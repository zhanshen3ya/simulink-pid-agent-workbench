import json
import os
import shutil
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from socketserver import TCPServer
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
WEB = Path(__file__).resolve().parent / "web"
RUNS = ROOT / "pid_tuning_runs"
def find_matlab_executable():
    configured = os.environ.get("MATLAB_EXE", "").strip().strip('"')
    if configured:
        return Path(configured)

    on_path = shutil.which("matlab")
    if on_path:
        return Path(on_path)

    candidates = [
        Path(r"D:\MATLAB\bin\matlab.exe"),
        *sorted(Path(r"C:\Program Files\MATLAB").glob(r"R*\bin\matlab.exe"), reverse=True),
        *sorted(Path(r"D:\Program Files\MATLAB").glob(r"R*\bin\matlab.exe"), reverse=True),
    ]
    return next((path for path in candidates if path.is_file()), Path("matlab.exe"))


MATLAB = find_matlab_executable()
JOBS = {}


def read_json(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        return None


def read_history(job_id):
    path = RUNS / job_id / "history.jsonl"
    rows = []
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        try:
            if line.strip():
                rows.append(json.loads(line))
        except Exception:
            pass
    return rows


def read_status(job_id):
    status = read_json(RUNS / job_id / "current_status.json")
    if isinstance(status, dict):
        status["jobId"] = job_id
        status["runDir"] = str(RUNS / job_id)
    return status


def write_status(job_id, status):
    run_dir = RUNS / job_id
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "current_status.json").write_text(
        json.dumps(status, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def list_jobs():
    if not RUNS.exists():
        return []
    jobs = []
    for path in sorted(RUNS.iterdir(), key=lambda item: item.stat().st_mtime, reverse=True):
        if not path.is_dir():
            continue
        status = read_json(path / "current_status.json") or {}
        jobs.append({
            "jobId": path.name,
            "status": status.get("status", "unknown"),
            "modelName": status.get("modelName", ""),
            "updatedAt": status.get("updatedAt", ""),
            "runDir": str(path),
        })
    return jobs


def new_id(prefix):
    return f"{prefix}_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"


def matlab_quote(value):
    return str(value).replace("'", "''")


def normalize_model_path(value):
    text = str(value or "").strip().strip('"').strip("'").lstrip("\ufeff")
    if not text:
        raise ValueError("请选择 Simulink 模型文件，或输入模型名。")
    if text.lower().startswith("file:///"):
        text = unquote(text[8:])
    expanded = os.path.expandvars(os.path.expanduser(text))
    path = Path(expanded)
    allowed = (".slx", ".mdl")
    looks_like_path = bool(path.suffix) or path.parent != Path(".")
    if looks_like_path:
        if path.suffix.lower() not in allowed:
            suffix = path.suffix or "<无扩展名>"
            raise ValueError(f"请选择 .slx 或 .mdl 模型，当前文件扩展名为 {suffix}: {expanded}")
        if not path.is_file():
            raise ValueError(f"模型文件不存在: {expanded}")
        return str(path.resolve())
    return expanded


def validate_bounds(bounds, pid_index):
    result = {}
    for field in ("Kp", "Ki", "Kd", "N"):
        pair = (bounds or {}).get(field)
        if not isinstance(pair, list) or len(pair) != 2:
            raise ValueError(f"PID {pid_index} 的 {field} 边界必须包含最小值和最大值。")
        try:
            low, high = float(pair[0]), float(pair[1])
        except (TypeError, ValueError):
            raise ValueError(f"PID {pid_index} 的 {field} 边界必须是数字。")
        if not all(map(lambda item: item == item and abs(item) != float("inf"), (low, high))):
            raise ValueError(f"PID {pid_index} 的 {field} 边界必须是有限数字。")
        if low > high:
            raise ValueError(f"PID {pid_index} 的 {field} 最小值不能大于最大值。")
        result[field] = [low, high]
    return result


def normalize_custom_payload(payload):
    if not isinstance(payload, dict):
        raise ValueError("请求配置必须是 JSON 对象。")
    model_path = normalize_model_path(payload.get("modelPath"))
    raw_blocks = payload.get("pidBlocks")
    if not isinstance(raw_blocks, list) or not 1 <= len(raw_blocks) <= 2:
        raise ValueError("请选择一个或两个 PID 控制器。")

    blocks = []
    for index, block in enumerate(raw_blocks, 1):
        path = str((block or {}).get("path") or "").strip()
        if not path:
            raise ValueError(f"PID {index} 缺少 Simulink 块路径。")
        blocks.append({
            "name": str((block or {}).get("name") or f"pid{index}"),
            "path": path,
            "bounds": validate_bounds((block or {}).get("bounds"), index),
        })

    try:
        max_iterations = int(payload.get("maxIterations") or 20)
        num_candidates = int(payload.get("numCandidates") or 16)
        random_seed = int(payload.get("randomSeed") or 1)
    except (TypeError, ValueError):
        raise ValueError("迭代轮数、候选数和随机种子必须是整数。")
    if max_iterations < 1 or num_candidates < 1:
        raise ValueError("迭代轮数和每轮候选数必须大于 0。")

    targets = {}
    for field in (
        "overshootPctMax", "settlingTimeMax", "steadyStateErrorAbsMax",
        "iaeMax", "iseMax", "itaeMax", "maxAbsControlMax", "controlEnergyMax",
        "maxAbsCurrentMax", "outputRippleMax", "controlSaturationFractionMax",
    ):
        if field in (payload.get("targets") or {}):
            try:
                targets[field] = float(payload["targets"][field])
            except (TypeError, ValueError):
                raise ValueError(f"验证指标 {field} 必须是数字。")

    return {
        "modelPath": model_path,
        "pidBlocks": blocks,
        "stopTime": str(payload.get("stopTime") or "10"),
        "referenceSignalName": str(payload.get("referenceSignalName") or "r"),
        "outputSignalName": str(payload.get("outputSignalName") or "y"),
        "controlSignalName": str(payload.get("controlSignalName") or "u"),
        "currentSignalName": str(payload.get("currentSignalName") or ""),
        "controlUpperLimit": float(payload.get("controlUpperLimit") or 1e12),
        "maxIterations": max_iterations,
        "numCandidates": num_candidates,
        "randomSeed": random_seed,
        "stopOnFirstPass": bool(payload.get("stopOnFirstPass", False)),
        "useParallel": bool(payload.get("useParallel", False)),
        "targets": targets,
    }


def trigger_code_backup(job_id):
    if os.environ.get("PID_GIT_AUTO_BACKUP", "1").lower() in ("0", "false", "off"):
        return
    script = ROOT / "local_pid_gateway" / "git_code_backup.ps1"
    if not script.is_file():
        return
    subprocess.Popen(
        [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(script), "-JobId", str(job_id), "-Root", str(ROOT),
        ],
        cwd=str(ROOT),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )

def launch_job(job_id, script):
    if not MATLAB.is_file():
        raise RuntimeError(f"找不到 MATLAB: {MATLAB}")
    process = subprocess.Popen(
        [str(MATLAB), "-batch", f"run('{matlab_quote(script)}')"],
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    JOBS[job_id] = {"process": process, "script": str(script)}

    def pump():
        log_path = RUNS / job_id / "matlab_stdout.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8", errors="ignore") as stream:
            for line in process.stdout or []:
                stream.write(line)
                stream.flush()
        return_code = process.wait()
        if return_code != 0:
            current = read_status(job_id) or {}
            current.update({
                "jobId": job_id,
                "status": "failed",
                "error": f"MATLAB 任务退出，代码 {return_code}。请查看 matlab_stdout.log。",
                "updatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
            })
            write_status(job_id, current)
        else:
            trigger_code_backup(job_id)

    threading.Thread(target=pump, daemon=True).start()


def start_custom_job(payload):
    config = normalize_custom_payload(payload)
    job_id = new_id("job")
    config["runId"] = job_id
    run_dir = RUNS / job_id
    run_dir.mkdir(parents=True, exist_ok=True)
    config_file = run_dir / "request_config.json"
    config_file.write_text(json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8")

    script = ROOT / "local_pid_gateway" / f"run_{job_id}.m"
    script.write_text(
        "cd('{root}');\naddpath(genpath(pwd));\nrun_pid_tuning_from_json('{config}');\n".format(
            root=matlab_quote(ROOT.as_posix()),
            config=matlab_quote(config_file.as_posix()),
        ),
        encoding="utf-8",
    )
    model_path = Path(config["modelPath"])
    model_name = model_path.stem if model_path.suffix.lower() in (".slx", ".mdl") else config["modelPath"]
    write_status(job_id, {
        "jobId": job_id,
        "status": "queued",
        "modelName": model_name,
        "currentIteration": 0,
        "maxIterations": config["maxIterations"],
        "testedCount": 0,
        "passedCount": 0,
        "elapsedSeconds": 0,
        "updatedAt": time.strftime("%Y-%m-%d %H:%M:%S"),
    })
    launch_job(job_id, script)
    return job_id


def start_demo_job():
    return start_custom_job({
        "modelPath": str(ROOT / "pid_ai_cascade_two_pid_demo.slx"),
        "pidBlocks": [
            {"name": "outer", "path": "pid_ai_cascade_two_pid_demo/Outer PID", "bounds": {"Kp": [0, 40], "Ki": [0, 30], "Kd": [0, 10], "N": [10, 500]}},
            {"name": "inner", "path": "pid_ai_cascade_two_pid_demo/Inner PID", "bounds": {"Kp": [0, 60], "Ki": [0, 40], "Kd": [0, 10], "N": [10, 500]}},
        ],
        "stopTime": "8",
        "referenceSignalName": "r",
        "outputSignalName": "y",
        "controlSignalName": "u",
        "maxIterations": 8,
        "numCandidates": 14,
        "stopOnFirstPass": False,
        "targets": {"overshootPctMax": 12, "settlingTimeMax": 6, "steadyStateErrorAbsMax": 0.05},
    })


def inspect_model(model_path):
    if not MATLAB.is_file():
        raise RuntimeError(f"找不到 MATLAB: {MATLAB}")
    request_id = new_id("inspect")
    request_file = ROOT / "local_pid_gateway" / f"{request_id}.json"
    response_file = ROOT / "local_pid_gateway" / f"{request_id}_result.json"
    request_file.write_text(json.dumps({"modelPath": normalize_model_path(model_path)}, ensure_ascii=False), encoding="utf-8")
    command = (
        "cd('{root}'); addpath(genpath(pwd)); "
        "inspect_pid_model_from_json('{request}', '{response}');"
    ).format(
        root=matlab_quote(ROOT.as_posix()),
        request=matlab_quote(request_file.as_posix()),
        response=matlab_quote(response_file.as_posix()),
    )
    try:
        completed = subprocess.run(
            [str(MATLAB), "-batch", command],
            cwd=str(ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=180,
        )
        if completed.returncode != 0 or not response_file.is_file():
            tail = "\n".join((completed.stdout or "").splitlines()[-12:])
            raise RuntimeError(f"MATLAB 模型扫描失败。\n{tail}")
        result = read_json(response_file)
        if not isinstance(result, dict):
            raise RuntimeError("MATLAB 返回的模型扫描结果无效。")
        return result
    finally:
        for path in (request_file, response_file):
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def select_model_file():
    script = r"""
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = 'Select Simulink model'
$dialog.Filter = 'Simulink models (*.slx;*.mdl)|*.slx;*.mdl'
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName }
"""
    completed = subprocess.run(
        ["powershell.exe", "-NoProfile", "-STA", "-WindowStyle", "Hidden", "-Command", script],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=300,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "无法打开模型文件选择框。")
    return completed.stdout.strip()


class LocalHTTPServer(ThreadingHTTPServer):
    def server_bind(self):
        TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def send_json(self, obj, status=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def read_json_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 2 * 1024 * 1024:
            raise ValueError("请求正文为空或过大。")
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            if path == "/api/pid/jobs/demo":
                job_id = start_demo_job()
                self.send_json({"jobId": job_id, "status": "started"})
                return
            if path == "/api/pid/jobs/custom":
                job_id = start_custom_job(self.read_json_body())
                self.send_json({"jobId": job_id, "status": "started"})
                return
            if path == "/api/pid/models/discover":
                self.send_json(inspect_model(self.read_json_body().get("modelPath")))
                return
            if path == "/api/pid/models/select":
                selected = select_model_file()
                self.send_json({"modelPath": selected, "cancelled": not bool(selected)})
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
        self.send_json({"error": "not found"}, 404)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/health":
            self.send_json({"ok": True, "root": str(ROOT), "runsDir": str(RUNS), "matlab": str(MATLAB), "matlabAvailable": MATLAB.is_file(), "customModelApi": True})
            return
        if path == "/api/pid/jobs":
            self.send_json({"jobs": list_jobs()})
            return
        if path.startswith("/api/pid/jobs/"):
            parts = path.strip("/").split("/")
            if len(parts) >= 4:
                job_id = parts[3]
                if len(parts) == 4:
                    status = read_status(job_id)
                    self.send_json(status or {"error": "job not found"}, 200 if status else 404)
                    return
                if len(parts) == 5 and parts[4] == "history":
                    self.send_json({"jobId": job_id, "history": read_history(job_id)})
                    return
                if len(parts) == 5 and parts[4] == "best":
                    self.send_json(read_json(RUNS / job_id / "best_result.json") or {})
                    return

        file_path = WEB / "index_custom.html" if path in ("/", "/index.html") else WEB / path.lstrip("/")
        if file_path.exists() and file_path.is_file() and WEB.resolve() in file_path.resolve().parents:
            data = file_path.read_bytes()
            content_type = "text/plain"
            if file_path.suffix == ".html":
                content_type = "text/html; charset=utf-8"
            elif file_path.suffix == ".css":
                content_type = "text/css; charset=utf-8"
            elif file_path.suffix == ".js":
                content_type = "application/javascript; charset=utf-8"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_json({"error": "not found"}, 404)


def main():
    port = int(os.environ.get("PID_GATEWAY_PORT", "8788"))
    RUNS.mkdir(exist_ok=True)
    server = LocalHTTPServer(("127.0.0.1", port), Handler)
    print(f"PID tuning console: http://127.0.0.1:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
