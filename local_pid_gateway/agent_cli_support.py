import json
import os
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROVIDER = Path(__file__).with_name("agent_cli_pid_provider.py")
AGENT_ORDER = ("codex", "minimax", "claude", "qwen", "kimi", "codebuddy")
AGENT_LABELS = {
    "codex": "Codex CLI",
    "minimax": "MiniMax Code",
    "claude": "Claude Code",
    "qwen": "Qwen Code",
    "kimi": "Kimi Code CLI",
    "codebuddy": "CodeBuddy Code",
}
COMMAND_NAMES = {
    "codex": ("codex",),
    "minimax": ("minimax",),
    "claude": ("claude",),
    "qwen": ("qwen",),
    "kimi": ("kimi",),
    "codebuddy": ("codebuddy", "cbc"),
}


def _known_paths():
    home = Path.home()
    appdata = Path(os.environ.get("APPDATA", str(home / "AppData" / "Roaming")))
    localappdata = Path(os.environ.get("LOCALAPPDATA", str(home / "AppData" / "Local")))
    npm_bin = appdata / "npm"
    project_bin = ROOT / ".tools" / "node_modules" / ".bin"
    paths = {
        "codex": [
            project_bin / "codex.cmd",
            localappdata / "Microsoft" / "WindowsApps" / "codex.exe",
            npm_bin / "codex.cmd",
        ],
        "minimax": [home / ".mavis" / "bin" / "minimax.cmd"],
        "claude": [npm_bin / "claude.cmd"],
        "qwen": [
            project_bin / "qwen.cmd",
            npm_bin / "qwen.cmd",
            localappdata / "Programs" / "qwen-code" / "qwen.exe",
            localappdata / "qwen-code" / "qwen.exe",
        ],
        "kimi": [
            home / ".local" / "bin" / "kimi.exe",
            home / ".local" / "bin" / "kimi",
            appdata / "Python" / "Scripts" / "kimi.exe",
        ],
        "codebuddy": [
            project_bin / "codebuddy.cmd",
            project_bin / "cbc.cmd",
            npm_bin / "codebuddy.cmd",
            npm_bin / "cbc.cmd",
            localappdata / "Programs" / "codebuddy" / "codebuddy.exe",
        ],
    }
    python_roots = [appdata / "Python", localappdata / "Programs" / "Python"]
    for root in python_roots:
        if root.is_dir():
            paths["kimi"].extend(root.glob("Python*/Scripts/kimi.exe"))
    return paths


def _validate_agent_type(agent_type):
    if agent_type not in AGENT_ORDER:
        supported = ", ".join(AGENT_ORDER)
        raise ValueError(f"Code Agent 类型必须是以下之一：{supported}。")


def _find_executable(agent_type):
    _validate_agent_type(agent_type)
    for path in _known_paths().get(agent_type, []):
        if path.is_file():
            return path
    for command_name in COMMAND_NAMES[agent_type]:
        found = shutil.which(command_name)
        if found:
            return Path(found)
    return None


def discover_agents():
    agents = []
    for agent_type in AGENT_ORDER:
        executable = _find_executable(agent_type)
        agents.append({
            "id": agent_type,
            "label": AGENT_LABELS[agent_type],
            "installed": executable is not None,
            "executable": str(executable) if executable else "",
            "readOnly": True,
        })
    return agents


def _resolve_explicit_executable(executable_text):
    expanded = os.path.expandvars(os.path.expanduser(executable_text))
    path = Path(expanded)
    if path.is_file():
        return path
    found = shutil.which(executable_text)
    return Path(found) if found else None


def _resolve_command(agent_type, executable_text):
    _validate_agent_type(agent_type)
    executable = (
        _resolve_explicit_executable(executable_text)
        if executable_text
        else _find_executable(agent_type)
    )
    if executable is None or not executable.is_file():
        raise ValueError(f"未找到 {AGENT_LABELS[agent_type]} 可执行文件。")

    prefix = []
    extra_env = {}
    if executable.suffix.lower() in (".cmd", ".bat") and agent_type == "minimax":
        content = executable.read_text(encoding="utf-8", errors="ignore")
        match = re.search(r'"([^"]+\.exe)"\s+"([^"]+cli\.js)"', content, re.IGNORECASE)
        if not match:
            raise ValueError("无法解析 MiniMax Code 命令包装器。")
        executable = Path(match.group(1))
        prefix = [match.group(2)]
        extra_env["ELECTRON_RUN_AS_NODE"] = "1"
    return executable.resolve(), prefix, extra_env


def normalize_agent_config(raw_ai, num_candidates):
    raw = raw_ai.get("agent") or {}
    agent_type = str(raw.get("type") or "codex").lower()
    _validate_agent_type(agent_type)
    executable, prefix, extra_env = _resolve_command(
        agent_type, str(raw.get("executable") or "").strip()
    )
    timeout = float(raw.get("timeoutSeconds") or 180)
    if timeout < 5 or timeout > 1800:
        raise ValueError("Code Agent 超时必须在 5 到 1800 秒之间。")
    candidate_count = int(raw_ai.get("candidatesPerIteration") or min(4, num_candidates))
    if not 1 <= candidate_count <= num_candidates:
        raise ValueError("Code Agent 每轮候选数必须在 1 和每轮总候选数之间。")

    config = {
        "mode": "agent",
        "sourceLabel": f"agent:{agent_type}",
        "candidatesPerIteration": candidate_count,
        "maxHistoryRecords": int(raw_ai.get("maxHistoryRecords") or 12),
        "failOnError": bool(raw_ai.get("failOnError", False)),
        "local": {
            "pythonExe": str(raw.get("pythonExe") or "python"),
            "scriptPath": str(PROVIDER),
            "timeoutSeconds": timeout + 30,
        },
        "agent": {
            "type": agent_type,
            "model": str(raw.get("model") or ""),
            "name": str(raw.get("name") or "mavis"),
            "timeoutSeconds": timeout,
        },
    }
    environment = {
        "PID_AGENT_TYPE": agent_type,
        "PID_AGENT_EXECUTABLE": str(executable),
        "PID_AGENT_COMMAND_PREFIX": json.dumps(prefix),
        "PID_AGENT_MODEL": config["agent"]["model"],
        "PID_AGENT_NAME": config["agent"]["name"],
        "PID_AGENT_TIMEOUT": str(timeout),
        "PID_AGENT_WORKSPACE": str(ROOT),
    }
    environment.update(extra_env)
    return config, environment


def test_agent(raw):
    agent_type = str(raw.get("type") or "codex").lower()
    executable, prefix, extra_env = _resolve_command(
        agent_type, str(raw.get("executable") or "").strip()
    )
    args = [str(executable), *prefix]
    args.append("version" if agent_type == "minimax" else "--version")
    environment = os.environ.copy()
    environment.update(extra_env)
    try:
        completed = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=20,
            shell=False,
            env=environment,
        )
        output = "\n".join((completed.stdout or "").splitlines()[-12:]).strip()
        return {
            "ok": completed.returncode == 0,
            "agent": agent_type,
            "executable": str(executable),
            "versionOutput": output,
            "exitCode": completed.returncode,
        }
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "agent": agent_type,
            "executable": str(executable),
            "versionOutput": "CLI 测试在 20 秒后超时。",
            "exitCode": None,
        }
    except OSError as error:
        return {
            "ok": False,
            "agent": agent_type,
            "executable": str(executable),
            "versionOutput": f"无法启动 CLI：{error}",
            "exitCode": None,
        }
