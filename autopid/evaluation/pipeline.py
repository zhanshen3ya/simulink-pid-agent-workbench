"""Single deterministic evaluation path for successful and failed simulations."""

from typing import Any, Tuple

import numpy as np

from .constraints import evaluate_hard_constraints
from .metrics import compute_normalized_metrics
from .profiles import EvaluationProfile, select_profile
from .scoring import score_feasible_result
from .types import GateResult, MetricResult


def evaluate_simulation(simulation: Any, config: Any,
                        measurement_name: str = "") -> Tuple[MetricResult, GateResult, EvaluationProfile]:
    """Return structured metrics and gates even when simulation data is invalid."""
    arrays = [
        np.asarray(simulation.time, dtype=float).reshape(-1),
        np.asarray(simulation.reference, dtype=float).reshape(-1),
        np.asarray(simulation.output, dtype=float).reshape(-1),
        np.asarray(simulation.control, dtype=float).reshape(-1),
    ]
    aligned = len(arrays[0]) >= 3 and all(len(item) == len(arrays[0]) for item in arrays[1:])
    finite = all(np.all(np.isfinite(item)) for item in arrays)
    if simulation.success and aligned and finite:
        metrics = compute_normalized_metrics(
            *arrays,
            output_scale=config.evaluation.output_scale,
            control_min=config.constraints.control_min,
            control_max=config.constraints.control_max,
            control_scale=config.evaluation.control_scale,
            settling_band=config.evaluation.settling_band,
            tail_window_ratio=config.evaluation.tail_window_ratio,
            remove_switching_ripple=config.evaluation.remove_switching_ripple,
            moving_average_window=config.evaluation.moving_average_window,
        )
    else:
        metrics = MetricResult({}, {}, {
            "valid": False,
            "reason": _invalid_reason(simulation.success, aligned, finite),
        })
    gate = evaluate_hard_constraints(
        *arrays, metrics, config.constraints,
        simulation.success, simulation.solver_error, simulation.extra_signals,
    )
    profile = select_profile(config.evaluation.profile, measurement_name)
    score_feasible_result(metrics, gate, profile)
    return metrics, gate, profile


def _invalid_reason(success: bool, aligned: bool, finite: bool) -> str:
    if not success:
        return "simulation_error"
    if not aligned:
        return "invalid_signal_shape"
    if not finite:
        return "non_finite"
    return "unknown"
