import argparse
import json
import math
from pathlib import Path


def clipped(value, pair):
    return min(max(float(value), float(pair[0])), float(pair[1]))


def build_candidates(request):
    count = int(request.get("requestedCandidates", 1))
    blocks = request["pidBlocks"]
    if isinstance(blocks, dict):
        blocks = [blocks]
    center_pids = request.get("searchCenter", {}).get("pids", [])
    if isinstance(center_pids, dict):
        center_pids = [center_pids]

    candidates = []
    offsets = [0.0, -0.15, 0.15, -0.3, 0.3]
    for candidate_index in range(count):
        ratio = offsets[candidate_index % len(offsets)]
        pids = []
        for index, block in enumerate(blocks):
            bounds = block["bounds"]
            center = center_pids[index] if index < len(center_pids) else {}
            pid = {"name": block.get("name", f"pid{index + 1}")}
            for field in ("Kp", "Ki", "Kd", "N"):
                pair = bounds[field]
                midpoint = (float(pair[0]) + float(pair[1])) / 2
                current = float(center.get(field, midpoint))
                span = float(pair[1]) - float(pair[0])
                value = clipped(current + ratio * span, pair)
                pid[field] = round(value, 10)
            pids.append(pid)
        candidates.append({"pids": pids})
    return candidates


def main():
    parser = argparse.ArgumentParser(description="Local-code PID candidate provider example")
    parser.add_argument("--request", required=True)
    parser.add_argument("--response", required=True)
    args = parser.parse_args()

    request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    response = {
        "provider": "local-code-example",
        "candidates": build_candidates(request),
    }
    Path(args.response).write_text(json.dumps(response, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
