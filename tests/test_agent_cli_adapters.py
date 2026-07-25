import json
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "local_pid_gateway"))

import agent_cli_pid_provider as provider
import agent_cli_support as support


REQUEST = {
    "requestedCandidates": 1,
    "pidBlocks": [{"name": "VoltageLoop"}],
}
PAYLOAD = {
    "candidates": [
        {
            "pids": [
                {"name": "VoltageLoop", "Kp": 1.2, "Ki": 3.4, "Kd": 0.0, "N": 100.0}
            ]
        }
    ]
}


class ProviderAdapterTests(unittest.TestCase):
    def test_qwen_uses_headless_plan_mode(self):
        output = json.dumps([{"type": "result", "result": json.dumps(PAYLOAD)}])
        with mock.patch.object(provider, "run_process", return_value=output) as run:
            result = provider.run_qwen(["qwen"], "prompt", ROOT, 90, "qwen3-coder")

        args = run.call_args[0][0]
        self.assertEqual(result, PAYLOAD)
        self.assertIn("--prompt", args)
        self.assertEqual(args[args.index("--output-format") + 1], "json")
        self.assertEqual(args[args.index("--approval-mode") + 1], "plan")
        self.assertEqual(args[args.index("--model") + 1], "qwen3-coder")

    def test_kimi_uses_quiet_plan_mode(self):
        output = "```json\n" + json.dumps(PAYLOAD) + "\n```"
        with mock.patch.object(provider, "run_process", return_value=output) as run:
            result = provider.run_kimi(["kimi"], "prompt", ROOT, 90)

        args = run.call_args[0][0]
        self.assertEqual(result, PAYLOAD)
        self.assertIn("--quiet", args)
        self.assertIn("--plan", args)
        self.assertIn("-p", args)

    def test_codebuddy_uses_schema_and_disables_mutating_tools(self):
        output = json.dumps({"structured_output": PAYLOAD})
        with mock.patch.object(provider, "run_process", return_value=output) as run:
            result = provider.run_codebuddy(["codebuddy"], "prompt", ROOT, 90, "")

        args = run.call_args[0][0]
        disabled = args[args.index("--disallowedTools") + 1]
        self.assertEqual(result, PAYLOAD)
        self.assertIn("--json-schema", args)
        self.assertEqual(args[args.index("--permission-mode") + 1], "plan")
        for tool_name in ("Bash", "PowerShell", "Write", "Edit", "WebFetch", "WebSearch"):
            self.assertIn(tool_name, disabled)

    def test_prompt_embeds_request_and_forbids_file_changes(self):
        prompt = provider.build_prompt(Path("request.json"), REQUEST)
        self.assertIn('"requestedCandidates":1', prompt)
        self.assertIn("Do not read, edit, create, or delete files", prompt)


class AgentSupportTests(unittest.TestCase):
    def test_discovery_contains_all_supported_agents(self):
        with mock.patch.object(support, "_find_executable", return_value=None):
            agents = support.discover_agents()
        self.assertEqual([agent["id"] for agent in agents], list(support.AGENT_ORDER))
        self.assertTrue(all(agent["readOnly"] for agent in agents))

    def test_new_agent_configs_are_normalized(self):
        resolved = (Path(sys.executable).resolve(), [], {})
        for agent_type in ("qwen", "kimi", "codebuddy"):
            with self.subTest(agent=agent_type), mock.patch.object(
                support, "_resolve_command", return_value=resolved
            ):
                config, environment = support.normalize_agent_config(
                    {
                        "agent": {"type": agent_type, "timeoutSeconds": 60},
                        "candidatesPerIteration": 2,
                    },
                    4,
                )
            self.assertEqual(config["sourceLabel"], f"agent:{agent_type}")
            self.assertEqual(environment["PID_AGENT_TYPE"], agent_type)


if __name__ == "__main__":
    unittest.main()
