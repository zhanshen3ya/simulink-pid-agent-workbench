import tempfile
import unittest
from pathlib import Path

from autopid.config.schema import AutoPidConfig, ConfigError, load_config


class ConfigSchemaTests(unittest.TestCase):
    def test_unknown_fields_are_rejected(self):
        with self.assertRaises(ConfigError):
            AutoPidConfig.from_mapping({"model": {"file": "mock:buck", "typo": 1}})

    def test_original_model_overwrite_is_rejected(self):
        with self.assertRaises(ConfigError):
            AutoPidConfig.from_mapping({
                "deployment": {"overwrite_original": True},
            })

    def test_invalid_limit_order_is_rejected(self):
        with self.assertRaises(ConfigError):
            AutoPidConfig.from_mapping({
                "constraints": {"control_min": 1.0, "control_max": 0.0},
            })

    def test_legacy_gateway_fields_are_translated(self):
        config = AutoPidConfig.from_mapping({
            "modelPath": "demo.slx",
            "stopTime": 2,
            "pidBlocks": [{"path": "demo/PID"}],
            "referenceSignalName": "r",
            "outputSignalName": "y",
            "controlSignalName": "u",
            "targets": {"overshootPctMax": 0.2},
        })
        self.assertEqual(config.model.file, "demo.slx")
        self.assertEqual(config.controller.block_path, "demo/PID")
        self.assertEqual(config.signals.reference, "r")
        self.assertEqual(config.constraints.max_overshoot, 0.2)

    def test_yaml_uses_strict_schema(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.yaml"
            path.write_text("model:\n  file: mock:buck\n", encoding="utf-8")
            self.assertEqual(load_config(str(path)).model.file, "mock:buck")


if __name__ == "__main__":
    unittest.main()
