import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = Path(__file__).with_name("pid_candidate_response.schema.json")


def parse_json_object(text):
    text = str(text or "").strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{[\s\S]*\}", text)
    if not match:
        raise ValueError("Agent output did not contain a JSON object.")
    return json.loads(match.group(0))


def validate_response(payload, request):
    candidates = payload.get("candidates") if isinstance(payload, dict) else None
    if not isinstance(candidates, list) or not candidates:
        raise ValueError("Agent response must contain a non-empty candidates array.")
    blocks = request.get("pidBlocks") or []
    if isinstance(blocks, dict):
        blocks = [blocks]
    for candidate_index, candidate in enumerate(candidates, 1):
        pids = candidate.get("pids") if isinstance(candidate, dict) else None
        if isinstance(pids, dict):
            pids = [pids]
            candidate["pids"] = pids
        if not isinstance(pids, list) or len(pids) != len(blocks):
            raise ValueError(f"Candidate {candidate_index} must contain {len(blocks)} PID entries.")
        for pid in pids:
            for field in ("Kp", "Ki", "Kd", "N"):
                value = pid.get(field)
                if not isinstance(value, (int, float)):
                    raise ValueError(f"Candidate {candidate_index} field {field} must be numeric.")
    return {"candidates": candidates[: int(request.get("requestedCandidates", len(candidates)))]}


def build_prompt(request_path, request):
    return (
        "You are a PID tuning candidate advisor. Read the request JSON at "
        f"{request_path}. Analyze the PID bounds, current search center, fixed targets, "
        "and previous Simulink results. Return JSON only, matching the provided schema. "
        f"Return at most {request.get('requestedCandidates', 1)} candidates. "
        "Every candidate must contain one pids item for every pidBlocks item. "
        "Do not modify project files or claim that a candidate passed; Simulink validates every candidate."
    )


def run_process(args, prompt=None, timeout=120, cwd=None, env=None):
    input_bytes = prompt.encode("utf-8") if isinstance(prompt, str) else prompt
    completed = subprocess.run(
        args,
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        cwd=cwd,
        env=env,
        shell=False,
    )
    output = (completed.stdout or b"").decode("utf-8", errors="replace")
    if completed.returncode != 0:
        tail = "\n".join(output.splitlines()[-30:])
        raise RuntimeError(f"Agent CLI exited with {completed.returncode}:\n{tail}")
    return output


def run_codex(command, prompt, output_path, workspace, timeout, model):
    args = [
        *command, "exec", "--cd", str(workspace), "--sandbox", "read-only",
        "--skip-git-repo-check", "--output-schema", str(SCHEMA),
        "--output-last-message", str(output_path), "--color", "never",
    ]
    if model:
        args.extend(["--model", model])
    args.append("-")
    run_process(args, prompt=prompt, timeout=timeout, cwd=workspace)
    if not output_path.is_file():
        raise RuntimeError("Codex did not write the expected output file.")
    return parse_json_object(output_path.read_text(encoding="utf-8"))


def run_claude(command, prompt, workspace, timeout, model):
    schema_text = SCHEMA.read_text(encoding="utf-8")
    args = [*command, "-p", "--output-format", "json", "--json-schema", schema_text]
    if model:
        args.extend(["--model", model])
    raw = run_process(args, prompt=prompt, timeout=timeout, cwd=workspace)
    envelope = parse_json_object(raw)
    result = envelope.get("structured_output") or envelope.get("result") or envelope
    return parse_json_object(result) if isinstance(result, str) else result


def extract_last_json(text):
    starts = [index for index, char in enumerate(text) if char == "{"]
    for start in reversed(starts):
        try:
            return json.loads(text[start:])
        except json.JSONDecodeError:
            continue
    raise ValueError("MiniMax Code CLI output did not contain JSON.")


def run_minimax(command, prompt, workspace, timeout, model, agent_name):
    short_prompt = prompt
    args = [
        *command, "session", "new", agent_name or "mavis", "--from", "root",
        "--prompt", short_prompt, "--workspace", str(workspace),
    ]
    if model:
        args.extend(["--model", model])
    raw = run_process(args, timeout=min(timeout, 45), cwd=workspace)
    created = extract_last_json(raw)
    session_id = created.get("sessionId")
    if not session_id:
        raise RuntimeError("MiniMax Code did not return a sessionId.")

    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            messages_raw = run_process(
                [*command, "session", "messages", session_id, "--limit", "30"],
                timeout=min(30, max(5, deadline - time.monotonic())), cwd=workspace,
            )
            messages_payload = extract_last_json(messages_raw)
            messages = messages_payload.get("messages", [])
            for message in reversed(messages):
                if message.get("role") == "assistant" and message.get("msgContent"):
                    try:
                        return parse_json_object(message["msgContent"])
                    except (ValueError, json.JSONDecodeError):
                        continue
            time.sleep(2)
        raise TimeoutError(f"MiniMax Code session timed out after {timeout:g} seconds.")
    except Exception:
        try:
            run_process([*command, "session", "abort", session_id], timeout=15, cwd=workspace)
        except Exception:
            pass
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--response", required=True)
    args = parser.parse_args()

    request_path = Path(args.request).resolve()
    response_path = Path(args.response).resolve()
    request = json.loads(request_path.read_text(encoding="utf-8"))
    agent_type = os.environ.get("PID_AGENT_TYPE", "codex").lower()
    executable = os.environ.get("PID_AGENT_EXECUTABLE", agent_type)
    command_prefix = json.loads(os.environ.get("PID_AGENT_COMMAND_PREFIX", "[]"))
    command = [executable, *command_prefix]
    model = os.environ.get("PID_AGENT_MODEL", "").strip()
    agent_name = os.environ.get("PID_AGENT_NAME", "mavis").strip()
    timeout = float(os.environ.get("PID_AGENT_TIMEOUT", "120"))
    workspace = Path(os.environ.get("PID_AGENT_WORKSPACE", str(ROOT))).resolve()
    prompt = build_prompt(request_path, request)

    if agent_type == "codex":
        raw_response = run_codex(command, prompt, response_path.with_suffix(".agent.json"), workspace, timeout, model)
    elif agent_type == "minimax":
        raw_response = run_minimax(command, prompt, workspace, timeout, model, agent_name)
    elif agent_type == "claude":
        raw_response = run_claude(command, prompt, workspace, timeout, model)
    else:
        raise ValueError(f"Unsupported Code Agent: {agent_type}")

    response = validate_response(raw_response, request)
    response["provider"] = f"agent:{agent_type}"
    response_path.write_text(json.dumps(response, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
