"""Signal alignment and switching-ripple-aware preprocessing."""

from typing import Any, Dict, Tuple

import numpy as np


def validate_series(time: Any, *signals: Any) -> Tuple[np.ndarray, ...]:
    """Convert equal-length finite one-dimensional arrays."""
    arrays = [np.asarray(time, dtype=float).reshape(-1)]
    arrays.extend(np.asarray(item, dtype=float).reshape(-1) for item in signals)
    if len(arrays[0]) < 3:
        raise ValueError("评价信号至少需要 3 个采样点。")
    if any(len(item) != len(arrays[0]) for item in arrays[1:]):
        raise ValueError("时间和评价信号长度必须一致。")
    if np.any(np.diff(arrays[0]) <= 0):
        raise ValueError("时间序列必须严格递增。")
    return tuple(arrays)


def moving_average(signal: np.ndarray, window: int) -> np.ndarray:
    """Return a centered moving average with edge padding."""
    window = int(max(1, window))
    if window <= 1 or len(signal) < 3:
        return signal.copy()
    if window % 2 == 0:
        window += 1
    window = min(window, len(signal) if len(signal) % 2 else len(signal) - 1)
    pad = window // 2
    padded = np.pad(signal, (pad, pad), mode="edge")
    kernel = np.ones(window, dtype=float) / window
    return np.convolve(padded, kernel, mode="valid")


def preprocess_output(output: np.ndarray, remove_switching_ripple: bool,
                      window: int) -> Tuple[np.ndarray, Dict[str, Any]]:
    """Separate low-frequency control response from raw high-frequency ripple."""
    if remove_switching_ripple:
        filtered = moving_average(output, window)
        method = "centered_moving_average"
    else:
        filtered = output.copy()
        method = "none"
    return filtered, {
        "method": method,
        "window_samples": int(window if remove_switching_ripple else 1),
        "raw_signal_preserved_for_ripple": True,
    }
