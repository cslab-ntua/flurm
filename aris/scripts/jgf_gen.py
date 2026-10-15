#!/usr/bin/env python3
import argparse
import json
import os
from typing import Any, Dict, List, Optional, Tuple


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


def next_id(counter: List[int]) -> str:
    value = str(counter[0])
    counter[0] += 1
    return value


def parse_hosts(args: argparse.Namespace) -> List[str]:
    if args.nodes:
        return [host.strip() for host in args.nodes.split(",") if host.strip()]
    return [f"{args.prefix}{i}" for i in range(args.nnodes)]


def parse_props(prop_args: List[str]) -> Dict[str, Dict[str, str]]:
    result: Dict[str, Dict[str, str]] = {}
    for item in prop_args:
        if ":" not in item:
            raise ValueError(f"Invalid property mapping {item!r}; expected HOST:prop1,prop2")

        host, props_raw = item.split(":", 1)
        host = host.strip()
        props_raw = props_raw.strip()

        if not host:
            raise ValueError(f"Invalid property mapping {item!r}; empty host")

        props = {prop.strip(): "" for prop in props_raw.split(",") if prop.strip()}
        result[host] = props
    return result


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


def parse_set_args(items: List[str]) -> List[List[Tuple[str, int]]]:
    """
    Parse repeated:
      --set socket=2
      --set numanode=2
      --set ccd=2
      --set core+gpu=4,1

    into:
      [
        [("socket", 2)],
        [("numanode", 2)],
        [("ccd", 2)],
        [("core", 4), ("gpu", 1)],
      ]

    Rules:
      - one --set = one hierarchy level
      - siblings at the same level are joined with '+'
      - sibling counts are comma-separated in matching order
    """
    levels: List[List[Tuple[str, int]]] = []

    for item in items:
        if "=" not in item:
            raise ValueError(f"Invalid --set value {item!r}; expected TYPE=COUNT or A+B=X,Y")

        lhs, rhs = item.split("=", 1)
        lhs = lhs.strip()
        rhs = rhs.strip()

        types = [t.strip() for t in lhs.split("+") if t.strip()]
        counts_raw = [c.strip() for c in rhs.split(",") if c.strip()]

        if not types:
            raise ValueError(f"Invalid --set value {item!r}; empty resource type")

        if len(types) != len(counts_raw):
            raise ValueError(
                f"Invalid --set value {item!r}; sibling type/count mismatch "
                f"({len(types)} types, {len(counts_raw)} counts)"
            )

        level: List[Tuple[str, int]] = []
        for rtype, raw_count in zip(types, counts_raw):
            try:
                count = int(raw_count)
            except ValueError as e:
                raise ValueError(
                    f"Invalid count {raw_count!r} in --set {item!r}; count must be integer"
                ) from e

            if count < 0:
                raise ValueError(
                    f"Invalid count {raw_count!r} in --set {item!r}; count must be >= 0"
                )

            level.append((rtype, count))

        levels.append(level)

    return levels


def add_resources_recursive(
    *,
    nodes: List[Dict[str, Any]],
    edges: List[Dict[str, Any]],
    id_counter: List[int],
    resource_id_counters: Dict[str, int],
    parent_id: str,
    parent_path: str,
    levels: List[List[Tuple[str, int]]],
    level_index: int,
    context: Dict[str, int],
    host_props: Optional[Dict[str, str]],
) -> None:
    if level_index >= len(levels):
        return

    current_level = levels[level_index]

    for rtype, count in current_level:
        for local_idx in range(count):
            rid = resource_id_counters.get(rtype, 0)
            resource_id_counters[rtype] = rid + 1

            name = f"{rtype}{rid}"
            node_id = next_id(id_counter)
            path = f"{parent_path}/{name}"

            local_context = dict(context)
            local_context[rtype] = rid

            add_node(
                nodes,
                node_id,
                make_metadata(
                    rtype=rtype,
                    name=name,
                    rid=rid,
                    uniq_id=int(node_id),
                    path=path,
                    properties=host_props,
                ),
            )
            add_edge(edges, parent_id, node_id)

            add_resources_recursive(
                nodes=nodes,
                edges=edges,
                id_counter=id_counter,
                resource_id_counters=resource_id_counters,
                parent_id=node_id,
                parent_path=path,
                levels=levels,
                level_index=level_index + 1,
                context=local_context,
                host_props=host_props,
            )


def gen_graph(
    *,
    cluster_name: str,
    hosts: List[str],
    levels: List[List[Tuple[str, int]]],
    start_uid: int = 0,
    host_props: Optional[Dict[str, Dict[str, str]]] = None,
) -> Dict[str, Any]:
    host_props = host_props or {}

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
        node_id = next_id(id_counter)
        node_path = f"/{cluster_name}/{host}"
        props = host_props.get(host)

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
                properties=props,
            ),
        )
        add_edge(edges, cluster_id, node_id)

        resource_id_counters: Dict[str, int] = {}

        add_resources_recursive(
            nodes=nodes,
            edges=edges,
            id_counter=id_counter,
            resource_id_counters=resource_id_counters,
            parent_id=node_id,
            parent_path=node_path,
            levels=levels,
            level_index=0,
            context={},
            host_props=props,
        )

    return {"graph": {"nodes": nodes, "edges": edges}}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a simple custom JGF resource graph from repeated --set levels"
    )
    parser.add_argument("--cluster-name", default="cluster0")
    parser.add_argument("--nodes", help="Comma-separated hostnames, e.g. n0,n1")
    parser.add_argument("--nnodes", type=int, default=1)
    parser.add_argument("--prefix", default="node")
    parser.add_argument(
        "--set",
        dest="sets",
        action="append",
        required=True,
        help=(
            "Define one hierarchy level. "
            "Examples: --set socket=2 --set numanode=2 --set ccd=2 --set core+gpu=4,1"
        ),
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
    levels = parse_set_args(args.sets)
    host_props = parse_props(args.prop) if args.prop else {}

    graph = gen_graph(
        cluster_name=args.cluster_name,
        hosts=hosts,
        levels=levels,
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