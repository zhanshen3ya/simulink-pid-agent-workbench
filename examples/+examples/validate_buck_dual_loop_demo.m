function report = validate_buck_dual_loop_demo()
%VALIDATE_BUCK_DUAL_LOOP_DEMO Simulate and verify the baseline electrical design.

model = "pid_ai_buck_dual_loop_demo";
if ~isfile(model + ".slx")
    examples.create_buck_dual_loop_demo();
end
load_system(model);
set_param(model, "FastRestart", "off");
output = sim(model, "StopTime", "0.3");

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";
cfg.currentSignalName = "iL";
cfg.metrics.controlUpperLimit = 0.95;
cfg.targets.overshootPctMax = 12;
cfg.targets.settlingTimeMax = 0.27;
cfg.targets.steadyStateErrorAbsMax = 0.1;
cfg.targets.iaeMax = 0.65;
cfg.targets.maxAbsControlMax = 0.95;
cfg.targets.maxAbsCurrentMax = 6;
cfg.targets.outputRippleMax = 0.2;
cfg.targets.controlSaturationFractionMax = 0.02;

voltagePid = struct("name", "voltage", "Kp", 0.08, "Ki", 8, "Kd", 0, "N", 100);
currentPid = struct("name", "current", "Kp", 0.04, "Ki", 8, "Kd", 0, "N", 100);
simulation = struct("success", true, "output", output, "error", "");
metrics = pid_tuning_core.evaluatePidRun( ...
    simulation, struct("pids", [voltagePid, currentPid]), cfg);
validation = pid_tuning_core.validatePidMetrics(metrics, cfg);

report = struct("metrics", metrics, "validation", validation);
fprintf("Buck baseline: pass=%d, overshoot=%.3f%%, settling=%.4fs, " + ...
    "SSE=%.5fV, Ipeak=%.3fA, ripple=%.5fV, duty=%.3f\n", ...
    validation.passed, metrics.overshootPct, metrics.settlingTime, ...
    metrics.steadyStateError, metrics.maxAbsCurrent, metrics.outputRipple, ...
    metrics.maxAbsControl);
end