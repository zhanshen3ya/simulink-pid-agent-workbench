"""Adapter-based detection for standard Simulink PID-family blocks."""

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Mapping

from .types import ControllerInfo


class ControllerAdapter(ABC):
    """Read-only P0 adapter contract for a controller implementation."""

    name = "base"

    @abstractmethod
    def matches(self, block_metadata: Mapping[str, Any]) -> bool:
        raise NotImplementedError

    @abstractmethod
    def read_parameters(self, block_metadata: Mapping[str, Any]) -> ControllerInfo:
        raise NotImplementedError

    def write_parameters(self, block_path: str, parameters: Mapping[str, Any]) -> None:
        """P0 never writes a controller; later adapters must target model copies only."""
        raise RuntimeError("P0 禁止自动写入 PID 参数: %s" % block_path)


class StandardPidAdapter(ControllerAdapter):
    """Recognize Simulink PID Controller and PID Controller 2DOF variants."""

    name = "standard_pid"

    def matches(self, block_metadata: Mapping[str, Any]) -> bool:
        block_type = str(block_metadata.get("block_type") or "").lower()
        descriptor = " ".join([
            block_type,
            str(block_metadata.get("mask_type") or "").lower(),
            str(block_metadata.get("reference_block") or "").lower(),
        ])
        parameters = block_metadata.get("parameters") or {}
        return ("pid" in descriptor or block_type in ("pidcontroller", "pidcontroller2dof")) and all(
            name in parameters for name in ("P", "I", "D")
        )

    def read_parameters(self, block_metadata: Mapping[str, Any]) -> ControllerInfo:
        parameters = dict(block_metadata.get("parameters") or {})
        link_status = str(block_metadata.get("link_status") or "none").lower()
        safe = bool(block_metadata.get("safe_to_modify", link_status in ("none", "inactive")))
        controller_mode = str(block_metadata.get("controller_mode") or _infer_mode(parameters))
        return ControllerInfo(
            block_id=str(block_metadata["id"]),
            path=str(block_metadata.get("path") or block_metadata["id"]),
            controller_type=str(block_metadata.get("controller_type") or "PID Controller"),
            mode=controller_mode,
            time_domain=str(block_metadata.get("time_domain") or "unknown"),
            sample_time=_optional_text(block_metadata.get("sample_time")),
            form=_optional_text(block_metadata.get("form")),
            parameters=parameters,
            output_limits=dict(block_metadata.get("output_limits") or {}),
            anti_windup=dict(block_metadata.get("anti_windup") or {}),
            input_ports=[str(item) for item in _list_values(block_metadata.get("input_ports"))],
            output_ports=[str(item) for item in _list_values(block_metadata.get("output_ports"))],
            parent_system=str(block_metadata.get("parent") or ""),
            library_link=link_status not in ("", "none", "inactive"),
            safe_to_modify=safe,
            adapter=self.name,
        )


def detect_controllers(export: Mapping[str, Any]) -> List[ControllerInfo]:
    """Return supported controllers while leaving custom PID blocks unresolved."""
    adapters = [StandardPidAdapter()]
    blocks = export.get("controllers") or export.get("blocks") or []
    if isinstance(blocks, Mapping):
        blocks = [blocks]
    result = []
    for block in blocks:
        for adapter in adapters:
            if adapter.matches(block):
                result.append(adapter.read_parameters(block))
                break
    return result


def _list_values(value: Any) -> List[Any]:
    if value is None or value == "":
        return []
    if isinstance(value, (list, tuple)):
        return list(value)
    return [value]


def _infer_mode(parameters: Mapping[str, Any]) -> str:
    def nonzero(name: str) -> bool:
        value = parameters.get(name, 0)
        if isinstance(value, Mapping):
            value = value.get("numeric", value.get("value", 0))
        try:
            return abs(float(value)) > 0
        except (TypeError, ValueError):
            return bool(str(value).strip())
    terms = "".join(name for name, key in (("P", "P"), ("I", "I"), ("D", "D")) if nonzero(key))
    return terms or "P"


def _optional_text(value: Any):
    text = str(value or "").strip()
    return text if text else None
