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
        raise ValueError("AI 模式必须是 none、api、local 或 agent。")

    if mode == "agent":
        config, environment = agent_cli_support.normalize_agent_config(raw, num_candidates)
        return config, "", environment

    try:
        candidate_count = int(raw.get("candidatesPerIteration") or min(4, num_candidates))
    except (TypeError, ValueError):
        raise ValueError("AI 每轮候选数必须是整数。")
    if not 0 <= candidate_count <= num_candidates:
        raise ValueError("AI 每轮候选数必须在 0 和每轮总候选数之间。")

    result = {
        "mode": mode,
        "candidatesPerIteration": candidate_count,
        "maxHistoryRecords": int(raw.get("maxHistoryRecords") or 12),
        "failOnError": bool(raw.get("failOnError", False)),
    }
    api_key = ""

    if mode == "api":
        api = raw.get("api") or {}
        base_url = str(api.get("baseUrl") or "").strip()
        model = str(api.get("model") or "").strip()
        api_key = str(api.get("apiKey") or "").strip()
        if not base_url or not model:
            raise ValueError("API AI 需要 Base URL 和模型名。")
        if not api_key and not _is_localhost_url(base_url):
            raise ValueError("远程 API 需要 API Key（本地端点可留空）。")
        result["api"] = {
            "baseUrl": base_url,
            "model": model,
            "temperature": float(api.get("temperature", 0.25)),
            "maxTokens": int(api.get("maxTokens", 2000)),
            "timeoutSeconds": float(api.get("timeoutSeconds", 120)),
        }

    if mode == "local":
        local = raw.get("local") or {}
        script_text = str(local.get("scriptPath") or "").strip().strip('"')
        if not script_text:
            raise ValueError("本地 Code 模式需要 Python provider 脚本路径。")
        script_path = Path(os.path.expandvars(os.path.expanduser(script_text)))
        if not script_path.is_file():
            raise ValueError(f"本地 AI provider 不存在: {script_path}")
        result["local"] = {
            "pythonExe": str(local.get("pythonExe") or "python"),
            "scriptPath": str(script_path.resolve()),
            "timeoutSeconds": float(local.get("timeoutSeconds", 120)),
        }

    return result, api_key, {}


def launch_job(job_id, script, extra_env=None):
    if not base.MATLAB.is_file():
        raise RuntimeError(f"找不到 MATLAB: {base.MATLAB}")
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

    script = base.ROOT / "local_pid_gateway" / f"run_{job_id}.m"
    script.write_text(
        "cd('{root}');\naddpath(genpath(pwd));\nrun_pid_tuning_from_json('{config}');\n".format(
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
    launch_job(job_id, script, environment)
    return job_id


def start_single_pid_demo():
    model_path = base.ROOT / "pid_ai_second_order_demo.slx"
    if not model_path.is_file():
        raise RuntimeError(f"单 PID Demo 文件不存在: {model_path}")
    return start_custom_job({
        "modelPath": str(model_path),
        "pidBlocks": [{
            "name": "single",
            "path": "pid_ai_second_order_demo/PID Controller",
            "bounds": {"Kp": [0, 40], "Ki": [0, 30], "Kd": [0, 8], "N": [10, 500]},
        }],
        "referenceSignalName": "r",
        "outputSignalName": "y",
        "controlSignalName": "u",
        "stopTime": "8",
        "maxIterations": 8,
        "numCandidates": 12,
        "stopOnFirstPass": False,
        "targets": {"overshootPctMax": 10, "settlingTimeMax": 5, "steadyStateErrorAbsMax": 0.03},
        "ai": {"mode": "none"},
    })


def start_buck_dual_loop_demo():
    model_path = base.ROOT / "pid_ai_buck_dual_loop_demo.slx"
    if not model_path.is_file():
        raise RuntimeError(f"Buck dual-loop Demo model not found: {model_path}")
    return start_custom_job({
        "modelPath": str(model_path),
        "pidBlocks": [
            {
                "name": "voltage",
                "path": "pid_ai_buck_dual_loop_demo/Outer_Voltage_PI",
                "bounds": {"Kp": [0.01, 0.15], "Ki": [4, 24], "Kd": [0, 0], "N": [100, 100]},
            },
            {
                "name": "current",
                "path": "pid_ai_buck_dual_loop_demo/Inner_Current_PI",
                "bounds": {"Kp": [0.015, 0.08], "Ki": [2, 20], "Kd": [0, 0], "N": [100, 100]},
            },
        ],
        "referenceSignalName": "r",
        "outputSignalName": "y",
        "controlSignalName": "u",
        "currentSignalName": "iL",
        "controlUpperLimit": 0.95,
        "stopTime": "0.3",
        "maxIterations": 6,
        "numCandidates": 10,
        "stopOnFirstPass": False,
        "targets": {
            "overshootPctMax": 12,
            "settlingTimeMax": 0.27,
            "steadyStateErrorAbsMax": 0.1,
            "iaeMax": 0.65,
            "maxAbsControlMax": 0.95,
            "maxAbsCurrentMax": 6,
            "outputRippleMax": 0.2,
            "controlSaturationFractionMax": 0.02,
        },
        "ai": {"mode": "none"},
    })


class Handler(base.Handler):
    def do_POST(self):
        path = urlparse(self.path).path
        try:
            if path == "/api/ai/agents/test":
                result = agent_cli_support.test_agent(self.read_json_body())
                self.send_json(result, 200 if result.get("ok") else 400)
                return
            if path == "/api/pid/jobs/custom":
                job_id = start_custom_job(self.read_json_body())
                self.send_json({"jobId": job_id, "status": "started"})
                return
            if path == "/api/pid/jobs/demo/buck":
                job_id = start_buck_dual_loop_demo()
                self.send_json({"jobId": job_id, "status": "started"})
                return
            if path == "/api/pid/jobs/demo/single":
                job_id = start_single_pid_demo()
                self.send_json({"jobId": job_id, "status": "started"})
                return
        except json.JSONDecodeError:
            self.send_json({"error": "JSON 请求格式不正确。"}, 400)
            return
        except ValueError as error:
            self.send_json({"error": str(error)}, 400)
            return
        except Exception as error:
            self.send_json({"error": str(error)}, 500)
            return
        super().do_POST()

    def do_GET(self):
        if urlparse(self.path).path == "/api/health":
            self.send_json({
                "ok": True,
                "root": str(base.ROOT),
                "runsDir": str(base.RUNS),
                "matlab": str(base.MATLAB),
                "matlabAvailable": base.MATLAB.is_file(),
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
