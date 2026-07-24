function validation = validatePidMetrics(metrics, cfg)
%VALIDATEPIDMETRICS Apply hard gates and calculate scalar optimization score.

failures = strings(0, 1);

if ~metrics.simulationSuccess
    failures(end + 1) = "simulation_failed";
end
if ~metrics.isFinite
    failures(end + 1) = "non_finite_output";
end
if ~metrics.isStable
    failures(end + 1) = "unstable_or_unsettled";
end
if metrics.overshootPct > cfg.targets.overshootPctMax
    failures(end + 1) = "overshoot";
end
if metrics.settlingTime > cfg.targets.settlingTimeMax
    failures(end + 1) = "settling_time";
end
if abs(metrics.steadyStateError) > cfg.targets.steadyStateErrorAbsMax
    failures(end + 1) = "steady_state_error";
end
if metrics.iae > cfg.targets.iaeMax
    failures(end + 1) = "iae";
end
if metrics.ise > cfg.targets.iseMax
    failures(end + 1) = "ise";
end
if metrics.itae > cfg.targets.itaeMax
    failures(end + 1) = "itae";
end
if metrics.maxAbsControl > cfg.targets.maxAbsControlMax
    failures(end + 1) = "max_abs_control";
end
if metrics.controlEnergy > cfg.targets.controlEnergyMax
    failures(end + 1) = "control_energy";
end
if metrics.maxAbsCurrent > cfg.targets.maxAbsCurrentMax
    failures(end + 1) = "max_abs_current";
end
if metrics.outputRipple > cfg.targets.outputRippleMax
    failures(end + 1) = "output_ripple";
end
if metrics.controlSaturationFraction > cfg.targets.controlSaturationFractionMax
    failures(end + 1) = "control_saturation";
end

score = 0;
score = score + cfg.weights.iae * localFinite(metrics.iae);
score = score + cfg.weights.ise * localFinite(metrics.ise);
score = score + cfg.weights.itae * localFinite(metrics.itae);
score = score + cfg.weights.overshootPct * localFinite(metrics.overshootPct);
score = score + cfg.weights.settlingTime * localFinite(metrics.settlingTime);
score = score + cfg.weights.steadyStateError * abs(localFinite(metrics.steadyStateError));
score = score + cfg.weights.controlEnergy * localFinite(metrics.controlEnergy);
score = score + cfg.weights.maxAbsControl * localFinite(metrics.maxAbsControl);
score = score + cfg.weights.maxAbsCurrent * localFinite(metrics.maxAbsCurrent);
score = score + cfg.weights.outputRipple * localFinite(metrics.outputRipple);
score = score + cfg.weights.controlSaturationFraction * ...
    localFinite(metrics.controlSaturationFraction);

if ~isempty(failures)
    score = score + cfg.weights.failurePenalty * numel(failures);
end

validation = struct();
validation.passed = isempty(failures);
validation.failures = failures;
validation.score = score;
end

function value = localFinite(value)
if ~isfinite(value)
    value = 1e9;
end
end

