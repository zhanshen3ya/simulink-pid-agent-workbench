"""Evaluation profile selection and metric weights."""

from dataclasses import dataclass
from typing import Dict


@dataclass(frozen=True)
class EvaluationProfile:
    name: str
    weights: Dict[str, float]


PROFILES = {
    "generic_step": EvaluationProfile("generic_step", {
        "niae": 1.0, "nise": 0.4, "nitae": 0.8, "nrmse": 0.5,
        "normalized_steady_state_error": 1.2, "normalized_overshoot": 0.8,
        "normalized_control_effort": 0.2, "normalized_control_variation": 0.05,
    }),
    "voltage_regulation": EvaluationProfile("voltage_regulation", {
        "niae": 1.2, "nitae": 1.0, "normalized_steady_state_error": 1.5,
        "normalized_overshoot": 1.0, "raw_ripple_rms": 0.2,
        "saturation_ratio": 1.0, "normalized_control_variation": 0.05,
    }),
    "current_regulation": EvaluationProfile("current_regulation", {
        "niae": 1.2, "nrmse": 1.0, "normalized_overshoot": 1.0,
        "raw_ripple_rms": 0.3, "saturation_ratio": 1.0,
    }),
    "speed_control": EvaluationProfile("speed_control", {
        "nitae": 1.2, "normalized_steady_state_error": 1.5,
        "normalized_overshoot": 0.8, "normalized_control_effort": 0.3,
    }),
    "position_control": EvaluationProfile("position_control", {
        "niae": 1.0, "normalized_steady_state_error": 1.5,
        "normalized_overshoot": 1.0, "normalized_control_variation": 0.2,
    }),
    "disturbance_rejection": EvaluationProfile("disturbance_rejection", {
        "niae": 1.2, "nitae": 1.2, "normalized_steady_state_error": 1.2,
        "normalized_control_effort": 0.2,
    }),
}


def select_profile(requested: str, measurement_name: str = "", unit: str = "") -> EvaluationProfile:
    """Select a deterministic profile; names and units never override topology."""
    if requested and requested not in ("auto", "custom"):
        if requested not in PROFILES:
            raise ValueError("未知评价模式: %s" % requested)
        return PROFILES[requested]
    text = (measurement_name + " " + unit).lower()
    if any(word in text for word in ("volt", "vout", "vdc", "vbus", " v")):
        return PROFILES["voltage_regulation"]
    if any(word in text for word in ("current", "ibat", "ipv", "id", "iq", "amp", " a")):
        return PROFILES["current_regulation"]
    if any(word in text for word in ("speed", "rpm", "omega")):
        return PROFILES["speed_control"]
    if any(word in text for word in ("position", "angle", "theta")):
        return PROFILES["position_control"]
    return PROFILES["generic_step"]
