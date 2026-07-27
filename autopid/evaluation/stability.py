"""Conservative divergence and oscillation classification."""

from typing import Any, List, Tuple

import numpy as np

from .types import StabilityResult


def analyze_stability(time: Any, output: Any, reference: Any,
                      absolute_limit: float = float("inf")) -> StabilityResult:
    """Classify low-frequency stability without treating PWM ripple as divergence."""
    t = np.asarray(time, dtype=float).reshape(-1)
    y = np.asarray(output, dtype=float).reshape(-1)
    r = np.asarray(reference, dtype=float).reshape(-1)
    reasons = []  # type: List[str]
    if len(t) != len(y) or len(y) != len(r) or len(t) < 8:
        return StabilityResult(False, "invalid_data", ["insufficient_or_misaligned_samples"], {})
    if not (np.all(np.isfinite(t)) and np.all(np.isfinite(y)) and np.all(np.isfinite(r))):
        return StabilityResult(False, "non_finite", ["nan_or_inf"], {})
    max_abs = float(np.max(np.abs(y)))
    if max_abs > absolute_limit:
        reasons.append("absolute_output_limit_exceeded")

    error = r - y
    window = max(4, len(y) // 10)
    rms = _rolling_rms(error, window)
    first_rms = float(np.median(rms[:max(1, len(rms) // 4)]))
    tail_rms = float(np.median(rms[-max(1, len(rms) // 4):]))
    rms_growth = tail_rms / max(first_rms, np.finfo(float).eps)
    envelope_slope = float(np.polyfit(np.arange(len(rms)), rms, 1)[0] / max(np.mean(rms), np.finfo(float).eps))
    peaks = _peaks(np.abs(error - np.median(error[-window:])))
    peak_ratio = 0.0
    if len(peaks) >= 4:
        split = len(peaks) // 2
        peak_ratio = float(np.median(peaks[split:]) / max(np.median(peaks[:split]), np.finfo(float).eps))
    zero_crossings = int(np.sum(np.diff(np.signbit(error - np.median(error[-window:]))) != 0))
    high_frequency_ratio = zero_crossings / max(1, len(error) - 1)

    if "absolute_output_limit_exceeded" in reasons:
        classification = "divergence"
    elif rms_growth > 3.0 and envelope_slope > 0.001:
        classification = "divergence"
        reasons.append("rolling_rms_growing")
    elif len(peaks) >= 4 and peak_ratio > 1.10:
        classification = "growing_oscillation"
        reasons.append("peak_envelope_growing")
    elif len(peaks) >= 4 and peak_ratio >= 0.90 and tail_rms > 0.02 * max(np.ptp(r), np.ptp(y), 1.0):
        classification = "persistent_oscillation"
        reasons.append("peak_envelope_not_decaying")
    elif high_frequency_ratio > 0.25 and rms_growth < 1.5:
        classification = "switching_ripple"
    elif len(peaks) >= 4 and peak_ratio < 0.90:
        classification = "damped_oscillation"
    else:
        classification = "stable"
    stable = classification in ("stable", "damped_oscillation", "switching_ripple") and not reasons
    diagnostics = {
        "max_abs_output": max_abs,
        "first_window_rms": first_rms,
        "tail_window_rms": tail_rms,
        "rms_growth_ratio": rms_growth,
        "envelope_slope": envelope_slope,
        "peak_decay_ratio": peak_ratio,
        "zero_crossing_ratio": high_frequency_ratio,
    }
    return StabilityResult(stable, classification, reasons, diagnostics)


def _rolling_rms(signal: np.ndarray, window: int) -> np.ndarray:
    squared = signal ** 2
    kernel = np.ones(window, dtype=float) / window
    return np.sqrt(np.convolve(squared, kernel, mode="valid"))


def _peaks(signal: np.ndarray) -> np.ndarray:
    if len(signal) < 3:
        return np.array([], dtype=float)
    mask = (signal[1:-1] > signal[:-2]) & (signal[1:-1] >= signal[2:])
    return signal[1:-1][mask]
