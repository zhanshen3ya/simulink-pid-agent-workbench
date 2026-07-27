"""Typed discovery results shared by MATLAB, Mock Runner, and CLI."""

from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional


@dataclass
class Evidence:
    """One observable fact used by a discovery decision."""
    kind: str
    description: str
    score: float
    source: str = "static_topology"


@dataclass
class ConfidenceBreakdown:
    """Weighted confidence components for a signal mapping."""
    topology_score: float = 0.0
    semantic_score: float = 0.0
    dynamic_response_score: float = 0.0
    error_consistency_score: float = 0.0
    unit_score: float = 0.0
    sample_time_score: float = 0.0
    overall_confidence: float = 0.0
    decision: str = "rejected"
    dynamic_probe_performed: bool = False


@dataclass
class ControllerInfo:
    """Normalized metadata for a standard Simulink PID-family block."""
    block_id: str
    path: str
    controller_type: str
    mode: str
    time_domain: str
    sample_time: Optional[str]
    form: Optional[str]
    parameters: Dict[str, Any]
    output_limits: Dict[str, Any]
    anti_windup: Dict[str, Any]
    input_ports: List[str]
    output_ports: List[str]
    parent_system: str
    library_link: bool
    safe_to_modify: bool
    adapter: str = "standard_pid"


@dataclass
class SignalRoleMapping:
    """Resolved signal IDs for one feedback loop."""
    reference_signal: Optional[str] = None
    measurement_signal: Optional[str] = None
    error_signal: Optional[str] = None
    raw_control_signal: Optional[str] = None
    actuator_signal: Optional[str] = None
    disturbance_signal: Optional[str] = None
    signal_source: str = "auto"


@dataclass
class LoopCandidate:
    """A static feedback-loop candidate and the evidence behind it."""
    controller: ControllerInfo
    signals: SignalRoleMapping
    confidence: ConfidenceBreakdown
    evidence: List[Evidence] = field(default_factory=list)
    unresolved: List[str] = field(default_factory=list)
    loop_level: str = "single"
    parent_loop: Optional[str] = None
    child_loop: Optional[str] = None
    recommended_tuning_order: Optional[int] = 1
    coupling_risk: str = "low"

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ModelDiscoveryResult:
    """Complete P0 static-discovery output."""
    model_name: str
    model_path: str
    graph: Dict[str, Any]
    controllers: List[ControllerInfo]
    loops: List[LoopCandidate]
    unresolved: List[str] = field(default_factory=list)
    schema_version: str = "autopid.discovery.v1"

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)
