"""Feasibility-first safety gates for PID candidates."""

from typing import Any, Mapping, Optional

import numpy as np

from .stability import analyze_stability
from .types import GateFailure, GateResult, MetricResult


def evaluate_hard_constraints(time: Any, reference: Any, output: Any, control: Any,
                              metrics: MetricResult, constraints: Any,
                              simulation_success: bool = True,
                              solver_error: Optional[str] = None,
                              extra_signals: Optional[Mapping[str, Any]] = None) -> GateResult:
    """Reject unsafe candidates before any scalar performance comparison."""
    failures = []
    values = metrics.values
    get = _reader(constraints)
    absolute_limit = _finite_or_inf(get("output_max"))
    lower_limit = get("output_min")
    stability = analyze_stability(time, output, reference, absolute_limit)

    if not simulation_success:
        failures.append(GateFailure("simulation_error", solver_error or "MATLAB/Simulink 仿真失败。"))
    arrays = [np.asarray(item, dtype=float) for item in (time, reference, output, control)]
    aligned = len(arrays[0]) >= 3 and all(len(item) == len(arrays[0]) for item in arrays[1:])
    finite = all(np.all(np.isfinite(item)) for item in arrays)
    if not aligned:
        failures.append(GateFailure("invalid_signal_shape", "时间和评价信号为空或长度不一致。"))
    if not finite:
        failures.append(GateFailure("non_finite", "信号包含 NaN 或 Inf。"))
    if not stability.stable:
        failures.append(GateFailure(stability.classification, "闭环稳定性检查未通过。"))
    # 原始信号无效时立即结束门禁，避免无意义指标进入综合评分.
    if not simulation_success or not aligned or not finite:
        return GateResult(False, failures, stability, None)

    y = np.asarray(output, dtype=float)
    u = np.asarray(control, dtype=float)
    if lower_limit is not None and np.min(y) < float(lower_limit):
        failures.append(GateFailure("output_below_limit", "输出低于绝对安全下限。", _first_time(time, y < float(lower_limit))))
    upper_limit = get("output_max")
    if upper_limit is not None and np.max(y) > float(upper_limit):
        failures.append(GateFailure("output_above_limit", "输出超过绝对安全上限。", _first_time(time, y > float(upper_limit))))
    control_min = get("control_min")
    control_max = get("control_max")
    if control_min is not None and np.min(u) < float(control_min) - 1e-12:
        failures.append(GateFailure("control_below_limit", "控制量低于执行器范围。", _first_time(time, u < float(control_min))))
    if control_max is not None and np.max(u) > float(control_max) + 1e-12:
        failures.append(GateFailure("control_above_limit", "控制量超过执行器范围。", _first_time(time, u > float(control_max))))

    checks = [
        ("max_saturation_ratio", "saturation_ratio", "persistent_saturation", "控制量饱和比例超限。"),
        ("max_overshoot", "normalized_overshoot", "overshoot", "归一化超调量超限。"),
        ("max_settling_time", "settling_time", "settling_time", "调节时间超限。"),
        ("max_steady_state_error", "normalized_steady_state_error", "steady_state_error", "归一化稳态误差超限。"),
    ]
    for config_name, metric_name, failure_type, reason in checks:
        limit = get(config_name)
        if limit is not None and values.get(metric_name, float("inf")) > float(limit):
            failures.append(GateFailure(failure_type, reason))
    if get("require_error_reduction", True) and values.get("tail_error_abs", 0.0) >= values.get("initial_error_abs", float("inf")):
        failures.append(GateFailure("error_not_reduced", "评价结束时误差没有减小。"))

    extras = extra_signals or {}
    max_current = get("max_current")
    if max_current is not None and "current" in extras and np.max(np.abs(extras["current"])) > float(max_current):
        failures.append(GateFailure("current_limit", "电流超过硬约束。"))
    max_voltage = get("max_voltage")
    if max_voltage is not None and "voltage" in extras and np.max(np.abs(extras["voltage"])) > float(max_voltage):
        failures.append(GateFailure("voltage_limit", "电压超过硬约束。"))
    return GateResult(not failures, failures, stability, None)


def _reader(source: Any):
    if isinstance(source, Mapping):
        return lambda name, fallback=None: source.get(name, fallback)
    return lambda name, fallback=None: getattr(source, name, fallback)


def _finite_or_inf(value: Any) -> float:
    if value is None:
        return float("inf")
    return abs(float(value))


def _first_time(time: Any, mask: np.ndarray) -> Optional[float]:
    indexes = np.flatnonzero(mask)
    return float(np.asarray(time)[indexes[0]]) if len(indexes) else None
