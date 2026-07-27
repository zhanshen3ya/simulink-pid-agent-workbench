"""Runner contracts shared by deterministic mock and MATLAB backends."""

from abc import ABC, abstractmethod
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, Mapping, Optional

import numpy as np


@dataclass
class SimulationResult:
    time: np.ndarray
    reference: np.ndarray
    output: np.ndarray
    control: np.ndarray
    extra_signals: Dict[str, np.ndarray] = field(default_factory=dict)
    success: bool = True
    solver_error: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        result = asdict(self)
        for key in ("time", "reference", "output", "control"):
            result[key] = np.asarray(result[key]).tolist()
        result["extra_signals"] = {
            name: np.asarray(value).tolist()
            for name, value in self.extra_signals.items()
        }
        return result


class BaseRunner(ABC):
    """Read-only model scan and baseline simulation interface."""

    @abstractmethod
    def scan(self, config: Any) -> Mapping[str, Any]:
        raise NotImplementedError

    @abstractmethod
    def run_baseline(self, config: Any) -> SimulationResult:
        raise NotImplementedError
