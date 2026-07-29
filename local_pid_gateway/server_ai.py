import json
import os
import subprocess
import threading
import time
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen

import server_custom as base
import agent_cli_support


AI_PRESETS = {
    "remote": [
        {"label": "OpenAI GPT-4o",        "baseUrl": "https://api.openai.com/v1",        "model": "gpt-4o"},
        {"label": "OpenAI GPT-4o-mini",   "baseUrl": "https://api.openai.com/v1",        "model": "gpt-4o-mini"},
        {"label": "OpenAI GPT-4-turbo",   "baseUrl": "https://api.openai.com/v1",        "model": "gpt-4-turbo"},
        {"label": "OpenAI GPT-3.5-turbo", "baseUrl": "https://api.openai.com/v1",        "model": "gpt-3.5-turbo"},
        {"label": "DeepSeek V3",          "baseUrl": "https://api.deepseek.com/v1",       "model": "deepseek-chat"},
        {"label": "DeepSeek R1",          "baseUrl": "https://api.deepseek.com/v1",       "model": "deepseek-reasoner"},
        {"label": "通义千问 (Qwen)",       "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1", "model": "qwen-plus"},
        {"label": "智谱 GLM-4",           "baseUrl": "https://open.bigmodel.cn/api/paas/v4", "model": "glm-4"},
        {"label": "Moonshot (Kimi)",      "baseUrl": "https://api.moonshot.cn/v1",        "model": "moonshot-v1-8k"},
        {"label": "自定义",               "baseUrl": "", "model": ""},
    ],
    "local": [
        {"engine": "ollama",  "label": "Ollama",              "baseUrl": "http://localhost:11434/v1"},
        {"engine": "lmstudio", "label": "LM Studio",           "baseUrl": "http://localhost:1234/v1"},
        {"engine": "vllm",    "label": "vLLM / LocalAI",       "baseUrl": "http://localhost:8000/v1"},
        {"engine": "python",  "label": "Python Provider 脚本", "baseUrl": ""},
        {"engine": "custom",  "label": "自定义本地端点",       "baseUrl": ""},
    ],
}


def _is_localhost_url(url_text):
    try:
        parsed = urlparse(str(url_text or ""))
        return parsed.hostname in ("127.0.0.1", "localhost", "::1")
    except Exception:
        return False


