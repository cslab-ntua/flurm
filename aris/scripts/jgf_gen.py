#!/usr/bin/env python3
import argparse
import json
import os
from typing import Any, Dict, List, Optional


def add_node(nodes: List[Dict[str, Any]], node_id: str, metadata: Dict[str, Any]) -> None:
    nodes.append({"id": node_id, "metadata": metadata})


def add_edge(
    edges: List[Dict[str, Any]],
    source: str,
    target: str,
    subsystem: str = "containment",
) -> None:
    edges.append({
        "source": source,
        "target": target,
        "metadata": {"subsystem": subsystem},
    })


def make_metadata(
    *,
    rtype: str,
    name: str,
    rid: int,
    uniq_id: int,
    path: str,
    rank: int = -1,
    properties: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    meta = {
        "type": rtype,
        "basename": rtype if rtype != "node" else name,
        "name": name,
        "id": rid,
        "uniq_id": uniq_id,
        "rank": rank,
        "exclusive": False,
        "unit": "",
        "size": 1,
        "paths": {"containment": path},
    }
    if properties:
        meta["properties"] = properties
    return meta


def parse_hosts(args: argparse.Namespace) -> List[str]:
    if args.nodes:
        return [host.strip() for host in args.nodes.split(",") if host.strip()]
    return [f"{args.prefix}{i}" for i in range(args.nnodes)]


def parse_props(prop_args: List[str]) -> Dict[str, Dict[str, str]]:
    """
    Parse:
      ["node0:fast,gpu", "node2:debug"]
    into:
      {
        "node0": {"fast": "", "gpu": ""},
        "node2": {"debug": ""}
      }
    """
    result: Dict[str, Dict[str, str]] = {}

    for item in prop_args:
        if ":" not in item:
            raise ValueError(f"Invalid property mapping {item!r}; expected HOST:prop1,prop2")

        host, props_raw = item.split(":", 1)
        host = host.strip()
        props_raw = props_raw.strip()

        if not host:
            raise ValueError(f"Invalid property mapping {item!r}; empty host")

        if not props_raw:
            continue

        props = {prop.strip(): "" for prop in props_raw.split(",") if prop.strip()}
        result[host] = props

    return result


def validate_topology(
    sockets: int,
    numanodes: int,
    cores: int,
    gpus_per_numanode: int,
) -> None:
    if sockets < 0:
        raise ValueError("sockets must be >= 0")
    if numanodes < 0:
        raise ValueError("numanodes must be >= 0")
    if numanodes > 0 and sockets == 0:
        raise ValueError("numanodes requires sockets > 0")
    if cores < 1:
        raise ValueError("cores must be >= 1")
    if gpus_per_numanode < 0:
        raise ValueError("gpus_per_numanode must be >= 0")


def next_id(counter: List[int]) -> str:
    value = str(counter[0])
    counter[0] += 1
    return value


def add_leaf_resources(
    *,
    nodes: List[Dict[str, Any]],
    edges: List[Dict[str, Any]],
    id_counter: List[int],
    cluster_name: str,
    host: str,
    parent_id: str,
    parent_path: str,
    core_start: int,
    core_count: int,
    gpu_count: int,
    properties: Optional[Dict[str, str]],
) -> None:
    for core_index in range(core_start, core_start + core_count):
        core_name = f"core{core_index}"
        core_id = next_id(id_counter)
        add_node(
            nodes,
            core_id,
            make_metadata(
                rtype="core",
                name=core_name,
                rid=core_index,
                uniq_id=int(core_id),
                path=f"{parent_path}/{core_name}",
                properties=properties,
            ),
        )
        add_edge(edges, parent_id, core_id)

    for gpu_index in range(gpu_count):
        gpu_name = f"gpu{gpu_index}"
        gpu_id = next_id(id_counter)
        add_node(
            nodes,
            gpu_id,
            make_metadata(
                rtype="gpu",
                name=gpu_name,
                rid=gpu_index,
                uniq_id=int(gpu_id),
                path=f"{parent_path}/{gpu_name}",
                properties=properties,
            ),
        )
        add_edge(edges, parent_id, gpu_id)


def gen_graph(
    cluster_name: str,
    hosts: List[str],
    sockets: int,
    cores: int,
    numanodes: int = 0,
    gpus_per_numanode: int = 0,
    start_uid: int = 0,
    host_props: Optional[Dict[str, Dict[str, str]]] = None,
) -> Dict[str, Any]:
    """
    Supported hierarchies:

    1) no sockets, no numanodes
       cluster
         └─ node
             ├─ core
             └─ gpu

    2) sockets, no numanodes
       cluster
         └─ node
             └─ socket
                 ├─ core
                 └─ gpu

    3) sockets and numanodes
       cluster
         └─ node
             └─ socket
                 └─ numanode
                     ├─ core
                     └─ gpu

    Semantics:
      - cores means:
          * cores per node if sockets == 0
          * cores per socket if sockets > 0 and numanodes == 0
          * cores per numanode if numanodes > 0
      - gpus_per_numanode means:
          * GPUs per node if sockets == 0
          * GPUs per socket if sockets > 0 and numanodes == 0
          * GPUs per numanode if numanodes > 0
    """
    host_props = host_props or {}
    validate_topology(sockets, numanodes, cores, gpus_per_numanode)

    nodes: List[Dict[str, Any]] = []
    edges: List[Dict[str, Any]] = []
    id_counter = [start_uid]

    cluster_id = next_id(id_counter)
    add_node(
        nodes,
        cluster_id,
        make_metadata(
            rtype="cluster",
            name=cluster_name,
            rid=0,
            uniq_id=int(cluster_id),
            path=f"/{cluster_name}",
        ),
    )

    for rank, host in enumerate(hosts):
        properties = host_props.get(host)

        node_id = next_id(id_counter)
        node_path = f"/{cluster_name}/{host}"
        add_node(
            nodes,
            node_id,
            make_metadata(
                rtype="node",
                name=host,
                rid=-1,
                uniq_id=int(node_id),
                path=node_path,
                rank=rank,
                properties=properties,
            ),
        )
        add_edge(edges, cluster_id, node_id)

        if sockets == 0:
            add_leaf_resources(
                nodes=nodes,
                edges=edges,
                id_counter=id_counter,
                cluster_name=cluster_name,
                host=host,
                parent_id=node_id,
                parent_path=node_path,
                core_start=0,
                core_count=cores,
                gpu_count=gpus_per_numanode,
                properties=properties,
            )
            continue

        for socket_index in range(sockets):
            socket_name = f"socket{socket_index}"
            socket_id = next_id(id_counter)
            socket_path = f"{node_path}/{socket_name}"

            add_node(
                nodes,
                socket_id,
                make_metadata(
                    rtype="socket",
                    name=socket_name,
                    rid=socket_index,
                    uniq_id=int(socket_id),
                    path=socket_path,
                    properties=properties,
                ),
            )
            add_edge(edges, node_id, socket_id)

            if numanodes == 0:
                add_leaf_resources(
                    nodes=nodes,
                    edges=edges,
                    id_counter=id_counter,
                    cluster_name=cluster_name,
                    host=host,
                    parent_id=socket_id,
                    parent_path=socket_path,
                    core_start=socket_index * cores,
                    core_count=cores,
                    gpu_count=gpus_per_numanode,
                    properties=properties,
                )
                continue

            cores_per_numanode = cores
            cores_per_socket = numanodes * cores_per_numanode

            for numa_index in range(numanodes):
                numa_name = f"numanode{numa_index}"
                numa_id = next_id(id_counter)
                numa_path = f"{socket_path}/{numa_name}"

                add_node(
                    nodes,
                    numa_id,
                    make_metadata(
                        rtype="numanode",
                        name=numa_name,
                        rid=numa_index,
                        uniq_id=int(numa_id),
                        path=numa_path,
                        properties=properties,
                    ),
                )
                add_edge(edges, socket_id, numa_id)

                core_start = socket_index * cores_per_socket + numa_index * cores_per_numanode

                add_leaf_resources(
                    nodes=nodes,
                    edges=edges,
                    id_counter=id_counter,
                    cluster_name=cluster_name,
                    host=host,
                    parent_id=numa_id,
                    parent_path=numa_path,
                    core_start=core_start,
                    core_count=cores_per_numanode,
                    gpu_count=gpus_per_numanode,
                    properties=properties,
                )

    return {"graph": {"nodes": nodes, "edges": edges}}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a JGF resource graph with optional sockets and numanodes"
    )
    parser.add_argument("--cluster-name", default="cluster0")
    parser.add_argument("--nodes", help="Comma-separated hostnames, e.g. n0,n1")
    parser.add_argument("--nnodes", type=int, default=1)
    parser.add_argument("--prefix", default="node")

    parser.add_argument(
        "--sockets",
        type=int,
        default=0,
        help="Sockets per node (0 disables sockets)",
    )
    parser.add_argument(
        "--numanodes",
        type=int,
        default=0,
        help="NUMA nodes per socket (requires --sockets > 0)",
    )
    parser.add_argument(
        "--cores",
        type=int,
        default=12,
        help="Cores per lowest CPU container",
    )
    parser.add_argument(
        "--gpus",
        type=int,
        default=0,
        help="GPUs per lowest container",
    )

    parser.add_argument("--start-uniq-id", type=int, default=0)
    parser.add_argument(
        "-p",
        "--prop",
        action="append",
        help="Host properties in form HOST:prop1,prop2",
    )
    parser.add_argument("-o", "--out", default="-", help="Output file (default stdout)")
    args = parser.parse_args()

    hosts = parse_hosts(args)
    host_props = parse_props(args.prop) if args.prop else {}

    graph = gen_graph(
        cluster_name=args.cluster_name,
        hosts=hosts,
        sockets=args.sockets,
        cores=args.cores,
        numanodes=args.numanodes,
        gpus_per_numanode=args.gpus,
        start_uid=args.start_uniq_id,
        host_props=host_props,
    )

    output = json.dumps(graph, indent=2)

    if args.out in ("-", "/dev/stdout"):
        print(output)
        return

    parent_dir = os.path.dirname(args.out)
    if parent_dir:
        os.makedirs(parent_dir, exist_ok=True)

    with open(args.out, "w") as f:
        f.write(output)


if __name__ == "__main__":
    main()