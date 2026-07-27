"""Resolve standard negative-feedback loops from the typed block graph."""

from typing import Any, Dict, List, Mapping, Optional, Tuple

from .block_graph import BlockGraph, GraphNode
from .confidence import build_confidence
from .types import ControllerInfo, Evidence, LoopCandidate, SignalRoleMapping

REFERENCE_WORDS = ("ref", "reference", "setpoint", "command", "cmd", "vref", "iref")
MEASUREMENT_WORDS = ("vout", "output", "measurement", "feedback", "vdc", "vbus", "current", "speed", "position")
CONTROL_WORDS = ("duty", "pwm", "modulation", "torque_cmd", "voltage_cmd", "current_cmd", "control")
ACTUATOR_BLOCKS = ("saturation", "pwm", "ratelimiter", "deadzone", "quantizer")


def resolve_loops(export: Mapping[str, Any], graph: BlockGraph,
                  controllers: List[ControllerInfo], auto_accept: float = 0.85,
                  minimum: float = 0.60) -> List[LoopCandidate]:
    loops = [_resolve_one(export, graph, item, auto_accept, minimum) for item in controllers]
    _mark_cascade(graph, loops)
    return loops


def _resolve_one(export: Mapping[str, Any], graph: BlockGraph, controller: ControllerInfo,
                 auto_accept: float, minimum: float) -> LoopCandidate:
    evidence = []  # type: List[Evidence]
    unresolved = []  # type: List[str]
    mapping = SignalRoleMapping()
    input_port = controller.input_ports[0] if controller.input_ports else _port_for_block(graph, controller.block_id, "in")
    output_port = controller.output_ports[0] if controller.output_ports else _port_for_block(graph, controller.block_id, "out")

    error_signal = _signal_feeding_port(graph, input_port)
    if error_signal:
        mapping.error_signal = error_signal.id
        evidence.append(Evidence("topology", "PID 输入端存在直接误差信号。", 0.7))
    else:
        unresolved.append("controller_input_signal_unresolved")

    # 拓扑证据优先；名称和单位只能提高置信度，不能改写反馈方向.
    sum_block = _source_block_of_signal(graph, error_signal)
    signs = ""
    if sum_block and str(sum_block.attributes.get("block_type", "")).lower() in ("sum", "add"):
        signs = str((sum_block.attributes.get("parameters") or {}).get("Inputs") or sum_block.attributes.get("inputs") or "+-")
        positive, negative = _sum_input_signals(graph, sum_block.id, signs)
        if positive:
            mapping.reference_signal = positive.id
        if negative:
            mapping.measurement_signal = negative.id
        if positive and negative:
            evidence.append(Evidence("topology", "误差 Sum 块同时存在正向参考支路和负向反馈支路。", 1.0))
            evidence.append(Evidence("error_consistency", "静态符号关系满足 e = r - y。", 1.0))
        else:
            unresolved.append("sum_sign_or_input_unresolved")
    else:
        unresolved.append("error_sum_block_unresolved")

    raw_signal = _signal_from_port(graph, output_port)
    if raw_signal:
        mapping.raw_control_signal = raw_signal.id
        mapping.actuator_signal = _resolve_actuator_signal(graph, raw_signal).id
        evidence.append(Evidence("topology", "PID 输出端控制信号可追踪。", 1.0))
    else:
        unresolved.append("controller_output_signal_unresolved")

    semantic = _semantic_score(graph, mapping)
    unit = _unit_score(graph, mapping)
    topology = 1.0 if mapping.reference_signal and mapping.measurement_signal and mapping.raw_control_signal else 0.45
    consistency = 1.0 if mapping.reference_signal and mapping.measurement_signal and "+" in signs and "-" in signs else 0.0
    sample = _sample_score(graph, controller, mapping)
    confidence = build_confidence(topology, semantic, 0.0, consistency, unit, sample,
                                  auto_accept, minimum, False)
    if not confidence.dynamic_probe_performed:
        unresolved.append("dynamic_probe_not_run")
    if not controller.safe_to_modify:
        unresolved.append("controller_not_safe_to_modify")
    return LoopCandidate(controller, mapping, confidence, evidence, sorted(set(unresolved)))


def _port_for_block(graph: BlockGraph, block_id: str, direction: str) -> Optional[str]:
    for node in graph.nodes_of_kind("port"):
        if str(node.attributes.get("block_id")) == block_id and str(node.attributes.get("direction")) == direction:
            return node.id
    return None


def _signal_feeding_port(graph: BlockGraph, port_id: Optional[str]) -> Optional[GraphNode]:
    if not port_id:
        return None
    candidates = graph.predecessors(port_id, "feeds_port")
    return candidates[0] if candidates else None


def _signal_from_port(graph: BlockGraph, port_id: Optional[str]) -> Optional[GraphNode]:
    if not port_id:
        return None
    candidates = graph.successors(port_id, "drives_signal")
    return candidates[0] if candidates else None