def normalize_ai(payload, num_candidates):
    raw = payload.get("ai") or {}
    mode = str(raw.get("mode") or "none").lower()
    if mode not in ("none", "api", "local", "agent"):
        raise base.RequestValidationError(
            "AI 模式必须是 none、api、local 或 agent。", "AI_MODE_INVALID", "ai.mode"
        )

    if mode == "agent":
        try:
            config, environment = agent_cli_support.normalize_agent_config(raw, num_candidates)
        except (TypeError, ValueError) as error:
            raise base.RequestValidationError(
                str(error), "AGENT_CONFIG_INVALID", "ai.agent"
            ) from error
        return config, "", environment

    try:
        candidate_count = int(raw.get("candidatesPerIteration") or min(4, num_candidates))
    except (TypeError, ValueError):
        raise base.RequestValidationError(
            "AI 每轮候选数必须是整数。", "AI_CANDIDATES_INVALID", "ai.candidatesPerIteration"
        )
    if not 0 <= candidate_count <= num_candidates:
        raise base.RequestValidationError(
            "AI 每轮候选数必须在 0 和每轮总候选数之间。",
            "AI_CANDIDATES_INVALID", "ai.candidatesPerIteration"
        )

    try:
        max_history = int(raw.get("maxHistoryRecords") or 12)
    except (TypeError, ValueError):
        raise base.RequestValidationError(
            "AI 历史记录数必须是整数。", "AI_HISTORY_INVALID", "ai.maxHistoryRecords"
        )
    if max_history < 1:
        raise base.RequestValidationError(
            "AI 历史记录数必须大于 0。", "AI_HISTORY_INVALID", "ai.maxHistoryRecords"
        )

    result = {
        "mode": mode,
        "candidatesPerIteration": candidate_count,
        "maxHistoryRecords": max_history,
        "failOnError": bool(raw.get("failOnError", False)),
    }
    api_key = ""

    if mode == "api":
        api = raw.get("api") or {}
        base_url = str(api.get("baseUrl") or "").strip()
        model = str(api.get("model") or "").strip()
        api_key = str(api.get("apiKey") or "").strip()
        if not base_url:
            raise base.RequestValidationError(
                "API AI 需要 Base URL。", "AI_API_URL_REQUIRED", "ai.api.baseUrl"
            )
        if not model:
            raise base.RequestValidationError(
                "API AI 需要模型名。", "AI_API_MODEL_REQUIRED", "ai.api.model"
            )
        if not api_key and not _is_localhost_url(base_url):
            raise base.RequestValidationError(
                "远程 API 需要 API Key，本地端点可以留空。",
                "AI_API_KEY_REQUIRED", "ai.api.apiKey"
            )
        try:
            temperature = float(api.get("temperature", 0.25))
            max_tokens = int(api.get("maxTokens", 2000))
            timeout = float(api.get("timeoutSeconds", 120))
        except (TypeError, ValueError):
            raise base.RequestValidationError(
                "API 温度、Max Tokens 和超时必须是数字。", "AI_API_CONFIG_INVALID", "ai.api"
            )
        if not 0 <= temperature <= 2:
            raise base.RequestValidationError(
                "API Temperature 必须在 0 到 2 之间。", "AI_API_CONFIG_INVALID", "ai.api.temperature"
            )
        if max_tokens < 1:
            raise base.RequestValidationError(
                "API Max Tokens 必须大于 0。", "AI_API_CONFIG_INVALID", "ai.api.maxTokens"
            )
        if not 5 <= timeout <= 1800:
            raise base.RequestValidationError(
                "API 超时必须在 5 到 1800 秒之间。", "AI_API_CONFIG_INVALID", "ai.api.timeoutSeconds"
            )
        result["api"] = {
            "baseUrl": base_url,
            "model": model,
            "temperature": temperature,
            "maxTokens": max_tokens,
            "timeoutSeconds": timeout,
        }

    if mode == "local":
        local = raw.get("local") or {}
        script_text = str(local.get("scriptPath") or "").strip().strip('"')
        if not script_text:
            raise base.RequestValidationError(
                "本地 Code 模式需要 Python provider 脚本路径。",
                "AI_LOCAL_SCRIPT_REQUIRED", "ai.local.scriptPath"
            )
        script_path = Path(os.path.expandvars(os.path.expanduser(script_text)))
        if not script_path.is_file():
            raise base.RequestValidationError(
                f"本地 AI provider 不存在: {script_path}",
                "AI_LOCAL_SCRIPT_NOT_FOUND", "ai.local.scriptPath"
            )
        result["local"] = {
            "pythonExe": str(local.get("pythonExe") or "python"),
            "scriptPath": str(script_path.resolve()),
            "timeoutSeconds": float(local.get("timeoutSeconds", 120)),
        }

    return result, api_key, {}

def launch_job(job_id, script, extra_env=None):
    health = base.probe_matlab()
    if not health["ready"]:
        raise RuntimeError("MATLAB 当前不可启动：" + health["error"])
    environment = os.environ.copy()
    environment.update(extra_env or {})
    process = subprocess.Popen(
        [str(base.MATLAB), "-batch", f"run('{base.matlab_quote(script)}')"],
        cwd=str(base.ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        env=environment,
    )
    base.JOBS[job_id] = {"process": process, "script": str(script)}

    def pump():
        log_path = base.RUNS / job_id / "matlab_stdout.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8", errors="ignore") as stream:
            for line in process.stdout or []:
                stream.write(line)
                stream.flush()
        return_code = process.wait()
        try:
            script.unlink()
        except OSError:
            pass
        if return_code != 0:
            current = base.read_status(job_id) or {}
            current.update({
                "jobId": job_id,
                "status": "failed",
                "error": f"MATLAB 任务退出，代码 {return_code}。请查看 matlab_stdout.log。",
                "updatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
            })
            base.write_status(job_id, current)
        else:
            base.trigger_code_backup(job_id)

    threading.Thread(target=pump, daemon=True).start()


