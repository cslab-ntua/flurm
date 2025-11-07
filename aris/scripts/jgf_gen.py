#!/usr/bin/env python3
import argparse
import json
import os
from typing import List, Dict, Optional

def add_node(nodes: List[Dict], *, id_str: str, meta: Dict):
    nodes.append({
        "id": id_str,
        "metadata": meta,
    })

def add_edge(edges: List[Dict], *, src: str, dst: str, subsystem="containment"):
    edges.append({
        "source": src,
        "target": dst,
        "metadata": {"subsystem": subsystem},
    })

def gen_graph(cluster_name: str,
              hosts: List[str],
              sockets: int,
              cores: int,
              start_uid: int = 0,
              host_props: Optional[Dict[str, List[str]]] = None):
    """
    Build graph with optional properties per host (node). host_props maps host → list of property names.
    """
    if host_props is None:
        host_props = {}

    nodes = []
    edges = []
    uniq = start_uid

    # 1) Cluster node
    cluster_id = str(uniq); uniq += 1
    add_node(nodes,
        id_str=cluster_id,
        meta={
            "type": "cluster",
            "basename": "cluster",
            "name": cluster_name,
            "id": 0,
            "uniq_id": int(cluster_id),
            "rank": -1,
            "exclusive": False,
            "unit": "",
            "size": 1,
            "paths": { "containment": f"/{cluster_name}" },
        }
    )

    # 2) Hosts → sockets → cores
    for r, host in enumerate(hosts):
        node_id = str(uniq); uniq += 1
        # Build metadata for node; include properties if present
        node_meta = {
            "type": "node",
            "basename": host,
            "name": host,
            "id": -1,
            "uniq_id": int(node_id),
            "rank": r,
            "exclusive": False,
            "unit": "",
            "size": 1,
            "paths": { "containment": f"/{cluster_name}/{host}" },
        }
        if host in host_props:
            node_meta["properties"] = host_props[host]

        add_node(nodes, id_str=node_id, meta=node_meta)
        add_edge(edges, src=cluster_id, dst=node_id)

        for s in range(sockets):
            sock_name = f"socket{s}"
            sock_id = str(uniq); uniq += 1
            add_node(nodes,
                id_str=sock_id,
                meta={
                    "type": "socket",
                    "basename": "socket",
                    "name": sock_name,
                    "id": s,
                    "uniq_id": int(sock_id),
                    "rank": -1,
                    "exclusive": False,
                    "unit": "",
                    "size": 1,
                    "paths": { "containment": f"/{cluster_name}/{host}/{sock_name}" },
                    "properties": host_props[host] if host in host_props else {}
                },
            )
            add_edge(edges, src=node_id, dst=sock_id)

            # core IDs from s*cores to (s+1)*cores - 1
            for c in range(s * cores, (s + 1) * cores):
                core_name = f"core{c}"
                core_id = str(uniq); uniq += 1
                add_node(nodes,
                    id_str=core_id,
                    meta={
                        "type": "core",
                        "basename": "core",
                        "name": core_name,
                        "id": c,
                        "uniq_id": int(core_id),
                        "rank": -1,
                        "exclusive": False,
                        "unit": "",
                        "size": 1,
                        "paths": {
                            "containment": f"/{cluster_name}/{host}/{sock_name}/{core_name}"
                        },
                        "properties": host_props[host] if host in host_props else {}
                    },
                )
                add_edge(edges, src=sock_id, dst=core_id)

    return { "graph": { "nodes": nodes, "edges": edges } }

def parse_hosts(args) -> List[str]:
    if args.nodes:
        return [h.strip() for h in args.nodes.split(",") if h.strip()]
    return [f"{args.prefix}{i}" for i in range(args.nnodes)]

def parse_props(prop_args: List[str]) -> Dict[str, Dict[str, str]]:
    """
    Parse a list like ["node0:hi,hey", "node2:foo"] into
    { "node0": {"hi": "", "hey": ""}, "node2": {"foo": ""} }
    """
    mapping: Dict[str, Dict[str, str]] = {}
    for p in prop_args:
        if ":" not in p:
            raise ValueError(f"Property argument {p!r} is not in HOST:prop1,prop2 form")
        host, props = p.split(":", 1)
        props = props.strip()
        if not props:
            continue
        prop_list = [pr.strip() for pr in props.split(",") if pr.strip()]
        # Build the dict with empty-string values
        prop_map: Dict[str, str] = {}
        for pr in prop_list:
            prop_map[pr] = ""
        mapping[host] = prop_map
    return mapping


def main():
    ap = argparse.ArgumentParser(description="Generate JGF graph with optional host properties")
    ap.add_argument("--cluster-name", default="cluster0")
    ap.add_argument("--nodes", help="Comma-separated hostnames, e.g. n0,n1")
    ap.add_argument("--nnodes", type=int, default=1)
    ap.add_argument("--prefix", default="node")
    ap.add_argument("--sockets", type=int, default=1)
    ap.add_argument("--cores", type=int, default=12)
    ap.add_argument("--start-uniq-id", type=int, default=0)
    ap.add_argument("-p", "--prop", action="append",
                    help="Host properties map in form HOST:prop1,prop2 (can repeat)")
    ap.add_argument("-o", "--out", default="-", help="Output file (default stdout)")
    args = ap.parse_args()

    hosts = parse_hosts(args)
    host_props = parse_props(args.prop) if args.prop else {}

    graph = gen_graph(
        cluster_name=args.cluster_name,
        hosts=hosts,
        sockets=args.sockets,
        cores=args.cores,
        start_uid=args.start_uniq_id,
        host_props=host_props,
    )

    data = json.dumps(graph, indent=2)
    if args.out in ("-", "/dev/stdout"):
        print(data)
    else:
        parent = os.path.dirname(args.out)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(args.out, "w") as f:
            f.write(data)

if __name__ == "__main__":
    main()