def _source_block_of_signal(graph: BlockGraph, signal: Optional[GraphNode]) -> Optional[GraphNode]:
    if signal is None:
        return None
    ports = graph.predecessors(signal.id, "drives_signal")
    if not ports:
        return None
    blocks = graph.predecessors(ports[0].id, "has_output_port")
    return blocks[0] if blocks else None


def _sum_input_signals(graph: BlockGraph, block_id: str, signs: str) -> Tuple[Optional[GraphNode], Optional[GraphNode]]:
    ports = [item for item in graph.nodes_of_kind("port")
             if str(item.attributes.get("block_id")) == block_id and item.attributes.get("direction") == "in"]
    ports.sort(key=lambda item: int(item.attributes.get("index") or 0))
    clean = "".join(char for char in signs if char in "+-")
    positive = None
    negative = None
    for offset, port in enumerate(ports):
        signal = _signal_feeding_port(graph, port.id)
        sign = clean[offset] if offset < len(clean) else "+"
        if signal and sign == "+" and positive is None:
            positive = signal
        if signal and sign == "-" and negative is None:
            negative = signal
    return positive, negative


def _resolve_actuator_signal(graph: BlockGraph, raw: GraphNode) -> GraphNode:
    for destination_port in graph.successors(raw.id, "feeds_port"):
        blocks = graph.successors(destination_port.id, "has_input_port")
        if not blocks:
            continue
        block = blocks[0]
        descriptor = (str(block.attributes.get("block_type") or "") + " " +
                      str(block.attributes.get("name") or "")).lower()
        if any(word in descriptor for word in ACTUATOR_BLOCKS):
            out_port = _port_for_block(graph, block.id, "out")
            processed = _signal_from_port(graph, out_port)
            if processed:
                return processed
    return raw


def _semantic_score(graph: BlockGraph, mapping: SignalRoleMapping) -> float:
    checks = [
        (_signal_text(graph, mapping.reference_signal), REFERENCE_WORDS),
        (_signal_text(graph, mapping.measurement_signal), MEASUREMENT_WORDS),
        (_signal_text(graph, mapping.actuator_signal), CONTROL_WORDS),
    ]
    return sum(1.0 for text, words in checks if any(word in text for word in words)) / len(checks)


def _unit_score(graph: BlockGraph, mapping: SignalRoleMapping) -> float:
    reference = _signal_unit(graph, mapping.reference_signal)
    measurement = _signal_unit(graph, mapping.measurement_signal)
    if not reference or not measurement:
        return 0.5
    return 1.0 if reference.lower() == measurement.lower() else 0.0


def _sample_score(graph: BlockGraph, controller: ControllerInfo, mapping: SignalRoleMapping) -> float:
    values = [controller.sample_time]
    for signal_id in (mapping.reference_signal, mapping.measurement_signal):
        node = graph.nodes.get(signal_id or "")
        values.append(str(node.attributes.get("sample_time") or "") if node else "")
    populated = [item for item in values if item not in (None, "", "-1")]
    return 1.0 if len(set(populated)) <= 1 and populated else 0.5


def _signal_text(graph: BlockGraph, signal_id: Optional[str]) -> str:
    node = graph.nodes.get(signal_id or "")
    if not node:
        return ""
    return (str(node.attributes.get("name") or "") + " " + str(node.attributes.get("description") or "")).lower()


def _signal_unit(graph: BlockGraph, signal_id: Optional[str]) -> str:
    node = graph.nodes.get(signal_id or "")
    return str(node.attributes.get("unit") or "") if node else ""


def _mark_cascade(graph: BlockGraph, loops: List[LoopCandidate]) -> None:
    by_reference = {item.signals.reference_signal: item for item in loops if item.signals.reference_signal}
    for outer in loops:
        output_id = outer.signals.actuator_signal or outer.signals.raw_control_signal
        if not output_id:
            continue
        for inner in loops:
            if inner is outer or not inner.signals.reference_signal:
                continue
            if output_id == inner.signals.reference_signal or _signal_reaches_signal(graph, output_id, inner.signals.reference_signal, 8):
                outer.loop_level = "outer"
                outer.child_loop = inner.controller.path
                outer.recommended_tuning_order = 2
                inner.loop_level = "inner"
                inner.parent_loop = outer.controller.path
                inner.recommended_tuning_order = 1


def _signal_reaches_signal(graph: BlockGraph, source: str, target: str, max_depth: int) -> bool:
    queue = [(source, 0)]
    visited = {source}
    transparent = ("signal", "port")
    while queue:
        node_id, depth = queue.pop(0)
        if depth >= max_depth:
            continue
        for node in graph.successors(node_id):
            if node.id == target:
                return True
            if node.id in visited:
                continue
            if node.kind in transparent or _transparent_block(node):
                visited.add(node.id)
                queue.append((node.id, depth + 1))
    return False


def _transparent_block(node: GraphNode) -> bool:
    descriptor = str(node.attributes.get("block_type") or "").lower()
    return descriptor in ("gain", "saturation", "ratetransition", "goto", "from", "inport", "outport")
