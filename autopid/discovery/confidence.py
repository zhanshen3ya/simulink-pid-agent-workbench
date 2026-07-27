"""Evidence scoring for static and later dynamic loop verification."""

from typing import Iterable

from .types import ConfidenceBreakdown, Evidence


WEIGHTS = {
    "topology": 0.40,
    "dynamic": 0.25,
    "error_consistency": 0.20,
    "semantic": 0.10,
    "sample_time": 0.05,
}


def build_confidence(topology: float, semantic: float, dynamic: float,
                     error_consistency: float, unit: float, sample_time: float,
                     auto_accept: float = 0.85, minimum: float = 0.60,
                     dynamic_probe_performed: bool = False) -> ConfidenceBreakdown:
    """Calculate confidence without inflating missing dynamic evidence."""
    topology = _clip(topology)
    semantic = _clip(semantic)
    dynamic = _clip(dynamic)
    error_consistency = _clip(error_consistency)
    unit = _clip(unit)
    sample_time = _clip(sample_time)
    semantic_with_unit = min(1.0, 0.75 * semantic + 0.25 * unit)
    overall = (
        WEIGHTS["topology"] * topology
        + WEIGHTS["dynamic"] * dynamic
        + WEIGHTS["error_consistency"] * error_consistency
        + WEIGHTS["semantic"] * semantic_with_unit
        + WEIGHTS["sample_time"] * sample_time
    )
    if overall >= auto_accept and dynamic_probe_performed:
        decision = "auto_confirmed"
    elif overall >= minimum:
        decision = "suggested_confirmation"
    else:
        decision = "rejected"
    return ConfidenceBreakdown(topology, semantic, dynamic, error_consistency, unit,
                               sample_time, overall, decision, dynamic_probe_performed)


def evidence_score(items: Iterable[Evidence], kind: str) -> float:
    values = [item.score for item in items if item.kind == kind]
    return max(values) if values else 0.0


def _clip(value: float) -> float:
    return max(0.0, min(1.0, float(value)))
