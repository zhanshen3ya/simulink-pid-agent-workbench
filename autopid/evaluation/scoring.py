"""Performance scoring that accepts feasible candidates only."""

from typing import Optional

from .profiles import EvaluationProfile
from .types import GateResult, MetricResult


def score_feasible_result(metrics: MetricResult, gate: GateResult,
                          profile: EvaluationProfile) -> Optional[float]:
    """Return a scalar score only after all hard constraints pass."""
    if not gate.feasible:
        gate.score = None
        return None
    score = 0.0
    for name, weight in profile.weights.items():
        value = metrics.values.get(name)
        if value is None or value != value or abs(value) == float("inf"):
            gate.feasible = False
            gate.score = None
            return None
        if name == "raw_ripple_rms":
            value = value / max(metrics.scales.get("scale_y", 1.0), 1e-12)
        score += float(weight) * float(value)
    gate.score = score
    return score
