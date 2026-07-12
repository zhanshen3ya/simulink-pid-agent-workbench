import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
WEB = Path(__file__).resolve().parent / "web"
RUNS = ROOT / "pid_tuning_runs"
MATLAB = Path(r"D:\MATLAB\bin\matlab.exe")

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
        line = line.strip()
        if not line:
            continue
        try:
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
def list_jobs():
    if not RUNS.exists():
        return []
    jobs = []
    for p in sorted(RUNS.iterdir(), key=lambda x: x.stat().st_mtime, reverse=True):
        if not p.is_dir():
            continue
        status = read_json(p / "current_status.json") or {}
        jobs.append({
            "jobId": p.name,
            "status": status.get("status", "unknown"),
            "modelName": status.get("modelName", ""),
            "updatedAt": status.get("updatedAt", ""),
            "runDir": str(p),
        })
    return jobs


def start_demo_job():
    job_id = time.strftime("job_%Y%m%d_%H%M%S")
    script = ROOT / "local_pid_gateway" / f"run_{job_id}.m"
    script.write_text(f"""
cd('{ROOT.as_posix()}');
addpath(genpath(pwd));
if ~exist('pid_ai_cascade_two_pid_demo.slx', 'file')
    examples.create_cascade_two_pid_demo;
end
cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "pid_ai_cascade_two_pid_demo";
cfg.stopTime = "8";
cfg.pidBlocks(1).name = "outer";
cfg.pidBlocks(1).path = "pid_ai_cascade_two_pid_demo/Outer PID";
cfg.pidBlocks(1).bounds.Kp = [0, 40];
cfg.pidBlocks(1).bounds.Ki = [0, 30];
cfg.pidBlocks(1).bounds.Kd = [0, 10];
cfg.pidBlocks(1).bounds.N = [10, 500];
cfg.pidBlocks(2).name = "inner";
cfg.pidBlocks(2).path = "pid_ai_cascade_two_pid_demo/Inner PID";
cfg.pidBlocks(2).bounds.Kp = [0, 60];
cfg.pidBlocks(2).bounds.Ki = [0, 40];
cfg.pidBlocks(2).bounds.Kd = [0, 10];
cfg.pidBlocks(2).bounds.N = [10, 500];
cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";
cfg.maxIterations = 8;
cfg.numCandidates = 14;
cfg.stopOnFirstPass = false;
cfg.targets.overshootPctMax = 12;
cfg.targets.settlingTimeMax = 6;
cfg.targets.steadyStateErrorAbsMax = 0.05;
cfg.logging.outputDir = fullfile(pwd, 'pid_tuning_runs');
cfg.logging.runId = "{job_id}";
result = main_pid_search(cfg);
""", encoding="utf-8")

    cmd = [str(MATLAB), "-batch", f"run('{script}')"]
    proc = subprocess.Popen(cmd, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    JOBS[job_id] = {"process": proc, "script": str(script)}

    def pump():
        log_path = RUNS / job_id / "matlab_stdout.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with log_path.open("w", encoding="utf-8", errors="ignore") as f:
            for line in proc.stdout or []:
                f.write(line)
                f.flush()

    threading.Thread(target=pump, daemon=True).start()
    return job_id


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

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/api/pid/jobs/demo":
            job_id = start_demo_job()
            self.send_json({"jobId": job_id, "status": "started"})
            return
        self.send_json({"error": "not found"}, 404)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/api/health":
            self.send_json({"ok": True, "root": str(ROOT), "runsDir": str(RUNS)})
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
                    if status is None:
                        self.send_json({"error": "job not found"}, 404)
                    else:
                        self.send_json(status)
                    return
                if len(parts) == 5 and parts[4] == "history":
                    self.send_json({"jobId": job_id, "history": read_history(job_id)})
                    return
                if len(parts) == 5 and parts[4] == "best":
                    self.send_json(read_json(RUNS / job_id / "best_result.json") or {})
                    return
        if path == "/" or path == "/index.html":
            file_path = WEB / "index.html"
        else:
            file_path = WEB / path.lstrip("/")
        if file_path.exists() and file_path.is_file():
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





