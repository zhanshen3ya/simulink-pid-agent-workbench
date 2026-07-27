"""High-level P0 static scan orchestration."""

from typing import Any, Mapping

from .block_graph import BlockGraph
from .controller_detector import detect_controllers
from .loop_resolver import resolve_loops
from .types import ModelDiscoveryResult


def analyze_scan(export: Mapping[str, Any], auto_accept: float = 0.85,
                 minimum: float = 0.60) -> ModelDiscoveryResult:
    """Detect standard controllers and resolve static negative-feedback loops."""
    if not isinstance(export, Mapping):
        raise ValueError("模型扫描结果必须是对象。")
    graph = BlockGraph.from_export(export)
    controllers = detect_controllers(export)
    loops = resolve_loops(export, graph, controllers, auto_accept, minimum)
    unresolved = list(export.get("unresolved") or [])
    if not controllers:
        unresolved.append("no_supported_standard_pid")
    if any(loop.confidence.decision == "rejected" for loop in loops):
        unresolved.append("one_or_more_loops_need_manual_mapping")
    return ModelDiscoveryResult(
        model_name=str(export.get("model_name") or export.get("modelName") or "unknown"),
        model_path=str(export.get("model_path") or export.get("modelPath") or ""),
        graph=graph.to_dict(),
        controllers=controllers,
        loops=loops,
        unresolved=sorted(set(unresolved)),
    )
