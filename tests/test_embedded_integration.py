import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "local_pid_gateway"))

import server_custom


class EmbeddedIntegrationTests(unittest.TestCase):
    def test_custom_payload_preserves_matlab_context_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            workdir = Path(directory)
            model = workdir / "controller.slx"
            project = workdir / "controller.prj"
            model.touch()
            project.touch()
            payload = {
                "modelPath": str(model),
                "workingDirectory": str(workdir),
                "projectRoot": str(workdir),
                "projectPath": str(project),
                "pidBlocks": [{
                    "name": "Outer PID",
                    "path": "controller/Outer PID",
                    "bounds": {
                        "Kp": [0, 10], "Ki": [0, 10],
                        "Kd": [0, 1], "N": [1, 1000],
                    },
                }],
            }

            normalized = server_custom.normalize_custom_payload(payload)

            self.assertEqual(normalized["modelPath"], str(model.resolve()))
            self.assertEqual(normalized["workingDirectory"], str(workdir.resolve()))
            self.assertEqual(normalized["projectRoot"], str(workdir.resolve()))
            self.assertEqual(normalized["projectPath"], str(project.resolve()))

    def test_job_list_ignores_incomplete_run_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            run_root = Path(directory)
            (run_root / "incomplete").mkdir()
            complete = run_root / "complete"
            complete.mkdir()
            (complete / "current_status.json").write_text(
                json.dumps({"status": "completed", "modelName": "demo"}),
                encoding="utf-8",
            )
            original_runs = server_custom.RUNS
            try:
                server_custom.RUNS = run_root
                jobs = server_custom.list_jobs()
            finally:
                server_custom.RUNS = original_runs

            self.assertEqual([job["jobId"] for job in jobs], ["complete"])

    def test_toolstrip_commands_and_uihtml_bridge_are_packaged(self):
        json_root = ROOT / "resources" / "json"
        tab = json.loads((json_root / "pidAgentTab.json").read_text(encoding="utf-8"))
        actions = json.loads((json_root / "pidAgentTab_actions.json").read_text(encoding="utf-8"))
        action_entries = [entry for entry in actions["entries"] if entry.get("type") == "Action"]
        action_ids = {entry["id"] for entry in action_entries}
        icon_entries = [entry for entry in actions["entries"] if entry.get("type") == "Icon"]
        icon_ids = {entry["id"] for entry in icon_entries}
        commands = {entry["command"] for entry in action_entries}

        def collect_action_refs(node):
            refs = {node["action"]} if isinstance(node, dict) and "action" in node else set()
            if isinstance(node, dict):
                for child in node.get("children", []):
                    refs.update(collect_action_refs(child))
            return refs

        action_refs = set()
        for entry in tab["entries"]:
            action_refs.update(collect_action_refs(entry))

        self.assertEqual(action_refs, action_ids)
        self.assertEqual({entry["icon"] for entry in action_entries}, icon_ids)
        for icon in icon_entries:
            self.assertTrue((ROOT / "resources" / "icons" / icon["icon16"]).is_file())
            self.assertTrue((ROOT / "resources" / "icons" / icon["icon24"]).is_file())
        self.assertIn("pid_agent_ui.launch('current')", commands)
        self.assertIn("pid_agent_ui.launch('selected')", commands)
        self.assertIn("pid_agent_ui.openManager()", commands)
        self.assertIn("pid_agent_ui.openHistory()", commands)

        html = (ROOT / "local_pid_gateway" / "web" / "index_custom.html").read_text(encoding="utf-8")
        self.assertIn("function setup(htmlComponent)", html)
        self.assertIn("sendEventToMATLAB('BridgeReady'", html)
        self.assertIn('src="./app_custom.js"', html)
        self.assertIn('href="./styles_custom.css"', html)
        self.assertIn('id="effectVerdict"', html)
        self.assertIn('id="effectComparisonRows"', html)

        app_js = (ROOT / "local_pid_gateway" / "web" / "app_custom.js").read_text(encoding="utf-8")
        self.assertIn("renderEffectEvaluation({})", app_js)
        self.assertIn("apiViaMatlab(path, options)", app_js)
        self.assertIn("sendMatlabEvent('GatewayRequest'", app_js)
        self.assertNotIn("el('currentMetrics')", app_js)


if __name__ == "__main__":
    unittest.main()
