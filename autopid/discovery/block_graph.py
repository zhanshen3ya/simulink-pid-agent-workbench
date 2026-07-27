"""Block/Port/Signal graph built from a MATLAB or mock scan export."""

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, Iterable, List, Mapping, Optional


@dataclass
class GraphNode:
    id: str
    kind: str
    attributes: Dict[str, Any] = field(default_factory=dict)


@dataclass
class GraphEdge:
    source: str
    target: str
    kind: str
    attributes: Dict[str, Any] = field(default_factory=dict)


class BlockGraph:
    """A small dependency-free directed graph with typed Simulink nodes."""

    def __init__(self) -> None:
        self.nodes = {}  # type: Dict[str, GraphNode]
        self.edges = []  # type: List[GraphEdge]
        self._outgoing = {}  # type: Dict[str, List[GraphEdge]]
        self._incoming = {}  # type: Dict[str, List[GraphEdge]]

    def add_node(self, node: GraphNode) -> None:
        self.nodes[node.id] = node
        self._outgoing.setdefault(node.id, [])
        self._incoming.setdefault(node.id, [])

    def add_edge(self, edge: GraphEdge) -> None:
        if edge.source not in self.nodes or edge.target not in self.nodes:
            raise ValueError("图边引用了不存在的节点: %s -> %s" % (edge.source, edge.target))
        self.edges.append(edge)
        self._outgoing[edge.source].append(edge)
        self._incoming[edge.target].append(edge)

    def successors(self, node_id: str, kind: Optional[str] = None) -> List[GraphNode]:
        edges = self._outgoing.get(node_id, [])
        return [self.nodes[item.target] for item in edges if kind is None or item.kind == kind]

    def predecessors(self, node_id: str, kind: Optional[str] = None) -> List[GraphNode]:
        edges = self._incoming.get(node_id, [])
        return [self.nodes[item.source] for item in edges if kind is None or item.kind == kind]

    def outgoing_edges(self, node_id: str) -> List[GraphEdge]:
        return list(self._outgoing.get(node_id, []))

    def incoming_edges(self, node_id: str) -> List[GraphEdge]:
        return list(self._incoming.get(node_id, []))

    def nodes_of_kind(self, kind: str) -> List[GraphNode]:
        return [node for node in self.nodes.values() if node.kind == kind]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "nodes": [asdict(item) for item in self.nodes.values()],
            "edges": [asdict(item) for item in self.edges],
        }

    @classmethod
    def from_export(cls, export: Mapping[str, Any]) -> "BlockGraph":
        """Convert the stable scan JSON contract to a typed graph."""
        graph = cls()
        for block in _items(export.get("blocks")):
            graph.add_node(GraphNode(str(block["id"]), "block", dict(block)))
        for port in _items(export.get("ports")):
            graph.add_node(GraphNode(str(port["id"]), "port", dict(port)))
        for signal in _items(export.get("signals")):
            graph.add_node(GraphNode(str(signal["id"]), "signal", dict(signal)))

        for port in _items(export.get("ports")):
            block_id = str(port.get("block_id") or "")
            port_id = str(port["id"])
            if block_id not in graph.nodes:
                continue
            direction = str(port.get("direction") or "")
            if direction == "out":
                graph.add_edge(GraphEdge(block_id, port_id, "has_output_port"))
            else:
                graph.add_edge(GraphEdge(port_id, block_id, "has_input_port"))
        for signal in _items(export.get("signals")):
            signal_id = str(signal["id"])
            src = str(signal.get("src_port") or "")
            if src in graph.nodes:
                graph.add_edge(GraphEdge(src, signal_id, "drives_signal"))
            for dst in _list_values(signal.get("dst_ports")):
                dst_id = str(dst)
                if dst_id in graph.nodes:
                    graph.add_edge(GraphEdge(signal_id, dst_id, "feeds_port"))
        for virtual in _items(export.get("virtual_edges")):
            source = str(virtual.get("source") or "")
            target = str(virtual.get("target") or "")
            if source in graph.nodes and target in graph.nodes:
                graph.add_edge(GraphEdge(source, target, str(virtual.get("kind") or "virtual"), dict(virtual)))
        return graph


def _list_values(value: Any) -> List[Any]:
    if value is None or value == "":
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def _items(value: Any) -> Iterable[Mapping[str, Any]]:
    if value is None:
        return []
    if isinstance(value, Mapping):
        return [value]
    if isinstance(value, list):
        return [item for item in value if isinstance(item, Mapping)]
    raise ValueError("扫描导出字段必须是对象或数组。")
