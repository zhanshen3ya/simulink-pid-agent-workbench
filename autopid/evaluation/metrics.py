"""Scale-independent deterministic control metrics."""

from typing import Any, Dict, Optional

import numpy as np

from .preprocess import preprocess_output, validate_series
from .types import MetricResult


def compute_normalized_metrics(time: Any, reference: Any, output: Any,
                               control: Optional[Any] = None,
                               output_scale: Optional[float] = None,
                               control_min: Optional[float] = None,
                               control_max: Optional[float] = None,
                               control_scale: Optional[float] = None,
                               settling_band: float = 0.02,
                               tail_window_ratio: float = 0.10,
                               remove_switching_ripple: bool = True,
                               moving_average_window: int = 11) -> MetricResult:
    """Compute normalized tracking, control, and ripple metrics.

    Tail medians are used for final values. Filtered output is used for control
    performance while the raw signal remains the source of ripple metrics.
    """
    raw_control = np.zeros(len(np.asarray(time).reshape(-1))) if control is None else control
    t, r, y_raw, u = validate_series(time, reference, output, raw_control)
    y, preprocessing = preprocess_output(y_raw, remove_switching_ripple, moving_average_window)
    duration = max(float(t[-1] - t[0]), np.finfo(float).eps)
    tail_count = max(3, int(round(len(t) * float(tail_window_ratio))))
    tail = slice(len(t) - tail_count, len(t))
    initial_count = max(1, min(tail_count, len(t) // 5))
    initial_y = float(np.median(y[:initial_count]))
    final_reference = float(np.median(r[tail]))
    final_output = float(np.median(y[tail]))
    step_amplitude = abs(final_reference - float(np.median(r[:initial_count])))
    baseline_range = float(np.ptp(y))
    scale_y = max(step_amplitude, abs(float(output_scale or 0.0)), baseline_range, np.finfo(float).eps)
    if control_min is not None and control_max is not None:
        actuator_range = abs(float(control_max) - float(control_min))
    else:
        actuator_range = 0.0
    scale_u = max(actuator_range, abs(float(control_scale or 0.0)), float(np.ptp(u)), np.finfo(float).eps)
    error = r - y
    shifted_t = t - t[0]

    delta = final_reference - initial_y
    if delta >= 0:
        directional_peak = max(0.0, float(np.max(y) - final_reference))
    else:
        directional_peak = max(0.0, float(final_reference - np.min(y)))
    normalized_overshoot = directional_peak / scale_y
    band = max(float(settling_band) * scale_y, np.finfo(float).eps)
    outside = np.flatnonzero(np.abs(y - final_reference) > band)
    settling_time = float("inf") if len(outside) and outside[-1] == len(t) - 1 else (
        0.0 if not len(outside) else float(t[outside[-1] + 1] - t[0])
    )
    u0 = float(np.median(u[:initial_count]))
    saturation_ratio = 0.0
    if control_min is not None or control_max is not None:
        saturated = np.zeros(len(u), dtype=bool)
        tolerance = max(scale_u * 1e-6, np.finfo(float).eps)
        if control_min is not None:
            saturated |= u <= float(control_min) + tolerance
        if control_max is not None:
            saturated |= u >= float(control_max) - tolerance
        saturation_ratio = float(np.mean(saturated))
    raw_tail = y_raw[tail]
    filtered_tail = y[tail]
    ripple = raw_tail - filtered_tail

    values = {
        "niae": float(np.trapz(np.abs(error), t) / (scale_y * duration)),
        "nise": float(np.trapz(error ** 2, t) / (scale_y ** 2 * duration)),
        "nitae": float(np.trapz(shifted_t * np.abs(error), t) / (scale_y * duration ** 2)),
        "nrmse": float(np.sqrt(np.mean(error ** 2)) / scale_y),
        "normalized_steady_state_error": abs(final_reference - final_output) / scale_y,
        "normalized_overshoot": normalized_overshoot,
        "normalized_control_effort": float(np.mean(np.abs(u - u0)) / scale_u),
        "normalized_control_variation": float(np.sum(np.abs(np.diff(u))) / scale_u),
        "saturation_ratio": saturation_ratio,
        "settling_time": settling_time,
        "final_reference": final_reference,
        "final_output": final_output,
        "max_abs_output": float(np.max(np.abs(y_raw))),
        "max_abs_control": float(np.max(np.abs(u))),
        "raw_ripple_rms": float(np.sqrt(np.mean(ripple ** 2))),
        "tail_output_range": float(np.ptp(raw_tail)),
        "initial_error_abs": float(np.median(np.abs(error[:initial_count]))),
        "tail_error_abs": float(np.median(np.abs(error[tail]))),
    }
    preprocessing.update({
        "tail_window_ratio": float(tail_window_ratio),
        "tail_samples": tail_count,
        "settling_band": float(settling_band),
    })
    return MetricResult(values, {"scale_y": scale_y, "scale_u": scale_u, "duration": duration}, preprocessing)
