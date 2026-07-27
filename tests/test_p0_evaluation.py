import unittest

import numpy as np

from autopid.config.schema import AutoPidConfig, ConstraintConfig
from autopid.evaluation.constraints import evaluate_hard_constraints
from autopid.evaluation.metrics import compute_normalized_metrics
from autopid.evaluation.pipeline import evaluate_simulation
from autopid.evaluation.profiles import select_profile
from autopid.evaluation.scoring import score_feasible_result
from autopid.evaluation.types import MetricResult
from autopid.runners.mock_runner import MockRunner
from autopid.runners.base import SimulationResult


def evaluate_scenario(name, constraints=None):
    config = AutoPidConfig()
    config.model.file = "mock:" + name
    config.constraints = constraints or ConstraintConfig(
        output_min=-1.0, output_max=120.0,
        control_min=0.0, control_max=1.0,
        max_saturation_ratio=0.20, max_overshoot=0.10,
        max_settling_time=0.8, max_steady_state_error=0.03,
        max_current=5.0,
    )
    simulation = MockRunner().run_baseline(config)
    metrics = compute_normalized_metrics(
        simulation.time, simulation.reference, simulation.output, simulation.control,
        control_min=config.constraints.control_min,
        control_max=config.constraints.control_max,
    )
    gate = evaluate_hard_constraints(
        simulation.time, simulation.reference, simulation.output, simulation.control,
        metrics, config.constraints, simulation.success, simulation.solver_error,
        simulation.extra_signals,
    )
    score_feasible_result(metrics, gate, select_profile("generic_step"))
    return metrics, gate


class EvaluationTests(unittest.TestCase):
    def test_normalized_metrics_are_scale_independent(self):
        low, _ = evaluate_scenario("scale10")
        high, _ = evaluate_scenario("scale100")
        for name in ("niae", "nise", "nitae", "nrmse", "normalized_steady_state_error"):
            self.assertAlmostEqual(low.values[name], high.values[name], places=9)

    def test_unstable_candidate_is_rejected_without_score(self):
        _, gate = evaluate_scenario("unstable")
        self.assertFalse(gate.feasible)
        self.assertIsNone(gate.score)
        self.assertTrue(any(item.failure_type in ("divergence", "growing_oscillation")
                            for item in gate.failures))

    def test_saturation_candidate_is_rejected(self):
        _, gate = evaluate_scenario("saturation")
        self.assertFalse(gate.feasible)
        self.assertTrue(any(item.failure_type == "persistent_saturation"
                            for item in gate.failures))

    def test_fast_candidate_over_current_limit_is_rejected(self):
        _, safe = evaluate_scenario("buck")
        _, unsafe = evaluate_scenario("current_limit")
        self.assertTrue(safe.feasible)
        self.assertFalse(unsafe.feasible)
        self.assertTrue(any(item.failure_type == "current_limit"
                            for item in unsafe.failures))

    def test_non_finite_signal_is_rejected(self):
        time = np.linspace(0.0, 1.0, 20)
        output = np.ones(20)
        output[8] = np.nan
        metrics = MetricResult({
            "tail_error_abs": 0.0, "initial_error_abs": 1.0,
            "saturation_ratio": 0.0, "normalized_overshoot": 0.0,
            "settling_time": 0.1, "normalized_steady_state_error": 0.0,
        }, {}, {})
        gate = evaluate_hard_constraints(
            time, np.ones(20), output, np.zeros(20),
            metrics, ConstraintConfig(),
        )
        self.assertFalse(gate.feasible)
        self.assertTrue(any(item.failure_type == "non_finite" for item in gate.failures))

    def test_failed_simulation_returns_structured_gate(self):
        config = AutoPidConfig()
        simulation = SimulationResult(
            np.array([]), np.array([]), np.array([]), np.array([]),
            success=False, solver_error="solver stopped",
        )
        metrics, gate, _ = evaluate_simulation(simulation, config)
        self.assertEqual(metrics.preprocessing["reason"], "simulation_error")
        self.assertFalse(gate.feasible)
        self.assertIsNone(gate.score)
        self.assertTrue(any(item.failure_type == "simulation_error" for item in gate.failures))


if __name__ == "__main__":
    unittest.main()
