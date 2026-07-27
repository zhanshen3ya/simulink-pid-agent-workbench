"""Command line entry point for P0 discovery and deterministic validation."""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict

from .config.schema import ConfigError, load_config
from .discovery.model_scanner import analyze_scan
from .evaluation.pipeline import evaluate_simulation
from .runners.matlab_runner import MatlabRunner
from .runners.mock_runner import MockRunner


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="autopid", description="AutoPID P0 scanner and validator")
    parser.add_argument("command", choices=("scan", "baseline", "validate"))
    parser.add_argument("--config", required=True, help="YAML or JSON configuration")
    parser.add_argument("--runner", choices=("mock", "matlab"), default="mock")
    parser.add_argument("--output", help="Optional JSON result path")
    return parser


def execute(args: argparse.Namespace) -> Dict[str, Any]:
    config = load_config(args.config)
    runner = MockRunner() if args.runner == "mock" else MatlabRunner()
    if args.command == "scan":
        discovery = analyze_scan(
            runner.scan(config),
            config.discovery.auto_accept_confidence,
            config.discovery.minimum_confidence,
        )
        return {"command": "scan", "config": config.to_dict(), "discovery": discovery.to_dict()}

    simulation = runner.run_baseline(config)
    metrics, gate, profile = evaluate_simulation(
        simulation, config, config.signals.measurement or ""
    )
    result = {
        "command": args.command,
        "config": config.to_dict(),
        "simulation": {
            "success": simulation.success,
            "solver_error": simulation.solver_error,
            "metadata": simulation.metadata,
        },
        "profile": profile.name,
        "metrics": metrics.to_dict(),
        "gate": gate.to_dict(),
    }
    if args.command == "validate":
        result["discovery"] = analyze_scan(
            runner.scan(config),
            config.discovery.auto_accept_confidence,
            config.discovery.minimum_confidence,
        ).to_dict()
    return result


def main(argv: Any = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        result = execute(args)
        text = json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False)
        if args.output:
            output = Path(args.output)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(text + "\n", encoding="utf-8")
        print(text)
        return 0
    except (ConfigError, ValueError, KeyError, RuntimeError, OSError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