def start_custom_job(payload):
    config = base.normalize_custom_payload(payload)
    ai_config, api_key, agent_environment = normalize_ai(payload, config["numCandidates"])
    config["ai"] = ai_config
    job_id = base.new_id("job")
    config["runId"] = job_id

    run_dir = base.RUNS / job_id
    run_dir.mkdir(parents=True, exist_ok=True)
    config_file = run_dir / "request_config.json"
    config_file.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")

    script = run_dir / "run_job.m"
    script.write_text(
        "root='{root}';\ncd(root);\naddpath(root, fullfile(root,'pid_tuning_core'), fullfile(root,'pid_project_manager'), fullfile(root,'examples'));\nrun_pid_tuning_from_json('{config}');\n".format(
            root=base.matlab_quote(base.ROOT.as_posix()),
            config=base.matlab_quote(config_file.as_posix()),
        ),
        encoding="utf-8",
    )
    model_path = Path(config["modelPath"])
    model_name = model_path.stem if model_path.suffix.lower() in (".slx", ".mdl") else config["modelPath"]
    base.write_status(job_id, {
        "jobId": job_id,
        "status": "queued",
        "modelName": model_name,
        "aiEnabled": ai_config["mode"] != "none",
        "aiMode": ai_config["mode"],
        "currentIteration": 0,
        "maxIterations": config["maxIterations"],
        "testedCount": 0,
        "passedCount": 0,
        "elapsedSeconds": 0,
        "updatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
    })
    environment = dict(agent_environment)
    if api_key:
        environment["PID_AI_API_KEY"] = api_key
    try:
        launch_job(job_id, script, environment)
    except Exception as error:
        base.write_status(job_id, {
            "jobId": job_id,
            "status": "failed",
            "modelName": model_name,
            "error": str(error),
            "updatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
        })
        try:
            script.unlink()
        except OSError:
            pass
        raise
    return job_id


def start_single_pid_demo():
    model_path = base.ROOT / "pid_ai_second_order_demo.slx"
    if not model_path.is_file():
        raise RuntimeError(f"单 PID 示例模型不存在: {model_path}")
    return start_custom_job({
        "modelPath": str(model_path),
        "pidBlocks": [{
            "name": "single", "path": "pid_ai_second_order_demo/PID Controller",
            "bounds": {"Kp": [0, 40], "Ki": [0, 30], "Kd": [0, 8], "N": [10, 500]},
        }],
        "stopTime": "8", "maxIterations": 8, "numCandidates": 12,
        "stopOnFirstPass": False, "searchStrategy": "joint",
        "availableSignalNames": ["r", "y", "u"], "signalMappingConfirmed": True,
        "evaluationLoops": [{
            "name": "output", "role": "single", "pidPath": "pid_ai_second_order_demo/PID Controller",
            "referenceSignalName": "r", "outputSignalName": "y", "controlSignalName": "u",
            "currentSignalName": "", "weight": 1, "primary": True,
            "controlLowerLimit": -100, "controlUpperLimit": 100,
            "targets": {"overshootPctMax": 10, "settlingTimeMax": 5, "steadyStateErrorAbsMax": 0.03, "controlSaturationFractionMax": 0.02},
        }],
        "targets": {"overshootPctMax": 10, "settlingTimeMax": 5, "steadyStateErrorAbsMax": 0.03},
        "ai": {"mode": "none"},
    })


def start_buck_dual_loop_demo():
    model_path = base.ROOT / "pid_ai_buck_dual_loop_demo.slx"
    if not model_path.is_file():
        raise RuntimeError(f"Buck 双环示例模型不存在: {model_path}")
    return start_custom_job({
        "modelPath": str(model_path),
        "pidBlocks": [
            {"name": "voltage", "path": "pid_ai_buck_dual_loop_demo/Outer_Voltage_PI", "bounds": {"Kp": [0.01, 0.15], "Ki": [4, 24], "Kd": [0, 0], "N": [100, 100]}},
            {"name": "current", "path": "pid_ai_buck_dual_loop_demo/Inner_Current_PI", "bounds": {"Kp": [0.015, 0.08], "Ki": [2, 20], "Kd": [0, 0], "N": [100, 100]}},
        ],
        "stopTime": "0.3", "maxIterations": 9, "numCandidates": 10,
        "stopOnFirstPass": False, "searchStrategy": "cascade",
        "availableSignalNames": ["r", "y", "iRef", "iL", "u"],
        "signalMappingConfirmed": True,
        "evaluationLoops": [
            {
                "name": "voltage", "role": "outer", "pidPath": "pid_ai_buck_dual_loop_demo/Outer_Voltage_PI",
                "referenceSignalName": "r", "outputSignalName": "y", "controlSignalName": "iRef", "currentSignalName": "iL",
                "weight": 1, "primary": True, "controlLowerLimit": 0, "controlUpperLimit": 8,
                "targets": {"overshootPctMax": 12, "settlingTimeMax": 0.27, "steadyStateErrorAbsMax": 0.1, "maxAbsCurrentMax": 8, "outputRippleMax": 0.2, "controlSaturationFractionMax": 0.03},
            },
            {
                "name": "current", "role": "inner", "pidPath": "pid_ai_buck_dual_loop_demo/Inner_Current_PI",
                "referenceSignalName": "iRef", "outputSignalName": "iL", "controlSignalName": "u", "currentSignalName": "iL",
                "weight": 1, "primary": False, "controlLowerLimit": 0, "controlUpperLimit": 0.95,
                "targets": {"overshootPctMax": 18, "settlingTimeMax": 0.05, "steadyStateErrorAbsMax": 0.2, "maxAbsCurrentMax": 8, "controlSaturationFractionMax": 0.08},
            },
        ],
        "targets": {"overshootPctMax": 12, "settlingTimeMax": 0.27, "steadyStateErrorAbsMax": 0.1},
        "ai": {"mode": "none"},
    })


