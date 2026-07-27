import json
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

from autopid.cli import build_parser, execute, main


CONFIG = Path(__file__).resolve().parents[1] / "configs" / "p0_buck_mock.yaml"


class CliTests(unittest.TestCase):
    def test_scan_command_returns_discovery(self):
        args = build_parser().parse_args([
            "scan", "--config", str(CONFIG), "--runner", "mock",
        ])
        result = execute(args)
        self.assertEqual(result["command"], "scan")
        self.assertEqual(result["discovery"]["loops"][0]["signals"]["measurement_signal"], "sig_y")

    def test_validate_command_writes_json(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "result.json"
            with redirect_stdout(StringIO()):
                exit_code = main([
                    "validate", "--config", str(CONFIG), "--runner", "mock",
                    "--output", str(output),
                ])
            self.assertEqual(exit_code, 0)
            result = json.loads(output.read_text(encoding="utf-8"))
            self.assertTrue(result["gate"]["feasible"])
            self.assertIsNotNone(result["gate"]["score"])


if __name__ == "__main__":
    unittest.main()
