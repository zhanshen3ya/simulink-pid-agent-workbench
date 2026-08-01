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


def dual_loop_payload(model, **overrides):
    payload = single_loop_payload(model)
    payload["pidBlocks"].append({
        "name": "Inner PID", "path": "controller/Inner PID",
        "bounds": {"Kp": [0, 10], "Ki": [0, 10], "Kd": [0, 1], "N": [1, 1000]},
    })
    payload["availableSignalNames"].append("iRef")
    payload["evaluationLoops"][0].update({
        "role": "outer", "controlSignalName": "iRef", "primary": True,
        "targets": {"overshootPctMax": 10, "settlingTimeMax": 2, "steadyStateErrorAbsMax": 0.1},
    })
    payload["evaluationLoops"].append({
        "name": "current", "role": "inner", "pidPath": "controller/Inner PID",
        "referenceSignalName": "iRef", "outputSignalName": "iL",
        "controlSignalName": "duty", "currentSignalName": "iL",
        "weight": 1, "primary": False,
        "controlLowerLimit": 0, "controlUpperLimit": 1,
        "targets": {"overshootPctMax": 15, "settlingTimeMax": 0.5, "steadyStateErrorAbsMax": 0.1},
    })
    payload["searchStrategy"] = "auto"
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
            payload["evaluationLoops"][0]["controlSignalName"] = "iRef"
            payload["evaluationLoops"].append({
                "name": "current", "role": "inner", "pidPath": "controller/Inner PID",
                "referenceSignalName": "iRef", "outputSignalName": "iL",
                "controlSignalName": "duty", "currentSignalName": "iL",
                "weight": 1, "primary": False,
                "controlLowerLimit": 0, "controlUpperLimit": 1,
                "targets": {"overshootPctMax": 20, "settlingTimeMax": 0.5},
            })
            payload["availableSignalNames"].append("iRef")
            payload["searchStrategy"] = "cascade"
            normalized = server_custom.normalize_custom_payload(payload)
            self.assertEqual({loop["role"] for loop in normalized["evaluationLoops"]}, {"inner", "outer"})
            payload["evaluationLoops"][1]["role"] = "outer"
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CASCADE_ROLE_REQUIRED")

    def test_auto_coupled_dual_loop_uses_joint_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = dual_loop_payload(model)
            for loop in payload["evaluationLoops"]:
                loop["role"] = "coupled"
            normalized = server_custom.normalize_custom_payload(payload)
            self.assertEqual({loop["role"] for loop in normalized["evaluationLoops"]}, {"coupled"})
            self.assertEqual(normalized["searchStrategy"], "auto")

    def test_cascade_requires_outer_to_drive_inner_reference(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = dual_loop_payload(model)
            payload["evaluationLoops"][0]["controlSignalName"] = "duty"
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CASCADE_SIGNAL_CHAIN_INVALID")

    def test_transformed_cascade_accepts_scanned_topology_relation(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = dual_loop_payload(model)
            payload["availableSignalNames"].append("iGridRef")
            payload["evaluationLoops"][1]["referenceSignalName"] = "iGridRef"
            payload["cascadeRelation"] = {
                "outerPidPath": "controller/Outer PID",
                "innerPidPath": "controller/Inner PID",
                "connectionKind": "transformed",
                "transformBlocks": ["controller/Current Reference Product"],
                "outerControlSignalName": "iRef",
                "innerReferenceSignalName": "iGridRef",
            }
            normalized = server_custom.normalize_custom_payload(payload)
            self.assertEqual(normalized["cascadeRelation"]["connectionKind"], "transformed")
            self.assertEqual(
                normalized["cascadeRelation"]["transformBlocks"],
                ["controller/Current Reference Product"],
            )

    def test_transformed_cascade_rejects_mismatched_signal_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = dual_loop_payload(model)
            payload["availableSignalNames"].append("iGridRef")
            payload["evaluationLoops"][1]["referenceSignalName"] = "iGridRef"
            payload["cascadeRelation"] = {
                "outerPidPath": "controller/Outer PID",
                "innerPidPath": "controller/Inner PID",
                "connectionKind": "transformed",
                "transformBlocks": ["controller/Current Reference Product"],
                "outerControlSignalName": "wrong",
                "innerReferenceSignalName": "iGridRef",
            }
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CASCADE_RELATION_SIGNAL_MISMATCH")
    def test_cascade_requires_outer_primary_loop(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = dual_loop_payload(model)
            payload["evaluationLoops"][0]["primary"] = False
            payload["evaluationLoops"][1]["primary"] = True
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CASCADE_PRIMARY_OUTER_REQUIRED")

    def test_cascade_requires_faster_inner_target(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "controller.slx"
            model.touch()
            payload = dual_loop_payload(model)
            payload["evaluationLoops"][1]["targets"]["settlingTimeMax"] = 2
            with self.assertRaises(server_custom.RequestValidationError) as raised:
                server_custom.normalize_custom_payload(payload)
            self.assertEqual(raised.exception.code, "CASCADE_TARGET_ORDER_INVALID")

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
    def test_apply_rejects_running_stage_result(self):
        with tempfile.TemporaryDirectory() as directory:
            run_root = Path(directory)
            job = run_root / "running-job"
            job.mkdir()
            (job / "current_status.json").write_text(
                json.dumps({"status": "running", "modelName": "demo"}),
                encoding="utf-8",
            )
            original_runs = server_custom.RUNS
            try:
                server_custom.RUNS = run_root
                with self.assertRaises(server_custom.RequestValidationError) as raised:
                    server_custom.apply_job_result("running-job")
            finally:
                server_custom.RUNS = original_runs
            self.assertEqual(raised.exception.code, "JOB_NOT_COMPLETED")

    def test_job_launch_status_becomes_running_before_matlab_output(self):
        with tempfile.TemporaryDirectory() as directory:
            run_root = Path(directory)
            job = run_root / "job-starting"
            job.mkdir()
            (job / "current_status.json").write_text(
                json.dumps({"jobId": job.name, "status": "queued", "modelName": "demo"}),
                encoding="utf-8",
            )
            original_runs = server_custom.RUNS
            try:
                server_custom.RUNS = run_root
                process = type("Process", (), {"pid": 12345})()
                server_custom.mark_job_running(job.name, process)
                status = json.loads(
                    (job / "current_status.json").read_text(encoding="utf-8")
                )
            finally:
                server_custom.RUNS = original_runs

            self.assertEqual(status["status"], "running")
            self.assertEqual(status["currentStage"], "initializing")
            self.assertEqual(status["processId"], 12345)
            self.assertTrue(status["startedAt"])

    def test_job_status_includes_bound_model_path(self):
        with tempfile.TemporaryDirectory() as directory:
            run_root = Path(directory)
            job = run_root / "job-1"
            job.mkdir()
            (job / "current_status.json").write_text(
                json.dumps({"status": "completed", "modelName": "demo"}),
                encoding="utf-8",
            )
            (job / "request_config.json").write_text(
                json.dumps({"modelPath": r"D:\models\demo.slx"}),
                encoding="utf-8",
            )
            original_runs = server_custom.RUNS
            try:
                server_custom.RUNS = run_root
                status = server_custom.read_status("job-1")
            finally:
                server_custom.RUNS = original_runs
            self.assertEqual(status["modelPath"], r"D:\models\demo.slx")

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
            (complete / "request_config.json").write_text(
                json.dumps({"modelPath": r"D:\models\demo.slx"}),
                encoding="utf-8",
            )
            original_runs = server_custom.RUNS
            try:
                server_custom.RUNS = run_root
                jobs = server_custom.list_jobs()
            finally:
                server_custom.RUNS = original_runs

            self.assertEqual([job["jobId"] for job in jobs], ["complete"])
            self.assertEqual(jobs[0]["modelPath"], r"D:\models\demo.slx")

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
        self.assertIn("clear('pid_agent_ui.launch'); pid_agent_ui.launch('current')", commands)
        self.assertIn("clear('pid_agent_ui.launch'); pid_agent_ui.launch('selected')", commands)
        self.assertIn("pid_agent_ui.openManager()", commands)
        self.assertIn("pid_agent_ui.openHistory()", commands)

        html = (ROOT / "local_pid_gateway" / "web" / "index_custom.html").read_text(encoding="utf-8")
        legacy_html = (ROOT / "local_pid_gateway" / "web" / "index.html").read_text(encoding="utf-8")
        legacy_js = (ROOT / "local_pid_gateway" / "web" / "app.js").read_text(encoding="utf-8")
        self.assertIn("function setup(htmlComponent)", html)
        self.assertIn("sendEventToMATLAB('BridgeReady'", html)
        self.assertIn('src="./app_custom.js"', html)
        self.assertIn('src="./app_custom_v2.js"', html)
        self.assertIn('href="./styles_custom.css"', html)
        self.assertIn('id="effectVerdict"', html)
        self.assertIn('id="effectComparisonRows"', html)
        self.assertIn('id="evaluationPidSelect"', html)
        self.assertIn('id="signalMappingConfirmedInput"', html)
        self.assertIn('id="bestLoopMetricRows"', html)
        self.assertIn('id="stageSummaryRows"', html)
        self.assertIn('id="jobContextWarning"', html)
        self.assertIn('<th>诊断</th>', html)
        self.assertIn('<th>所属系统</th>', html)
        self.assertIn('我已核对双环关系', html)

        styles = (ROOT / "local_pid_gateway" / "web" / "styles_custom.css").read_text(encoding="utf-8")
        app_js = (ROOT / "local_pid_gateway" / "web" / "app_custom.js").read_text(encoding="utf-8")
        app_v2_js = (ROOT / "local_pid_gateway" / "web" / "app_custom_v2.js").read_text(encoding="utf-8")
        self.assertIn("button.primary-button:disabled", styles)
        self.assertIn(".loop-relationship.warning", styles)
        self.assertIn("body.embedded-mode .title-strip", styles)
        self.assertIn("renderEffectEvaluation({})", app_js)
        self.assertIn("enforceModelMatch: true", app_js)
        self.assertIn("apiViaMatlab(path, options)", app_js)
        self.assertIn("sendMatlabEvent('GatewayRequest'", app_js)
        self.assertIn("function validationError", app_js)
        self.assertIn("function applySignalSuggestion", app_js)
        self.assertIn("availableSignalNames", app_js)
        self.assertIn("apiErrorText(error, '启动')", app_js)
        self.assertIn("function updateStartButton", app_js)
        self.assertIn("const optimisticStatus", app_js)
        self.assertIn("function liveElapsedSeconds", app_v2_js)
        self.assertIn("MODEL_DRAFT_STORAGE_PREFIX", app_v2_js)
        self.assertIn("function saveModelDraftNow", app_v2_js)
        self.assertIn("function applyModelDraft", app_v2_js)
        self.assertIn("window.addEventListener('beforeunload', saveModelDraftNow)", app_v2_js)
        draft_section = app_v2_js.split("function captureModelDraft()", 1)[1].split(
            "function saveModelDraftNow()", 1
        )[0]
        self.assertNotIn("apiKey", draft_section)
        self.assertNotIn("el('currentMetrics')", app_js)
        self.assertIn("Multi-PID models require an explicit selection", app_v2_js)
        self.assertIn("return 'coupled';", app_v2_js)
        self.assertNotIn("position === 0 ? 'outer' : 'inner'", app_v2_js)
        self.assertNotIn("startDemoButton", legacy_html)
        self.assertNotIn("async function startDemo()", legacy_js)
        self.assertNotIn("startSingleDemoButton", html)
        self.assertNotIn("startDemoButton", html)
        self.assertNotIn("startBuckDemoButton", html)
        self.assertNotIn("async function startSingleDemo()", app_js)
        self.assertNotIn("async function startDemo()", app_js)
        self.assertNotIn("async function startBuckDemo()", app_js)
        self.assertNotIn("async function startBuckDemo()", app_v2_js)
        self.assertIn("status === 'completed' && Boolean(bestPassing)", app_v2_js)
        self.assertIn("function renderStageSummaries", app_v2_js)
        self.assertIn("function loopDiagnostic", app_v2_js)
        self.assertIn("function normalizedModelPath", app_v2_js)
        self.assertIn("function loopRelationshipMarkup", app_v2_js)
        self.assertIn("function pidSystem", app_v2_js)
        self.assertIn("function signalOptionsForBlock", app_v2_js)
        self.assertIn("scoped.length >= 3", app_v2_js)
        self.assertIn("function jobMatchesPreferredModel", app_v2_js)
        self.assertIn("state.enforceModelMatch = true", app_v2_js)
        self.assertIn("state.activeJobMatchesModel", app_v2_js)
        self.assertIn("当前显示的是其他模型的历史任务", app_v2_js)
        self.assertIn("document.body.classList.add('embedded-mode')", app_v2_js)
        self.assertIn("function cascadeRelationForLoops", app_v2_js)
        self.assertIn("function cascadeRelationMatchesSignals", app_v2_js)
        self.assertIn("const directChain = outer.controlSignalName === inner.referenceSignalName", app_v2_js)
        self.assertIn("cascadeRelation,", app_v2_js)
        self.assertIn("缺少或错误：", app_v2_js)
        self.assertIn("inner.targets.settlingTimeMax < outer.targets.settlingTimeMax", app_v2_js)
        self.assertIn("MATLAB 正在读取模型，已等待", app_v2_js)
        self.assertIn("number.toExponential(2)", app_v2_js)
        self.assertNotIn("/api/pid/jobs/demo/buck", app_v2_js)

        launch_helper = (ROOT / "+pid_agent_ui" / "launch.m").read_text(encoding="utf-8")
        matlab_app = (ROOT / "+pid_agent_ui" / "PidAgentWebApp.m").read_text(encoding="utf-8")
        http_helper = (ROOT / "+pid_agent_ui" / "sendGatewayHttpRequest.m").read_text(encoding="utf-8")
        request_builder = (ROOT / "+pid_agent_ui" / "buildGatewayRequest.m").read_text(encoding="utf-8")
        self.assertIn("clear(\"pid_agent_ui.sendGatewayHttpRequest\"", launch_helper)
        self.assertNotIn("webwrite", matlab_app)
        self.assertIn("pid_agent_ui.sendGatewayHttpRequest", matlab_app)
        self.assertIn("performModelAction", matlab_app)
        self.assertIn("applyPidCandidateToModel", matlab_app)
        self.assertIn("modelFingerprint", matlab_app)
        self.assertIn("PIDAgent:JobNotCompleted", matlab_app)
        preflight = (ROOT / "run_pid_tuning_from_json.m").read_text(encoding="utf-8")
        self.assertIn("localValidateModelMapping", preflight)
        self.assertIn("PIDAgent:SignalNotLogged", preflight)
        self.assertIn("pid_agent_ui.buildGatewayRequest", http_helper)
        self.assertIn("RequestMethod.POST", request_builder)
        self.assertIn("RequestMethod.GET", request_builder)
        self.assertIn("MessageBody(body)", request_builder)
        self.assertNotIn("jsonencode(body)", request_builder)
        self.assertNotIn('RequestMessage("post"', request_builder)
        self.assertNotIn('RequestMessage("get"', request_builder)

        server_ai_text = (ROOT / "local_pid_gateway" / "server_ai.py").read_text(encoding="utf-8")
        server_custom_text = (ROOT / "local_pid_gateway" / "server_custom.py").read_text(encoding="utf-8")
        self.assertNotIn("addpath(genpath(pwd))", server_ai_text)
        self.assertNotIn("addpath(genpath(pwd))", server_custom_text)
        self.assertIn('script = run_dir / "run_job.m"', server_ai_text)
        self.assertIn("base.mark_job_running(job_id, process)", server_ai_text)
        self.assertIn("def mark_job_running(job_id, process):", server_custom_text)


if __name__ == "__main__":
    unittest.main()
