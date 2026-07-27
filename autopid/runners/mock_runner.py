"""Deterministic mock models used for P0 acceptance and CI."""

from typing import Any, Dict, List

import numpy as np

from .base import BaseRunner, SimulationResult


class _ExportBuilder:
    def __init__(self, model_name: str) -> None:
        self.data = {
            "schema_version": "autopid.matlab_scan.v1",
            "model_name": model_name,
            "model_path": "mock:%s" % model_name,
            "blocks": [],
            "ports": [],
            "signals": [],
            "controllers": [],
            "unresolved": [],
        }

    def block(self, block_id: str, name: str, block_type: str,
              parameters: Dict[str, Any] = None, controller: bool = False) -> str:
        item = {
            "id": block_id,
            "name": name,
            "path": "%s/%s" % (self.data["model_name"], name),
            "block_type": block_type,
            "parameters": parameters or {},
            "link_status": "none",
            "safe_to_modify": True,
        }
        self.data["blocks"].append(item)
        if controller:
            item["input_ports"] = ["%s:in:1" % block_id]
            item["output_ports"] = ["%s:out:1" % block_id]
            item["controller_type"] = "PID Controller"
            item["time_domain"] = "continuous"
            item["sample_time"] = "0"
            self.data["controllers"].append(dict(item))
        return block_id

    def port(self, block_id: str, direction: str, index: int) -> str:
        port_id = "%s:%s:%d" % (block_id, direction, index)
        self.data["ports"].append({
            "id": port_id, "block_id": block_id,
            "direction": direction, "index": index,
        })
        return port_id

    def standard_ports(self, block_id: str, inputs: int = 1, outputs: int = 1) -> None:
        for index in range(1, inputs + 1):
            self.port(block_id, "in", index)
        for index in range(1, outputs + 1):
            self.port(block_id, "out", index)

    def signal(self, signal_id: str, name: str, src: str,
               destinations: List[str], unit: str = "") -> None:
        self.data["signals"].append({
            "id": signal_id, "name": name, "src_port": src,
            "dst_ports": destinations, "unit": unit, "sample_time": "0",
        })


class MockRunner(BaseRunner):
    """Return reproducible scan exports and waveforms without MATLAB."""

    def scan(self, config: Any) -> Dict[str, Any]:
        scenario = _scenario(config)
        if scenario == "cascade":
            return _cascade_export()
        return _buck_export(include_decoy=scenario == "wrong_signal")

    def run_baseline(self, config: Any) -> SimulationResult:
        scenario = _scenario(config)
        scale = 100.0 if scenario == "scale100" else 10.0
        t = np.linspace(0.0, float(config.model.stop_time), 1001)
        r = np.full_like(t, scale)
        if scenario == "unstable":
            y = 0.05 * scale * np.exp(7.0 * t / max(t[-1], 1e-9))
            u = np.clip(y / scale, 0.0, 1.0)
        else:
            tau = 0.12 * max(t[-1], 1e-9)
            y = scale * (1.0 - np.exp(-t / tau))
            u = 0.35 + 0.20 * np.exp(-t / max(0.04 * t[-1], 1e-9))
            if scenario == "saturation":
                u[:] = 1.0
            if scenario == "ripple":
                y += 0.01 * scale * np.sin(2.0 * np.pi * 180.0 * t / max(t[-1], 1e-9))
        current = 2.0 + 0.2 * np.exp(-t / max(0.08 * t[-1], 1e-9))
        if scenario == "current_limit":
            current += 5.0 * np.exp(-((t - 0.08 * t[-1]) / max(0.02 * t[-1], 1e-9)) ** 2)
        return SimulationResult(
            t, r, y, u, {"current": current, "voltage": y},
            metadata={"runner": "mock", "scenario": scenario},
        )


def _scenario(config: Any) -> str:
    value = str(config.model.file)
    return value.split(":", 1)[1] if value.startswith("mock:") else value


def _buck_export(include_decoy: bool = False) -> Dict[str, Any]:
    b = _ExportBuilder("buck")
    b.block("ref", "Vref", "Constant")
    b.block("sum", "VoltageError", "Sum", {"Inputs": "+-"})
    b.block("pid", "VoltagePID", "PIDController", {"P": 1.2, "I": 30.0, "D": 0.0}, True)
    b.block("sat", "DutySaturation", "Saturation")
    b.block("plant", "BuckPlant", "TransferFcn")
    for block_id, inputs, outputs in (
        ("ref", 0, 1), ("sum", 2, 1), ("pid", 1, 1),
        ("sat", 1, 1), ("plant", 1, 1),
    ):
        b.standard_ports(block_id, inputs, outputs)
    b.signal("sig_r", "Vref", "ref:out:1", ["sum:in:1"], "V")
    b.signal("sig_y", "Vout", "plant:out:1", ["sum:in:2"], "V")
    b.signal("sig_e", "Verror", "sum:out:1", ["pid:in:1"], "V")
    b.signal("sig_u_raw", "duty_raw", "pid:out:1", ["sat:in:1"], "1")
    b.signal("sig_u", "duty", "sat:out:1", ["plant:in:1"], "1")
    if include_decoy:
        b.block("decoy", "VoutDisplay", "Constant")
        b.standard_ports("decoy", 0, 1)
        b.signal("sig_fake", "Vout", "decoy:out:1", [], "V")
    return b.data


def _cascade_export() -> Dict[str, Any]:
    b = _ExportBuilder("cascade")
    definitions = [
        ("ref", "Vref", "Constant", 0, 1),
        ("sum_o", "VoltageError", "Sum", 2, 1),
        ("pid_o", "OuterVoltagePID", "PIDController", 1, 1),
        ("lim_o", "CurrentReferenceLimit", "Saturation", 1, 1),
        ("sum_i", "CurrentError", "Sum", 2, 1),
        ("pid_i", "InnerCurrentPID", "PIDController", 1, 1),
        ("sat_i", "DutySaturation", "Saturation", 1, 1),
        ("plant_i", "CurrentPlant", "TransferFcn", 1, 1),
        ("plant_o", "VoltagePlant", "TransferFcn", 1, 1),
    ]
    for block_id, name, block_type, inputs, outputs in definitions:
        params = {"Inputs": "+-"} if block_type == "Sum" else (
            {"P": 1.0, "I": 10.0, "D": 0.0} if block_type == "PIDController" else {}
        )
        b.block(block_id, name, block_type, params, block_type == "PIDController")
        b.standard_ports(block_id, inputs, outputs)
    b.signal("sig_vref", "Vref", "ref:out:1", ["sum_o:in:1"], "V")
    b.signal("sig_vout", "Vout", "plant_o:out:1", ["sum_o:in:2"], "V")
    b.signal("sig_ev", "Verror", "sum_o:out:1", ["pid_o:in:1"], "V")
    b.signal("sig_iref_raw", "Iref_raw", "pid_o:out:1", ["lim_o:in:1"], "A")
    b.signal("sig_iref", "Iref", "lim_o:out:1", ["sum_i:in:1"], "A")
    b.signal("sig_iout", "Iout", "plant_i:out:1", ["sum_i:in:2", "plant_o:in:1"], "A")
    b.signal("sig_ei", "Ierror", "sum_i:out:1", ["pid_i:in:1"], "A")
    b.signal("sig_duty_raw", "duty_raw", "pid_i:out:1", ["sat_i:in:1"], "1")
    b.signal("sig_duty", "duty", "sat_i:out:1", ["plant_i:in:1"], "1")
    return b.data
