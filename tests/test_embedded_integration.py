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


def single_loop_payload(model, **overrides):
    payload = {
        "modelPath": str(model),
        "pidBlocks": [{
            "name": "Outer PID", "path": "controller/Outer PID",
            "bounds": {"Kp": [0, 10], "Ki": [0, 10], "Kd": [0, 1], "N": [1, 1000]},
        }],
        "availableSignalNames": ["Vref", "Vout", "duty", "iL"],
        "signalMappingConfirmed": True,
        "searchStrategy": "joint",
        "maxIterations": 3,
        "numCandidates": 2,
        "evaluationLoops": [{
            "name": "voltage", "role": "single", "pidPath": "controller/Outer PID",
            "referenceSignalName": "Vref", "outputSignalName": "Vout",
            "controlSignalName": "duty", "currentSignalName": "iL",
            "weight": 1, "primary": True,
            "controlLowerLimit": 0, "controlUpperLimit": 1,
            "targets": {"overshootPctMax": 10, "settlingTimeMax": 2, "steadyStateErrorAbsMax": 0.1},
        }],
    }
    payload.update(overrides)
    return payload


class EmbeddedIntegrationTests(unittest.TestCase):
    def test_custom_payload_preserves_matlab_context_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            workdir = Path(directory)
            model = workdir / "controller.slx"
            project = workdir / "controller.prj"
            model.touch()
            project.touch()
            payload = single_loop_payload(
                model, workingDirectory=str(workdir), projectRoot=str(workdir),
                projectPath=str(project),
            )
            normalized = server_custom.normalize_custom_payload(payload)
            self.assertEqual(normalized["modelPath"], str(model.resolve()))
            self.assertEqual(normalized["workingDirectory"], str(workdir.resolve()))
            self.assertEqual(normalized["projectRoot"], str(workdir.resolve()))
            self.assertEqual(normalized["projectPath"], str(project.resolve()))

    def test_model_fingerprint_is_bound_to_job_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.write_bytes(b"model-v1")
            first = server_custom.normalize_custom_payload(single_loop_payload(model))
            self.assertEqual(len(first["modelFingerprint"]), 64)
            model.write_bytes(b"model-v2")
            second = server_custom.normalize_custom_payload(single_loop_payload(model))
            self.assertNotEqual(first["modelFingerprint"], second["modelFingerprint"])

    def test_project_path_collection_is_optional_context(self):
        with tempfile.TemporaryDirectory() as directory:
            workdir = Path(directory)
            model = workdir / "controller.slx"
            model.touch()
            payload = single_loop_payload(model, projectPath=[str(workdir / "models"), str(workdir / "data")])
            normalized = server_custom.normalize_custom_payload(payload)
            self.assertEqual(normalized["projectPath"], "")

    def test_signal_mapping_requires_explicit_confirmation(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = single_loop_payload(model, signalMappingConfirmed=False)
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "SIGNAL_MAPPING_NOT_CONFIRMED")

    def test_manual_signal_mapping_rejects_unlogged_signal(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = single_loop_payload(model)
            payload["evaluationLoops"][0]["outputSignalName"] = "wrong_voltage"
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "SIGNAL_NOT_LOGGED")
            self.assertEqual(raised.exception.field, "evaluationLoops[0].outputSignalName")

    def test_manual_signal_mapping_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            normalized = server_custom.normalize_custom_payload(single_loop_payload(model))
            self.assertEqual(normalized["referenceSignalName"], "Vref")
            self.assertEqual(normalized["currentSignalName"], "iL")
            self.assertTrue(normalized["signalMappingConfirmed"])
            self.assertEqual(normalized["evaluationPidPath"], "controller/Outer PID")
            self.assertEqual(len(normalized["evaluationLoops"]), 1)

    def test_dual_loop_cascade_requires_one_inner_and_one_outer(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = single_loop_payload(model)
            payload["pidBlocks"].append({
                "name": "Inner PID", "path": "controller/Inner PID",
                "bounds": {"Kp": [0, 10], "Ki": [0, 10], "Kd": [0, 1], "N": [1, 1000]},
            })
            payload["evaluationLoops"][0]["role"] = "outer"
            payload["evaluationLoops"].append({
                "name": "current", "role": "inner", "pidPath": "controller/Inner PID",
                "referenceSignalName": "iRef", "outputSignalName": "iL",
                "controlSignalName": "duty", "currentSignalName": "iL",
                "weight": 1, "primary": False,
                "controlLowerLimit": 0, "controlUpperLimit": 1,
                "targets": {"overshootPctMax": 20},
            })
            payload["availableSignalNames"].append("iRef")
            payload["searchStrategy"] = "cascade"
            normalized = server_custom.normalize_custom_payload(payload)
            self.assertEqual({loop["role"] for loop in normalized["evaluationLoops"]}, {"inner", "outer"})
            payload["evaluationLoops"][1]["role"] = "outer"
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CASCADE_ROLE_REQUIRED")

    def test_loop_control_limits_must_be_ordered(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = single_loop_payload(model)
            payload["evaluationLoops"][0]["controlLowerLimit"] = 1
            payload["evaluationLoops"][0]["controlUpperLimit"] = 0
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CONTROL_LIMIT_INVALID")

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
        self.assertIn('src="./app_custom_v2.js"', html)
        self.assertIn('href="./styles_custom.css"', html)
        self.assertIn('id="effectVerdict"', html)
        self.assertIn('id="effectComparisonRows"', html)
        self.assertIn('id="evaluationPidSelect"', html)
        self.assertIn('id="signalMappingConfirmedInput"', html)

        app_js = (ROOT / "local_pid_gateway" / "web" / "app_custom.js").read_text(encoding="utf-8")
        app_v2_js = (ROOT / "local_pid_gateway" / "web" / "app_custom_v2.js").read_text(encoding="utf-8")
        self.assertIn("renderEffectEvaluation({})", app_js)
        self.assertIn("apiViaMatlab(path, options)", app_js)
        self.assertIn("sendMatlabEvent('GatewayRequest'", app_js)
        self.assertIn("function validationError", app_js)
        self.assertIn("function applySignalSuggestion", app_js)
        self.assertIn("availableSignalNames", app_js)
        self.assertIn("apiErrorText(error, '启动')", app_js)
        self.assertNotIn("el('currentMetrics')", app_js)
        self.assertIn("Multi-PID models require an explicit selection", app_v2_js)
        self.assertIn("async function startBuckDemo()", app_v2_js)
        self.assertNotIn("/api/pid/jobs/demo/buck", app_v2_js)

        matlab_app = (ROOT / "+pid_agent_ui" / "PidAgentWebApp.m").read_text(encoding="utf-8")
        http_helper = (ROOT / "+pid_agent_ui" / "sendGatewayHttpRequest.m").read_text(encoding="utf-8")
        self.assertNotIn("webwrite", matlab_app)
        self.assertIn("pid_agent_ui.sendGatewayHttpRequest", matlab_app)
        self.assertIn("performModelAction", matlab_app)
        self.assertIn("applyPidCandidateToModel", matlab_app)
        self.assertIn("modelFingerprint", matlab_app)
        preflight = (ROOT / "run_pid_tuning_from_json.m").read_text(encoding="utf-8")
        self.assertIn("localValidateModelMapping", preflight)
        self.assertIn("PIDAgent:SignalNotLogged", preflight)
        self.assertIn("matlab.net.http.RequestMessage", http_helper)

        server_ai_text = (ROOT / "local_pid_gateway" / "server_ai.py").read_text(encoding="utf-8")
        server_custom_text = (ROOT / "local_pid_gateway" / "server_custom.py").read_text(encoding="utf-8")
        self.assertNotIn("addpath(genpath(pwd))", server_ai_text)
        self.assertNotIn("addpath(genpath(pwd))", server_custom_text)
        self.assertIn('script = run_dir / "run_job.m"', server_ai_text)


if __name__ == "__main__":
    unittest.main()