class Handler(base.Handler):
    def do_POST(self):
        path = urlparse(self.path).path
        request_id = base.new_id("req")
        payload = None
        try:
            if path == "/api/ai/agents/test":
                payload = self.read_json_body()
                result = agent_cli_support.test_agent(payload)
                if result.get("ok"):
                    base.log_request(request_id, "POST", path, 200, payload)
                    result["requestId"] = request_id
                    self.send_json(result, 200, request_id)
                else:
                    error = base.RequestValidationError(
                        result.get("versionOutput") or "Code Agent CLI 测试失败。",
                        "AGENT_TEST_FAILED", "ai.agent"
                    )
                    self.send_api_error(error, 400, request_id, path, payload)
                return
            if path == "/api/pid/jobs/custom":
                payload = self.read_json_body()
                job_id = start_custom_job(payload)
                base.log_request(request_id, "POST", path, 200, payload)
                self.send_json({"jobId": job_id, "status": "started", "requestId": request_id}, 200, request_id)
                return
            if path == "/api/pid/jobs/demo/buck":
                job_id = start_buck_dual_loop_demo()
                base.log_request(request_id, "POST", path, 200)
                self.send_json({"jobId": job_id, "status": "started", "requestId": request_id}, 200, request_id)
                return
            if path == "/api/pid/jobs/demo/single":
                job_id = start_single_pid_demo()
                base.log_request(request_id, "POST", path, 200)
                self.send_json({"jobId": job_id, "status": "started", "requestId": request_id}, 200, request_id)
                return
        except json.JSONDecodeError:
            error = base.RequestValidationError("JSON 请求格式不正确。", "JSON_INVALID")
            self.send_api_error(error, 400, request_id, path, payload)
            return
        except ValueError as error:
            self.send_api_error(error, 400, request_id, path, payload)
            return
        except Exception as error:
            self.send_api_error(error, 500, request_id, path, payload)
            return
        super().do_POST()

    def do_GET(self):
        if urlparse(self.path).path == "/api/health":
            health = base.matlab_health_snapshot()
            self.send_json({
                "ok": True,
                "root": str(base.ROOT),
                "runsDir": str(base.RUNS),
                "matlab": str(base.MATLAB),
                "matlabAvailable": base.MATLAB.is_file(),
                "matlabReady": bool(health.get("ready")),
                "matlabProbeError": health.get("error", ""),
                "matlabCheckedAt": health.get("checkedAt", 0),
                "serverVersion": base.SERVER_VERSION,
                "customModelApi": True,
                "aiModes": ["none", "api", "agent"],
                "aiPresets": True,
                "singlePidDemo": str(base.ROOT / "pid_ai_second_order_demo.slx"),
                "buckDualLoopDemo": str(base.ROOT / "pid_ai_buck_dual_loop_demo.slx"),
            })
            return
        if urlparse(self.path).path == "/api/ai/agents":
            self.send_json({"agents": agent_cli_support.discover_agents()})
            return
        if urlparse(self.path).path == "/api/ai/presets":
            self.send_json(AI_PRESETS)
            return
        if urlparse(self.path).path == "/api/ai/ollama/models":
            try:
                req = Request("http://localhost:11434/api/tags", method="GET")
                resp = urlopen(req, timeout=5)
                data = json.loads(resp.read().decode("utf-8"))
                models = data.get("models", [])
                self.send_json({"models": [{"id": m.get("name", ""), "name": m.get("name", "")} for m in models]})
            except Exception as err:
                self.send_json({"models": [], "error": str(err)})
            return
        super().do_GET()


def main():
    port = int(os.environ.get("PID_GATEWAY_PORT", "8788"))
    base.RUNS.mkdir(exist_ok=True)
    server = base.LocalHTTPServer(("127.0.0.1", port), Handler)
    print(f"PID tuning console with AI: http://127.0.0.1:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
