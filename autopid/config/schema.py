"""Configuration schema for P0 discovery and deterministic validation.

The implementation uses dataclasses instead of Pydantic so the package remains
usable with the Python 3.7 installation bundled on the reference workstation.
Unknown fields are rejected and YAML is loaded with ``safe_load`` only.
"""

from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional

import yaml


class ConfigError(ValueError):
    """Raised when a configuration file is invalid."""


def _mapping(value: Any, label: str) -> Dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, Mapping):
        raise ConfigError("%s 必须是对象。" % label)
    return dict(value)


def _reject_unknown(data: Mapping[str, Any], allowed: List[str], label: str) -> None:
    unknown = sorted(set(data) - set(allowed))
    if unknown:
        raise ConfigError("%s 包含未知字段: %s" % (label, ", ".join(unknown)))


def _number(value: Any, label: str, minimum: Optional[float] = None) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        raise ConfigError("%s 必须是数字。" % label)
    if result != result or abs(result) == float("inf"):
        raise ConfigError("%s 必须是有限数字。" % label)
    if minimum is not None and result < minimum:
        raise ConfigError("%s 不能小于 %s。" % (label, minimum))
    return result


def _integer(value: Any, label: str, minimum: int = 0) -> int:
    result = _number(value, label, float(minimum))
    if result != int(result):
        raise ConfigError("%s 必须是整数。" % label)
    return int(result)


