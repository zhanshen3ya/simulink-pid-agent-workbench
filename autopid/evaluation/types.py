"""Typed results for deterministic evaluation."""

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class MetricResult:
    values: Dict[str, float]
    scales: Dict[str, float]
    preprocessing: Dict[str, Any]

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class StabilityResult:
    stable: bool
    classification: str
    reasons: List[str] = field(default_factory=list)
    diagnostics: Dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class GateFailure:
    failure_type: str
    failure_reason: str
    abort_time: Optional[float] = None


@dataclass
class GateResult:
    feasible: bool
    failures: List[GateFailure]
    stability: StabilityResult
    score: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
