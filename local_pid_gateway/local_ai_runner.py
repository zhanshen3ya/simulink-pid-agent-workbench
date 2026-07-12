import argparse
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", required=True)
    parser.add_argument("--script", required=True)
    parser.add_argument("--request", required=True)
    parser.add_argument("--response", required=True)
    parser.add_argument("--timeout", type=float, default=120)
    args = parser.parse_args()

    command = [args.python, args.script, "--request", args.request, "--response", args.response]
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=args.timeout,
        )
    except subprocess.TimeoutExpired:
        print(f"Provider timed out after {args.timeout:g} seconds.", file=sys.stderr)
        return 124

    if completed.stdout:
        print(completed.stdout, end="")
    if completed.returncode != 0:
        return completed.returncode
    if not Path(args.response).is_file():
        print("Provider returned success but did not write the response file.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
