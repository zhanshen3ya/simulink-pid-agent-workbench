"""MATLAB subprocess runner for the stable P0 JSON bridge."""

import json
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict

import numpy as np

from .base import BaseRunner, SimulationResult


class MatlabRunner(BaseRunner):
    def __init__(self, project_root: str = None, executable: str = "matlab") -> None:
        self.project_root = Path(project_root or Path(__file__).resolve().parents[2])
        self.executable = shutil.which(executable) or executable

    def scan(self, config: Any) -> Dict[str, Any]:
        return self._invoke("scan_model_to_json", {
            "model_file": config.model.file,
        })

    def run_baseline(self, config: Any) -> SimulationResult:
        payload = self._invoke("run_baseline_to_json", {
            "model_file": config.model.file,
            "stop_time": config.model.stop_time,
            "signals": config.signals.__dict__,
        })
        if not bool(payload.get("success", True)):
            return SimulationResult(
                np.array([]), np.array([]), np.array([]), np.array([]),
                success=False,
                solver_error=payload.get("solver_error") or "MATLAB/Simulink simulation failed",
                metadata=payload.get("metadata") or {},
            )
        signals = payload.get("signals") or {}
        return SimulationResult(
            np.asarray(signals["time"], dtype=float),
            np.asarray(signals["reference"], dtype=float),
            np.asarray(signals["output"], dtype=float),
            np.asarray(signals["control"], dtype=float),
            {key: np.asarray(value, dtype=float)
             for key, value in (signals.get("extra_signals") or {}).items()},
            bool(payload.get("success", True)),
            payload.get("solver_error"),
            payload.get("metadata") or {},
        )

    def _invoke(self, bridge: str, request: Dict[str, Any]) -> Dict[str, Any]:
        with tempfile.TemporaryDirectory(prefix="autopid_p0_") as folder:
            request_path = Path(folder) / "request.json"
            output_path = Path(folder) / "result.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")
            root = _matlab_quote(str(self.project_root))
            command = (
                "root='%s'; addpath(root,fullfile(root,'matlab'),"
                "fullfile(root,'pid_tuning_core'),fullfile(root,'examples')); "
                "%s('%s','%s')"
                % (root, bridge, _matlab_quote(str(request_path)),
                   _matlab_quote(str(output_path)))
            )
            process = subprocess.run(
                [self.executable, "-batch", command],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                universal_newlines=True,
            )
            if process.returncode != 0 or not output_path.is_file():
                raise RuntimeError("MATLAB bridge failed: %s" % process.stdout[-4000:])
            return json.loads(output_path.read_text(encoding="utf-8-sig"))


def _matlab_quote(value: str) -> str:
    return value.replace("'", "''")
