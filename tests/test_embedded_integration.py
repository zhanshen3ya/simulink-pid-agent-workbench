import json
import sys
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "local_pid_gateway"))

import server_custom
import server_ai


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
                "referenceSignalName": "Vref",
                "outputSignalName": "Vout",
                "controlSignalName": "duty",
            }

            normalized = server_custom.normalize_custom_payload(payload)

            self.assertEqual(normalized["modelPath"], str(model.resolve()))
            self.assertEqual(normalized["workingDirectory"], str(workdir.resolve()))
            self.assertEqual(normalized["projectRoot"], str(workdir.resolve()))
            self.assertEqual(normalized["projectPath"], str(project.resolve()))

    def test_project_path_collection_is_optional_context(self):
        with tempfile.TemporaryDirectory() as directory:
            workdir = Path(directory)
            model = workdir / "controller.slx"
            model.touch()
            payload = {
                "modelPath": str(model),
                "projectPath": [str(workdir / "models"), str(workdir / "data")],
                "pidBlocks": [{
                    "path": "controller/PID",
                    "bounds": {"Kp": [0, 1], "Ki": [0, 1], "Kd": [0, 0], "N": [100, 100]},
                }],
                "referenceSignalName": "r",
                "outputSignalName": "y",
                "controlSignalName": "u",
            }

            normalized = server_custom.normalize_custom_payload(payload)

            self.assertEqual(normalized["projectPath"], "")

    def test_manual_signal_mapping_rejects_unlogged_signal(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = {
                "modelPath": str(model),
                "pidBlocks": [{
                    "path": "controller/PID",
                    "bounds": {
                        "Kp": [0, 1], "Ki": [0, 1],
                        "Kd": [0, 0], "N": [100, 100],
                    },
                }],
                "referenceSignalName": "Vref",
                "outputSignalName": "wrong_voltage",
                "controlSignalName": "duty",
                "availableSignalNames": ["Vref", "Vout", "duty"],
                "signalMappingConfirmed": True,
                "evaluationPidPath": "controller/PID",
            }

            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)

            self.assertEqual(raised.exception.code, "SIGNAL_NOT_LOGGED")
            self.assertEqual(raised.exception.field, "outputSignalName")

    def test_manual_signal_mapping_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = {
                "modelPath": str(model),
                "pidBlocks": [{
                    "path": "controller/PID",
                    "bounds": {
                        "Kp": [0, 1], "Ki": [0, 1],
                        "Kd": [0, 0], "N": [100, 100],
                    },
                }],
                "referenceSignalName": "Vref",
                "outputSignalName": "Vout",
                "controlSignalName": "duty",
                "currentSignalName": "iL",
                "availableSignalNames": ["Vref", "Vout", "duty", "iL"],
                "signalMappingConfirmed": True,
                "evaluationPidPath": "controller/PID",
            }

            normalized = server_custom.normalize_custom_payload(payload)

            self.assertEqual(normalized["referenceSignalName"], "Vref")
            self.assertEqual(normalized["currentSignalName"], "iL")
            self.assertTrue(normalized["signalMappingConfirmed"])
            self.assertEqual(normalized["evaluationPidPath"], "controller/PID")
    def test_custom_endpoint_returns_structured_redacted_error(self):
        with tempfile.TemporaryDirectory() as directory:
            original_log = server_custom.REQUEST_LOG
            server_custom.REQUEST_LOG = Path(directory) / "requests.jsonl"
            server = server_custom.LocalHTTPServer(("127.0.0.1", 0), server_ai.Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                body = json.dumps({
                    "modelPath": "",
                    "pidBlocks": [],
                    "ai": {"api": {"apiKey": "must-not-be-logged"}},
                }).encode("utf-8")
                request = Request(
                    f"http://127.0.0.1:{server.server_port}/api/pid/jobs/custom",
                    data=body,
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                with self.assertRaises(HTTPError) as raised:
                    urlopen(request, timeout=5)
                response = raised.exception
                payload = json.loads(response.read().decode("utf-8"))

                self.assertEqual(response.code, 400)
                self.assertEqual(payload["code"], "MODEL_REQUIRED")
                self.assertEqual(payload["field"], "modelPath")
                self.assertEqual(response.headers["X-Request-ID"], payload["requestId"])
                log_text = server_custom.REQUEST_LOG.read_text(encoding="utf-8")
                self.assertNotIn("must-not-be-logged", log_text)
                self.assertIn('"apiKey": "***"', log_text)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)
                server_custom.REQUEST_LOG = original_log
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
        self.assertIn('id="evaluationPidSelect"', html)
        self.assertIn('id="signalMappingConfirmedInput"', html)

        app_js = (ROOT / "local_pid_gateway" / "web" / "app_custom.js").read_text(encoding="utf-8")
        self.assertIn("renderEffectEvaluation({})", app_js)
        self.assertIn("apiViaMatlab(path, options)", app_js)
        self.assertIn("sendMatlabEvent('GatewayRequest'", app_js)
        self.assertIn("function validationError", app_js)
        self.assertIn("function applySignalSuggestion", app_js)
        self.assertIn("availableSignalNames", app_js)
        self.assertIn("apiErrorText(error, '启动')", app_js)
        self.assertNotIn("el('currentMetrics')", app_js)

        matlab_app = (ROOT / "+pid_agent_ui" / "PidAgentWebApp.m").read_text(encoding="utf-8")
        http_helper = (ROOT / "+pid_agent_ui" / "sendGatewayHttpRequest.m").read_text(encoding="utf-8")
        self.assertNotIn("webwrite", matlab_app)
        self.assertIn("pid_agent_ui.sendGatewayHttpRequest", matlab_app)
        self.assertIn("matlab.net.http.RequestMessage", http_helper)

        server_ai_text = (ROOT / "local_pid_gateway" / "server_ai.py").read_text(encoding="utf-8")
        server_custom_text = (ROOT / "local_pid_gateway" / "server_custom.py").read_text(encoding="utf-8")
        self.assertNotIn("addpath(genpath(pwd))", server_ai_text)
        self.assertNotIn("addpath(genpath(pwd))", server_custom_text)
        self.assertIn('script = run_dir / "run_job.m"', server_ai_text)


if __name__ == "__main__":
    unittest.main()