def _boolean(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise ConfigError("%s 必须是 true 或 false。" % label)
    return value


def _optional_number(value: Any, label: str) -> Optional[float]:
    return None if value is None else _number(value, label)


@dataclass
class ProjectConfig:
    name: str = "autopid-project"
    random_seed: int = 42


@dataclass
class ModelConfig:
    file: str = "mock:buck"
    stop_time: float = 1.0
    backup_original: bool = True
    write_result_to_copy: bool = True


@dataclass
class ControllerConfig:
    mode: str = "auto"
    block_path: Optional[str] = None
    block_paths: List[str] = field(default_factory=list)
    type: str = "auto"
    allow_anti_windup_change: bool = False


@dataclass
class SignalsConfig:
    mode: str = "auto"
    reference: Optional[str] = None
    measurement: Optional[str] = None
    error: Optional[str] = None
    raw_control: Optional[str] = None
    actuator_control: Optional[str] = None
    current: Optional[str] = None


@dataclass
class DiscoveryConfig:
    enable_dynamic_probe: bool = False
    auto_accept_confidence: float = 0.85
    minimum_confidence: float = 0.60
    max_probe_amplitude_ratio: float = 0.02


@dataclass
class EvaluationConfig:
    profile: str = "auto"
    settling_band: float = 0.02
    tail_window_ratio: float = 0.10
    use_normalized_metrics: bool = True
    remove_switching_ripple: bool = True
    moving_average_window: int = 11
    output_scale: Optional[float] = None
    control_scale: Optional[float] = None


@dataclass
class ConstraintConfig:
    output_min: Optional[float] = None
    output_max: Optional[float] = None
    control_min: Optional[float] = None
    control_max: Optional[float] = None
    max_saturation_ratio: Optional[float] = 0.20
    max_overshoot: Optional[float] = None
    max_settling_time: Optional[float] = None
    max_steady_state_error: Optional[float] = None
    max_current: Optional[float] = None
    max_voltage: Optional[float] = None
    require_error_reduction: bool = True


@dataclass
class OptimizationConfig:
    pipeline: List[str] = field(default_factory=lambda: ["initial_design", "differential_evolution"])
    max_trials: int = 200
    parallel_workers: int = 1
    resume: bool = True
    cache: bool = True


@dataclass
class RobustnessConfig:
    enabled: bool = False
    worst_case_weight: float = 0.5
    validation_holdout: bool = True


@dataclass
class DeploymentConfig:
    apply_best: bool = False
    overwrite_original: bool = False
    require_validation_pass: bool = True


@dataclass
class AutoPidConfig:
    project: ProjectConfig = field(default_factory=ProjectConfig)
    model: ModelConfig = field(default_factory=ModelConfig)
    controller: ControllerConfig = field(default_factory=ControllerConfig)
    signals: SignalsConfig = field(default_factory=SignalsConfig)
    discovery: DiscoveryConfig = field(default_factory=DiscoveryConfig)
    evaluation: EvaluationConfig = field(default_factory=EvaluationConfig)
    constraints: ConstraintConfig = field(default_factory=ConstraintConfig)
    optimization: OptimizationConfig = field(default_factory=OptimizationConfig)
    robustness: RobustnessConfig = field(default_factory=RobustnessConfig)
    deployment: DeploymentConfig = field(default_factory=DeploymentConfig)

    def to_dict(self) -> Dict[str, Any]:
        """Return a JSON/YAML-friendly resolved configuration."""
        return asdict(self)

    @classmethod
    def from_mapping(cls, source: Mapping[str, Any]) -> "AutoPidConfig":
        """Validate nested configuration and translate supported legacy fields."""
        if not isinstance(source, Mapping):
            raise ConfigError("配置文件根节点必须是对象。")
        data = _translate_legacy(dict(source))
        sections = ["project", "model", "controller", "signals", "discovery", "evaluation",
                    "constraints", "optimization", "robustness", "deployment"]
        _reject_unknown(data, sections, "配置")

        project = _build(ProjectConfig, data.get("project"), "project")
        model = _build(ModelConfig, data.get("model"), "model")
        controller = _build(ControllerConfig, data.get("controller"), "controller")
        signals = _build(SignalsConfig, data.get("signals"), "signals")
        discovery = _build(DiscoveryConfig, data.get("discovery"), "discovery")
        evaluation = _build(EvaluationConfig, data.get("evaluation"), "evaluation")
        constraints = _build(ConstraintConfig, data.get("constraints"), "constraints")
        optimization = _build(OptimizationConfig, data.get("optimization"), "optimization")
        robustness = _build(RobustnessConfig, data.get("robustness"), "robustness")
        deployment = _build(DeploymentConfig, data.get("deployment"), "deployment")

        model.stop_time = _number(model.stop_time, "model.stop_time", 0.0)
        project.random_seed = _integer(project.random_seed, "project.random_seed", 0)
        model.backup_original = _boolean(model.backup_original, "model.backup_original")
        model.write_result_to_copy = _boolean(model.write_result_to_copy, "model.write_result_to_copy")
        controller.allow_anti_windup_change = _boolean(
            controller.allow_anti_windup_change, "controller.allow_anti_windup_change"
        )
        discovery.enable_dynamic_probe = _boolean(
            discovery.enable_dynamic_probe, "discovery.enable_dynamic_probe"
        )
        discovery.auto_accept_confidence = _number(discovery.auto_accept_confidence, "discovery.auto_accept_confidence", 0.0)
        discovery.minimum_confidence = _number(discovery.minimum_confidence, "discovery.minimum_confidence", 0.0)
        discovery.max_probe_amplitude_ratio = _number(discovery.max_probe_amplitude_ratio, "discovery.max_probe_amplitude_ratio", 0.0)
        if not 0 <= discovery.minimum_confidence <= discovery.auto_accept_confidence <= 1:
            raise ConfigError("识别置信度必须满足 0 <= minimum <= auto_accept <= 1。")
        evaluation.tail_window_ratio = _number(evaluation.tail_window_ratio, "evaluation.tail_window_ratio", 0.0)
        evaluation.settling_band = _number(evaluation.settling_band, "evaluation.settling_band", 0.0)
        if not 0 < evaluation.tail_window_ratio <= 0.5:
            raise ConfigError("evaluation.tail_window_ratio 必须在 (0, 0.5]。")
        evaluation.moving_average_window = _integer(
            evaluation.moving_average_window, "evaluation.moving_average_window", 1
        )
        evaluation.use_normalized_metrics = _boolean(
            evaluation.use_normalized_metrics, "evaluation.use_normalized_metrics"
        )
        evaluation.remove_switching_ripple = _boolean(
            evaluation.remove_switching_ripple, "evaluation.remove_switching_ripple"
        )
        evaluation.output_scale = _optional_number(evaluation.output_scale, "evaluation.output_scale")
        evaluation.control_scale = _optional_number(evaluation.control_scale, "evaluation.control_scale")
        for name in (
            "output_min", "output_max", "control_min", "control_max",
            "max_saturation_ratio", "max_overshoot", "max_settling_time",
            "max_steady_state_error", "max_current", "max_voltage",
        ):
            setattr(constraints, name, _optional_number(
                getattr(constraints, name), "constraints.%s" % name
            ))
        constraints.require_error_reduction = _boolean(
            constraints.require_error_reduction, "constraints.require_error_reduction"
        )
        optimization.max_trials = _integer(optimization.max_trials, "optimization.max_trials", 1)
        optimization.parallel_workers = _integer(
            optimization.parallel_workers, "optimization.parallel_workers", 1
        )
        optimization.resume = _boolean(optimization.resume, "optimization.resume")
        optimization.cache = _boolean(optimization.cache, "optimization.cache")
        robustness.enabled = _boolean(robustness.enabled, "robustness.enabled")
        robustness.validation_holdout = _boolean(
            robustness.validation_holdout, "robustness.validation_holdout"
        )
        robustness.worst_case_weight = _number(
            robustness.worst_case_weight, "robustness.worst_case_weight", 0.0
        )
        deployment.apply_best = _boolean(deployment.apply_best, "deployment.apply_best")
        deployment.overwrite_original = _boolean(
            deployment.overwrite_original, "deployment.overwrite_original"
        )
        deployment.require_validation_pass = _boolean(
            deployment.require_validation_pass, "deployment.require_validation_pass"
        )
        if constraints.output_min is not None and constraints.output_max is not None:
            if constraints.output_min >= constraints.output_max:
                raise ConfigError("constraints.output_min 必须小于 output_max。")
        if constraints.control_min is not None and constraints.control_max is not None:
            if constraints.control_min >= constraints.control_max:
                raise ConfigError("constraints.control_min 必须小于 control_max。")
        if deployment.overwrite_original:
            raise ConfigError("P0 禁止覆盖原始 Simulink 模型，请将 deployment.overwrite_original 设为 false。")
        if controller.mode not in ("auto", "manual"):
            raise ConfigError("controller.mode 只能是 auto 或 manual。")
        if signals.mode not in ("auto", "manual"):
            raise ConfigError("signals.mode 只能是 auto 或 manual。")
        if signals.mode == "manual" and not (signals.reference and signals.measurement):
            raise ConfigError("手动信号模式至少需要 reference 和 measurement。")
        return cls(project, model, controller, signals, discovery, evaluation,
                   constraints, optimization, robustness, deployment)


def _build(kind: Any, value: Any, label: str) -> Any:
    data = _mapping(value, label)
    allowed = list(kind.__dataclass_fields__.keys())
    _reject_unknown(data, allowed, label)
    try:
        return kind(**data)
    except TypeError as error:
        raise ConfigError("%s 配置无效: %s" % (label, error))


def _translate_legacy(source: Dict[str, Any]) -> Dict[str, Any]:
    """Translate the existing flat gateway JSON fields without changing callers."""
    nested_names = {"project", "model", "controller", "signals", "discovery", "evaluation",
                    "constraints", "optimization", "robustness", "deployment"}
    if set(source).issubset(nested_names):
        return source
    legacy_allowed = {
        "modelPath", "stopTime", "pidBlocks", "referenceSignalName", "outputSignalName",
        "controlSignalName", "currentSignalName", "randomSeed", "maxIterations",
        "numCandidates", "stopOnFirstPass", "useParallel", "targets", "controlUpperLimit",
        "runId", "workingDirectory", "projectRoot", "projectPath", "ai",
        "availableSignalNames", "signalMappingConfirmed", "evaluationPidPath"
    }
    unknown = sorted(set(source) - legacy_allowed - nested_names)
    if unknown:
        raise ConfigError("旧配置包含未知字段: %s" % ", ".join(unknown))
    result = {name: dict(source.get(name) or {}) for name in nested_names if name in source}
    result.setdefault("project", {})
    result.setdefault("model", {})
    result.setdefault("controller", {})
    result.setdefault("signals", {})
    result.setdefault("evaluation", {})
    result.setdefault("constraints", {})
    result.setdefault("optimization", {})
    if "modelPath" in source:
        result["model"]["file"] = source["modelPath"]
    if "stopTime" in source:
        result["model"]["stop_time"] = source["stopTime"]
    if "randomSeed" in source:
        result["project"]["random_seed"] = source["randomSeed"]
    blocks = source.get("pidBlocks") or []
    if blocks:
        result["controller"]["block_paths"] = [str(item.get("path", "")) for item in blocks if item.get("path")]
        result["controller"]["block_path"] = result["controller"]["block_paths"][0] if result["controller"]["block_paths"] else None
    signal_map = {
        "referenceSignalName": "reference", "outputSignalName": "measurement",
        "controlSignalName": "actuator_control", "currentSignalName": "current"
    }
    for old, new in signal_map.items():
        if source.get(old):
            result["signals"][new] = source[old]
            result["signals"]["mode"] = "manual"
    if "maxIterations" in source:
        result["optimization"]["max_trials"] = source["maxIterations"]
    if "useParallel" in source:
        result["optimization"]["parallel_workers"] = 4 if source["useParallel"] else 1
    targets = source.get("targets") or {}
    target_map = {
        "overshootPctMax": "max_overshoot", "settlingTimeMax": "max_settling_time",
        "steadyStateErrorAbsMax": "max_steady_state_error",
        "maxAbsCurrentMax": "max_current", "controlSaturationFractionMax": "max_saturation_ratio"
    }
    for old, new in target_map.items():
        if old in targets:
            result["constraints"][new] = targets[old]
    if "controlUpperLimit" in source:
        result["constraints"]["control_max"] = source["controlUpperLimit"]
    return result


def load_config(path: str) -> AutoPidConfig:
    """Load YAML or JSON using safe parsers and return a validated schema."""
    config_path = Path(path)
    if not config_path.is_file():
        raise ConfigError("配置文件不存在: %s" % config_path)
    with config_path.open("r", encoding="utf-8") as stream:
        raw = yaml.safe_load(stream) or {}
    return AutoPidConfig.from_mapping(raw)
