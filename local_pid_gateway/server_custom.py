import json
import hashlib
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
REQUEST_LOG = ROOT / "local_pid_gateway" / "gateway_requests.jsonl"
REQUEST_LOG_LOCK = threading.Lock()
SERVER_VERSION = "0.5.0-beta.1"
MATLAB_HEALTH_CACHE = {"checkedAt": 0.0, "ready": False, "error": "正在检查 MATLAB"}
MATLAB_HEALTH_LOCK = threading.Lock()
MATLAB_HEALTH_PROBING = False
MATLAB_HEALTH_TTL_SECONDS = 900


def probe_matlab(force=False):
    now = time.time()
    with MATLAB_HEALTH_LOCK:
        cached = dict(MATLAB_HEALTH_CACHE)
    if not force and now - cached["checkedAt"] < MATLAB_HEALTH_TTL_SECONDS:
        return cached
    result = {"checkedAt": now, "ready": False, "error": ""}
    if not MATLAB.is_file():
        result["error"] = f"MATLAB executable not found: {MATLAB}"
    else:
        try:
            completed = subprocess.run(
                [str(MATLAB), "-batch", "disp('PID_AGENT_MATLAB_OK')"],
                cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, errors="replace", timeout=30,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            result["ready"] = completed.returncode == 0 and "PID_AGENT_MATLAB_OK" in (completed.stdout or "")
            if not result["ready"]:
                result["error"] = "\n".join((completed.stdout or "").splitlines()[-8:]) or f"MATLAB exited with code {completed.returncode}"
        except subprocess.TimeoutExpired:
            result["error"] = "MATLAB 启动检查超过 30 秒"
        except Exception as error:
            result["error"] = str(error)
    with MATLAB_HEALTH_LOCK:
        MATLAB_HEALTH_CACHE.update(result)
        return dict(MATLAB_HEALTH_CACHE)


def matlab_health_snapshot():
    global MATLAB_HEALTH_PROBING
    with MATLAB_HEALTH_LOCK:
        snapshot = dict(MATLAB_HEALTH_CACHE)
        stale = time.time() - snapshot["checkedAt"] >= MATLAB_HEALTH_TTL_SECONDS
        if stale and not MATLAB_HEALTH_PROBING:
            MATLAB_HEALTH_PROBING = True
            should_start = True
        else:
            should_start = False
    if should_start:
        def refresh():
            global MATLAB_HEALTH_PROBING
            try:
                probe_matlab(force=True)
            finally:
                with MATLAB_HEALTH_LOCK:
                    MATLAB_HEALTH_PROBING = False
        threading.Thread(target=refresh, daemon=True).start()
    return snapshot


SENSITIVE_FIELDS = {"apikey", "api_key", "authorization", "password", "secret", "token"}


class RequestValidationError(ValueError):
    def __init__(self, message, code="INVALID_REQUEST", field=""):
        super().__init__(message)
        self.code = code
        self.field = field


def error_payload(error, request_id, default_code="INVALID_REQUEST"):
    message = str(error)
    result = {
        "error": message,
        "message": message,
        "code": getattr(error, "code", default_code),
        "requestId": request_id,
    }
    field = getattr(error, "field", "")
    if field:
        result["field"] = field
    return result


def redact_payload(value):
    if isinstance(value, dict):
        return {
            key: ("***" if str(key).lower() in SENSITIVE_FIELDS else redact_payload(item))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [redact_payload(item) for item in value]
    return value


def log_request(request_id, method, path, status, payload=None, error=None):
    record = {
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "requestId": request_id,
        "method": method,
        "path": path,
        "status": int(status),
    }
    if payload is not None:
        record["payload"] = redact_payload(payload)
    if error is not None:
        record["error"] = error_payload(error, request_id, "INTERNAL_ERROR" if status >= 500 else "INVALID_REQUEST")
    try:
        REQUEST_LOG.parent.mkdir(parents=True, exist_ok=True)
        line = json.dumps(record, ensure_ascii=False) + "\n"
        with REQUEST_LOG_LOCK:
            with REQUEST_LOG.open("a", encoding="utf-8") as stream:
                stream.write(line)
    except OSError:
        pass


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
    run_dir = RUNS / job_id
    status = read_json(run_dir / "current_status.json")
    if isinstance(status, dict):
        request_config = read_json(run_dir / "request_config.json") or {}
        status["jobId"] = job_id
        status["runDir"] = str(run_dir)
        status["modelPath"] = request_config.get("modelPath", "")
        status["resultApplied"] = (run_dir / "apply_manifest.json").is_file()
        status["rollbackAvailable"] = status["resultApplied"]
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
        status = read_json(path / "current_status.json")
        if not isinstance(status, dict):
            continue
        request_config = read_json(path / "request_config.json") or {}
        jobs.append({
            "jobId": path.name,
            "status": status.get("status", "unknown"),
            "modelName": status.get("modelName", ""),
            "modelPath": request_config.get("modelPath", ""),
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
        raise RequestValidationError(
            "请选择 Simulink 模型文件，或输入模型名。", "MODEL_REQUIRED", "modelPath"
        )
    if text.lower().startswith("file:///"):
        text = unquote(text[8:])
    expanded = os.path.expandvars(os.path.expanduser(text))
    path = Path(expanded)
    allowed = (".slx", ".mdl")
    looks_like_path = bool(path.suffix) or path.parent != Path(".")
    if looks_like_path:
        if path.suffix.lower() not in allowed:
            suffix = path.suffix or "<无扩展名>"
            raise RequestValidationError(
                f"请选择 .slx 或 .mdl 模型，当前文件扩展名为 {suffix}: {expanded}",
                "MODEL_TYPE_INVALID", "modelPath"
            )
        if not path.is_file():
            raise RequestValidationError(
                f"模型文件不存在: {expanded}", "MODEL_NOT_FOUND", "modelPath"
            )
        return str(path.resolve())
    return expanded


def normalize_optional_directory(value):
    text = str(value or "").strip().strip('"').strip("'")
    if not text:
        return ""
    path = Path(os.path.expandvars(os.path.expanduser(text)))
    return str(path.resolve()) if path.is_dir() else ""


def normalize_project_path(value):
    if isinstance(value, (list, tuple)):
        return ""
    text = str(value or "").strip().strip('"').strip("'")
    if not text:
        return ""
    path = Path(os.path.expandvars(os.path.expanduser(text)))
    return str(path.resolve()) if path.exists() else ""


def validate_bounds(bounds, pid_index):
    result = {}
    for field in ("Kp", "Ki", "Kd", "N"):
        input_field = f"pidBlocks[{pid_index - 1}].bounds.{field}"
        pair = (bounds or {}).get(field)
        if not isinstance(pair, list) or len(pair) != 2:
            raise RequestValidationError(
                f"PID {pid_index} 的 {field} 边界必须包含最小值和最大值。",
                "PID_BOUNDS_INVALID", input_field
            )
        try:
            low, high = float(pair[0]), float(pair[1])
        except (TypeError, ValueError):
            raise RequestValidationError(
                f"PID {pid_index} 的 {field} 边界必须是数字。",
                "PID_BOUNDS_INVALID", input_field
            )
        if not all(map(lambda item: item == item and abs(item) != float("inf"), (low, high))):
            raise RequestValidationError(
                f"PID {pid_index} 的 {field} 边界必须是有限数字。",
                "PID_BOUNDS_INVALID", input_field
            )
        if low > high:
            raise RequestValidationError(
                f"PID {pid_index} 的 {field} 最小值不能大于最大值。",
                "PID_BOUNDS_REVERSED", input_field
            )
        result[field] = [low, high]
    return result


TARGET_FIELDS = (
    "overshootPctMax", "settlingTimeMax", "steadyStateErrorAbsMax",
    "iaeMax", "iseMax", "itaeMax", "maxAbsControlMax", "controlEnergyMax",
    "maxAbsCurrentMax", "outputRippleMax", "controlSaturationFractionMax",
    "trackingRmseMax", "disturbancePeakMax",
)


def normalize_targets(raw, field_prefix="targets"):
    raw = raw or {}
    if not isinstance(raw, dict):
        raise RequestValidationError("评价指标必须是对象。", "TARGET_INVALID", field_prefix)
    result = {}
    for field in TARGET_FIELDS:
        if field not in raw:
            continue
        try:
            value = float(raw[field])
        except (TypeError, ValueError):
            raise RequestValidationError(
                f"评价指标 {field} 必须是数字。", "TARGET_INVALID", f"{field_prefix}.{field}"
            )
        if value != value or abs(value) == float("inf") or value < 0:
            raise RequestValidationError(
                f"评价指标 {field} 必须是非负有限数字。",
                "TARGET_INVALID", f"{field_prefix}.{field}"
            )
        result[field] = value
    return result


def normalize_control_limits(source, field_prefix=""):
    try:
        lower = float(source.get("controlLowerLimit", -1e12))
        upper = float(source.get("controlUpperLimit", 1e12))
    except (TypeError, ValueError):
        raise RequestValidationError(
            "控制量上下限必须是数字。", "CONTROL_LIMIT_INVALID", field_prefix
        )
    if not all(value == value and abs(value) < float("inf") for value in (lower, upper)):
        raise RequestValidationError(
            "控制量上下限必须是有限数字。", "CONTROL_LIMIT_INVALID", field_prefix
        )
    if lower >= upper:
        raise RequestValidationError(
            "控制量下限必须小于上限。", "CONTROL_LIMIT_INVALID", field_prefix
        )
    return lower, upper


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalize_custom_payload(payload):
    if not isinstance(payload, dict):
        raise RequestValidationError("请求配置必须是 JSON 对象。")
    model_path = normalize_model_path(payload.get("modelPath"))
    raw_blocks = payload.get("pidBlocks")
    if not isinstance(raw_blocks, list) or not 1 <= len(raw_blocks) <= 2:
        raise RequestValidationError(
            "请选择一个或两个 PID 控制器。", "PID_SELECTION_INVALID", "pidBlocks"
        )

    blocks = []
    for index, block in enumerate(raw_blocks, 1):
        path_value = str((block or {}).get("path") or "").strip()
        if not path_value:
            raise RequestValidationError(
                f"PID {index} 缺少 Simulink 块路径。",
                "PID_PATH_REQUIRED", f"pidBlocks[{index - 1}].path"
            )
        blocks.append({
            "name": str((block or {}).get("name") or f"pid{index}"),
            "path": path_value,
            "bounds": validate_bounds((block or {}).get("bounds"), index),
        })

    try:
        max_iterations = int(payload.get("maxIterations") or 20)
        num_candidates = int(payload.get("numCandidates") or 16)
        random_seed = int(payload.get("randomSeed") or 1)
    except (TypeError, ValueError):
        raise RequestValidationError(
            "迭代轮数、候选数和随机种子必须是整数。", "SEARCH_CONFIG_INVALID"
        )
    if max_iterations < 3:
        raise RequestValidationError(
            "迭代轮数至少为 3。", "SEARCH_CONFIG_INVALID", "maxIterations"
        )
    if num_candidates < 2:
        raise RequestValidationError(
            "每轮候选数至少为 2。", "SEARCH_CONFIG_INVALID", "numCandidates"
        )

    stop_time_text = str(payload.get("stopTime") or "10").strip()
    try:
        stop_time_value = float(stop_time_text)
    except (TypeError, ValueError):
        raise RequestValidationError(
            "仿真停止时间必须是数字。", "STOP_TIME_INVALID", "stopTime"
        )
    if not (stop_time_value > 0 and stop_time_value < float("inf")):
        raise RequestValidationError(
            "仿真停止时间必须是正有限数字。", "STOP_TIME_INVALID", "stopTime"
        )

    available = payload.get("availableSignalNames")
    if not isinstance(available, list) or not available:
        raise RequestValidationError(
            "必须提交当前模型的已记录信号清单。",
            "SIGNAL_LIST_REQUIRED", "availableSignalNames"
        )
    available_signal_names = list(dict.fromkeys(
        str(item).strip() for item in available if str(item).strip()
    ))
    if not available_signal_names:
        raise RequestValidationError(
            "当前模型没有可用于评价的已记录信号。",
            "SIGNAL_LIST_REQUIRED", "availableSignalNames"
        )
    if payload.get("signalMappingConfirmed") is not True:
        raise RequestValidationError(
            "必须人工确认每个环路的评价信号映射。",
            "SIGNAL_MAPPING_NOT_CONFIRMED", "signalMappingConfirmed"
        )

    selected_paths = {item["path"] for item in blocks}
    raw_loops = payload.get("evaluationLoops")
    if not isinstance(raw_loops, list) or len(raw_loops) != len(blocks):
        raise RequestValidationError(
            "每个选中的 PID 都必须配置一个独立评价环路。",
            "LOOP_MAPPING_REQUIRED", "evaluationLoops"
        )

    global_targets = normalize_targets(payload.get("targets"))
    global_lower, global_upper = normalize_control_limits(payload)
    loops = []
    used_pid_paths = set()
    for index, raw_loop in enumerate(raw_loops):
        if not isinstance(raw_loop, dict):
            raise RequestValidationError(
                "环路配置必须是对象。", "LOOP_MAPPING_INVALID", f"evaluationLoops[{index}]"
            )
        pid_path = str(raw_loop.get("pidPath") or "").strip()
        if pid_path not in selected_paths or pid_path in used_pid_paths:
            raise RequestValidationError(
                "环路必须唯一对应一个已选 PID。",
                "LOOP_PID_INVALID", f"evaluationLoops[{index}].pidPath"
            )
        used_pid_paths.add(pid_path)
        role = str(raw_loop.get("role") or "single").strip().lower()
        if role not in {"single", "inner", "outer", "coupled"}:
            raise RequestValidationError(
                "环路角色必须是 single、inner、outer 或 coupled。",
                "LOOP_ROLE_INVALID", f"evaluationLoops[{index}].role"
            )
        signals = {}
        for field in ("referenceSignalName", "outputSignalName", "controlSignalName"):
            name = str(raw_loop.get(field) or "").strip()
            if not name:
                raise RequestValidationError(
                    "参考、反馈和控制信号都必须选择。",
                    "SIGNAL_REQUIRED", f"evaluationLoops[{index}].{field}"
                )
            if name not in available_signal_names:
                raise RequestValidationError(
                    f"信号 {name} 尚未启用记录或不属于当前模型。",
                    "SIGNAL_NOT_LOGGED", f"evaluationLoops[{index}].{field}"
                )
            signals[field] = name
        if signals["referenceSignalName"] == signals["outputSignalName"]:
            raise RequestValidationError(
                "参考信号和反馈信号不能相同。",
                "SIGNAL_MAPPING_INVALID", f"evaluationLoops[{index}].outputSignalName"
            )
        current_name = str(raw_loop.get("currentSignalName") or "").strip()
        if current_name and current_name not in available_signal_names:
            raise RequestValidationError(
                f"信号 {current_name} 尚未启用记录或不属于当前模型。",
                "SIGNAL_NOT_LOGGED", f"evaluationLoops[{index}].currentSignalName"
            )
        try:
            weight = float(raw_loop.get("weight", 1))
        except (TypeError, ValueError):
            raise RequestValidationError(
                "环路权重必须是数字。", "LOOP_WEIGHT_INVALID", f"evaluationLoops[{index}].weight"
            )
        if not (weight > 0 and weight < float("inf")):
            raise RequestValidationError(
                "环路权重必须是正有限数字。",
                "LOOP_WEIGHT_INVALID", f"evaluationLoops[{index}].weight"
            )
        loop_lower, loop_upper = normalize_control_limits(
            raw_loop, f"evaluationLoops[{index}]"
        )
        loops.append({
            "name": str(raw_loop.get("name") or f"loop{index + 1}"),
            "role": role,
            "pidPath": pid_path,
            **signals,
            "currentSignalName": current_name,
            "weight": weight,
            "enabled": bool(raw_loop.get("enabled", True)),
            "primary": bool(raw_loop.get("primary", False)),
            "targets": normalize_targets(
                raw_loop.get("targets"), f"evaluationLoops[{index}].targets"
            ),
            "metrics": {
                "controlLowerLimit": loop_lower,
                "controlUpperLimit": loop_upper,
            },
        })

    if used_pid_paths != selected_paths:
        raise RequestValidationError(
            "环路配置必须覆盖全部已选 PID。", "LOOP_MAPPING_INCOMPLETE", "evaluationLoops"
        )
    primary_indices = [index for index, item in enumerate(loops) if item["primary"]]
    if len(primary_indices) != 1:
        raise RequestValidationError(
            "必须且只能指定一个主评价环路。", "PRIMARY_LOOP_INVALID", "evaluationLoops"
        )
    primary = next(item for item in loops if item["primary"])

    strategy = str(payload.get("searchStrategy") or "auto").strip().lower()
    if strategy not in {"auto", "joint", "cascade"}:
        raise RequestValidationError(
            "调参策略必须是 auto、joint 或 cascade。",
            "SEARCH_STRATEGY_INVALID", "searchStrategy"
        )
    roles = {item["role"] for item in loops}
    has_cascade_roles = len(loops) == 2 and roles == {"inner", "outer"}
    has_coupled_roles = len(loops) == 2 and roles == {"coupled"}
    if strategy == "cascade" and not has_cascade_roles:
        raise RequestValidationError(
            "级联双环必须分别标记 inner 和 outer。",
            "CASCADE_ROLE_REQUIRED", "evaluationLoops"
        )
    if strategy == "auto" and len(loops) == 2 and not (has_cascade_roles or has_coupled_roles):
        raise RequestValidationError(
            "自动策略下，两个 PID 必须是明确的内外环，或都标记为 coupled。",
            "AUTO_ROLE_INCONSISTENT", "evaluationLoops"
        )
    if has_cascade_roles and strategy in {"auto", "cascade"}:
        inner = next(item for item in loops if item["role"] == "inner")
        outer = next(item for item in loops if item["role"] == "outer")
        if not outer["primary"]:
            raise RequestValidationError(
                "级联双环必须将外环设为主评价环。",
                "CASCADE_PRIMARY_OUTER_REQUIRED", "evaluationLoops"
            )
        if outer["controlSignalName"] != inner["referenceSignalName"]:
            raise RequestValidationError(
                "级联信号链不完整：外环控制输出必须与内环参考信号相同。",
                "CASCADE_SIGNAL_CHAIN_INVALID", "evaluationLoops"
            )
        inner_settling = inner["targets"].get("settlingTimeMax")
        outer_settling = outer["targets"].get("settlingTimeMax")
        if inner_settling is None or outer_settling is None:
            raise RequestValidationError(
                "级联内外环都必须设置调节时间上限。",
                "CASCADE_SETTLING_TARGET_REQUIRED", "evaluationLoops"
            )
        if inner_settling >= outer_settling:
            raise RequestValidationError(
                "级联评价目标不合理：内环调节时间上限必须小于外环。",
                "CASCADE_TARGET_ORDER_INVALID", "evaluationLoops"
            )

    return {
        "modelPath": model_path,
        "modelFingerprint": file_sha256(model_path),
        "workingDirectory": normalize_optional_directory(payload.get("workingDirectory")),
        "projectRoot": normalize_optional_directory(payload.get("projectRoot")),
        "projectPath": normalize_project_path(payload.get("projectPath")),
        "pidBlocks": blocks,
        "stopTime": stop_time_text,
        "referenceSignalName": primary["referenceSignalName"],
        "outputSignalName": primary["outputSignalName"],
        "controlSignalName": primary["controlSignalName"],
        "currentSignalName": primary["currentSignalName"],
        "evaluationLoops": loops,
        "availableSignalNames": available_signal_names,
        "signalMappingConfirmed": True,
        "evaluationPidPath": primary["pidPath"],
        "controlLowerLimit": global_lower,
        "controlUpperLimit": global_upper,
        "searchStrategy": strategy,
        "maxIterations": max_iterations,
        "numCandidates": num_candidates,
        "randomSeed": random_seed,
        "stopOnFirstPass": bool(payload.get("stopOnFirstPass", False)),
        "useParallel": bool(payload.get("useParallel", False)),
        "targets": global_targets,
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
    health = probe_matlab()
    if not health["ready"]:
        raise RuntimeError("MATLAB 当前不可启动：" + health["error"])
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
        try:
            script.unlink()
        except OSError:
            pass
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

    script = run_dir / "run_job.m"
    script.write_text(
        "root='{root}';\ncd(root);\naddpath(root, fullfile(root,'pid_tuning_core'), fullfile(root,'pid_project_manager'), fullfile(root,'examples'));\nrun_pid_tuning_from_json('{config}');\n".format(
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
    try:
        launch_job(job_id, script)
    except Exception as error:
        write_status(job_id, {
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


def start_demo_job():
    model_path = ROOT / "pid_ai_cascade_two_pid_demo.slx"
    if not model_path.is_file():
        raise RuntimeError(f"级联双环示例模型不存在: {model_path}")
    return start_custom_job({
        "modelPath": str(model_path),
        "pidBlocks": [
            {"name": "outer", "path": "pid_ai_cascade_two_pid_demo/Outer PID", "bounds": {"Kp": [0, 40], "Ki": [0, 30], "Kd": [0, 10], "N": [10, 500]}},
            {"name": "inner", "path": "pid_ai_cascade_two_pid_demo/Inner PID", "bounds": {"Kp": [0, 60], "Ki": [0, 40], "Kd": [0, 10], "N": [10, 500]}},
        ],
        "stopTime": "8", "maxIterations": 9, "numCandidates": 14,
        "stopOnFirstPass": False, "searchStrategy": "cascade",
        "availableSignalNames": ["r", "y", "inner_ref", "inner_y", "u"],
        "signalMappingConfirmed": True,
        "evaluationLoops": [
            {
                "name": "position", "role": "outer", "pidPath": "pid_ai_cascade_two_pid_demo/Outer PID",
                "referenceSignalName": "r", "outputSignalName": "y", "controlSignalName": "inner_ref",
                "currentSignalName": "", "weight": 1, "primary": True,
                "controlLowerLimit": -20, "controlUpperLimit": 20,
                "targets": {"overshootPctMax": 12, "settlingTimeMax": 6, "steadyStateErrorAbsMax": 0.05, "controlSaturationFractionMax": 0.02},
            },
            {
                "name": "velocity", "role": "inner", "pidPath": "pid_ai_cascade_two_pid_demo/Inner PID",
                "referenceSignalName": "inner_ref", "outputSignalName": "inner_y", "controlSignalName": "u",
                "currentSignalName": "", "weight": 1, "primary": False,
                "controlLowerLimit": -100, "controlUpperLimit": 100,
                "targets": {"overshootPctMax": 15, "settlingTimeMax": 2, "steadyStateErrorAbsMax": 0.08, "controlSaturationFractionMax": 0.02},
            },
        ],
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
        "root='{root}'; cd(root); "
        "addpath(root, fullfile(root,'pid_tuning_core'), fullfile(root,'pid_project_manager'), fullfile(root,'examples')); "
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
        with MATLAB_HEALTH_LOCK:
            MATLAB_HEALTH_CACHE.update({
                "checkedAt": time.time(), "ready": True, "error": ""
            })
        return result
    finally:
        for path in (request_file, response_file):
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def run_matlab_action(payload, run_dir, timeout=180):
    request_file = run_dir / "model_action_request.json"
    response_file = run_dir / "model_action_response.json"
    request_file.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    try:
        response_file.unlink(missing_ok=True)
    except TypeError:
        if response_file.exists():
            response_file.unlink()
    command = (
        "root='{root}'; cd(root); "
        "addpath(root, fullfile(root,'pid_tuning_core')); "
        "apply_pid_job_from_json('{request}', '{response}');"
    ).format(
        root=matlab_quote(ROOT.as_posix()),
        request=matlab_quote(request_file.as_posix()),
        response=matlab_quote(response_file.as_posix()),
    )
    completed = subprocess.run(
        [str(MATLAB), "-batch", command], cwd=str(ROOT),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, errors="replace", timeout=timeout,
    )
    if completed.returncode != 0 or not response_file.is_file():
        tail = "\n".join((completed.stdout or "").splitlines()[-16:])
        raise RuntimeError(f"MATLAB 模型操作失败。\n{tail}")
    result = read_json(response_file)
    if not isinstance(result, dict):
        raise RuntimeError("MATLAB 模型操作没有返回有效结果。")
    return result


def apply_job_result(job_id):
    run_dir = RUNS / job_id
    status = read_status(job_id)
    if not isinstance(status, dict) or status.get("status") != "completed":
        raise RequestValidationError(
            "调参任务尚未完成，不能写入阶段性参数。", "JOB_NOT_COMPLETED"
        )
    request_config = read_json(run_dir / "request_config.json")
    best_result = read_json(run_dir / "best_result.json")
    if not isinstance(request_config, dict) or not isinstance(best_result, dict):
        raise RequestValidationError("任务配置或最佳结果不存在。", "JOB_RESULT_MISSING")
    if best_result.get("kind") != "bestPassing":
        raise RequestValidationError(
            "只有通过全部硬指标的参数才允许写入模型。", "BEST_RESULT_NOT_PASSED"
        )
    manifest = run_dir / "apply_manifest.json"
    if manifest.is_file():
        raise RequestValidationError(
            "该任务结果已经写入模型，请先回滚后再应用。", "RESULT_ALREADY_APPLIED"
        )
    result_record = best_result.get("result") or {}
    candidate = result_record.get("candidate")
    if not candidate:
        raise RequestValidationError("最佳结果缺少 PID 参数。", "JOB_RESULT_MISSING")
    return run_matlab_action({
        "action": "apply",
        "modelPath": request_config["modelPath"],
        "pidBlocks": request_config["pidBlocks"],
        "candidate": candidate,
        "runDir": str(run_dir),
        "expectedModelFingerprint": request_config.get("modelFingerprint", ""),
    }, run_dir)


def rollback_job_result(job_id):
    run_dir = RUNS / job_id
    manifest = run_dir / "apply_manifest.json"
    if not manifest.is_file():
        raise RequestValidationError(
            "该任务没有可回滚的模型修改。", "ROLLBACK_NOT_AVAILABLE"
        )
    result = run_matlab_action({
        "action": "rollback", "manifestPath": str(manifest)
    }, run_dir)
    archive = run_dir / f"apply_manifest_rolled_back_{int(time.time())}.json"
    manifest.replace(archive)
    result["archivedManifestPath"] = str(archive)
    return result

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

    def send_json(self, obj, status=200, request_id=""):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Cache-Control", "no-store")
        if request_id:
            self.send_header("X-Request-ID", request_id)
        self.end_headers()
        self.wfile.write(data)

    def send_api_error(self, error, status, request_id, path, payload=None):
        log_request(request_id, "POST", path, status, payload, error)
        default_code = "INTERNAL_ERROR" if status >= 500 else "INVALID_REQUEST"
        self.send_json(error_payload(error, request_id, default_code), status, request_id)

    def read_json_body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 2 * 1024 * 1024:
            raise RequestValidationError("请求正文为空或过大。", "REQUEST_BODY_INVALID")
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Access-Control-Max-Age", "600")
        self.end_headers()

    def do_POST(self):
        path = urlparse(self.path).path
        request_id = new_id("req")
        payload = None
        try:
            if path == "/api/pid/jobs/demo":
                job_id = start_demo_job()
                log_request(request_id, "POST", path, 200)
                self.send_json({"jobId": job_id, "status": "started", "requestId": request_id}, 200, request_id)
                return
            if path == "/api/pid/jobs/custom":
                payload = self.read_json_body()
                job_id = start_custom_job(payload)
                log_request(request_id, "POST", path, 200, payload)
                self.send_json({"jobId": job_id, "status": "started", "requestId": request_id}, 200, request_id)
                return
            if path.startswith("/api/pid/jobs/"):
                parts = path.strip("/").split("/")
                if len(parts) == 5 and parts[4] in {"apply", "rollback"}:
                    job_id = parts[3]
                    if not (RUNS / job_id).is_dir():
                        raise RequestValidationError("任务不存在。", "JOB_NOT_FOUND")
                    if parts[4] == "apply":
                        result = apply_job_result(job_id)
                    else:
                        result = rollback_job_result(job_id)
                    log_request(request_id, "POST", path, 200)
                    self.send_json({**result, "requestId": request_id}, 200, request_id)
                    return
            if path == "/api/pid/models/discover":
                payload = self.read_json_body()
                result = inspect_model(payload.get("modelPath"))
                log_request(request_id, "POST", path, 200, payload)
                self.send_json(result, 200, request_id)
                return
            if path == "/api/pid/models/select":
                selected = select_model_file()
                log_request(request_id, "POST", path, 200)
                self.send_json({"modelPath": selected, "cancelled": not bool(selected)}, 200, request_id)
                return
        except json.JSONDecodeError:
            error = RequestValidationError("JSON 请求格式不正确。", "JSON_INVALID")
            self.send_api_error(error, 400, request_id, path, payload)
            return
        except ValueError as error:
            self.send_api_error(error, 400, request_id, path, payload)
            return
        except Exception as error:
            self.send_api_error(error, 500, request_id, path, payload)
            return
        error = RequestValidationError("接口不存在。", "NOT_FOUND")
        self.send_api_error(error, 404, request_id, path, payload)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/health":
            health = matlab_health_snapshot()
            self.send_json({
                "ok": True, "root": str(ROOT), "runsDir": str(RUNS),
                "matlab": str(MATLAB), "matlabAvailable": MATLAB.is_file(),
                "matlabReady": bool(health.get("ready")),
                "matlabProbeError": health.get("error", ""),
                "matlabCheckedAt": health.get("checkedAt", 0),
                "customModelApi": True, "serverVersion": SERVER_VERSION,
            })
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
