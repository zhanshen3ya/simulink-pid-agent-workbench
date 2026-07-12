import json
import os
import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROVIDER = Path(__file__).with_name("agent_cli_pid_provider.py")


KNOWN_PATHS = {
    "codex": [
        ROOT / ".tools" / "node_modules" / ".bin" / "codex.cmd",
        Path(os.environ.get("LOCALAPPDATA", str(Path.home() / "AppData" / "Local")))
        / "Microsoft" / "WindowsApps" / "codex.exe",
    ],
    "minimax": [Path.home() / ".mavis" / "bin" / "minimax.cmd"],
    "claude": [Path.home() / "AppData" / "Roaming" / "npm" / "claude.cmd"],
}


def _find_executable(agent_type):
    for path in KNOWN_PATHS.get(agent_type, []):
        if path.is_file():
            return path
    found = shutil.which(agent_type)
    return Path(found) if found else None


def discover_agents():
    labels = {"codex": "Codex CLI", "minimax": "MiniMax Code", "claude": "Claude Code"}
    agents = []
    for agent_type in ("codex", "minimax", "claude"):
        executable = _find_executable(agent_type)
        agents.append({
            "id": agent_type,
            "label": labels[agent_type],
            "installed": executable is not None,
            "executable": str(executable) if executable else "",
        })
    return agents


def _resolve_command(agent_type, executable_text):
    executable = Path(executable_text) if executable_text else _find_executable(agent_type)
    if executable is None or not executable.is_file():
        raise ValueError(f"未找到 {agent_type} Code Agent 可执行程序。")

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
    if agent_type not in ("codex", "minimax", "claude"):
        raise ValueError("Code Agent 类型必须是 codex、minimax 或 claude。")
    executable, prefix, extra_env = _resolve_command(agent_type, str(raw.get("executable") or "").strip())
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
    executable, prefix, extra_env = _resolve_command(agent_type, str(raw.get("executable") or "").strip())
    if agent_type == "minimax":
        args = [str(executable), *prefix, "version"]
    else:
        args = [str(executable), *prefix, "--version"]
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
            "versionOutput": "CLI test timed out after 20 seconds.",
            "exitCode": None,
        }
    except OSError as error:
        return {
            "ok": False,
            "agent": agent_type,
            "executable": str(executable),
            "versionOutput": f"Unable to start CLI: {error}",
            "exitCode": None,
        }
