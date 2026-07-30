function report = validate_buck_dual_loop_demo()
%VALIDATE_BUCK_DUAL_LOOP_DEMO Simulate and verify both cascade loops.

model = "pid_ai_buck_dual_loop_demo";
if ~isfile(model + ".slx")
    examples.create_buck_dual_loop_demo();
end
load_system(model);
set_param(model, "FastRestart", "off");

cfg = examples.buck_dual_loop_config();
[cfg, ~] = pid_tuning_core.setupPidBlocks(cfg);
output = sim(model, "StopTime", cfg.stopTime);
simulation = struct("success", true, "output", output, "error", "");
metrics = pid_tuning_core.evaluatePidRun(simulation, cfg.initialCandidate, cfg);
validation = pid_tuning_core.validatePidMetrics(metrics, cfg);

roles = lower(string({metrics.loopMetrics.role}));
outer = metrics.loopMetrics(find(roles == "outer", 1));
inner = metrics.loopMetrics(find(roles == "inner", 1));
report = struct("metrics", metrics, "validation", validation, "config", cfg);
fprintf("Buck baseline: pass=%d\n", validation.passed);
fprintf("  voltage: overshoot=%.3f%%, settling=%.4fs, SSE=%.5fV, " + ...
    "Ipeak=%.3fA, ripple=%.5fV, Iref=%.3fA\n", ...
    outer.overshootPct, outer.settlingTime, outer.steadyStateError, ...
    outer.maxAbsCurrent, outer.outputRipple, outer.maxAbsControl);
fprintf("  current: overshoot=%.3f%%, settling=%.4fs, SSE=%.5fA, " + ...
    "IAE=%.5f, duty=%.3f, RMSE=%.5fA\n", ...
    inner.overshootPct, inner.settlingTime, inner.steadyStateError, ...
    inner.iae, inner.maxAbsControl, inner.trackingRmse);
end
