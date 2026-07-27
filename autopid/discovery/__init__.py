"""Static Simulink controller and loop discovery."""

from .model_scanner import analyze_scan
from .types import ControllerInfo, LoopCandidate, ModelDiscoveryResult

__all__ = ["analyze_scan", "ControllerInfo", "LoopCandidate", "ModelDiscoveryResult"]
