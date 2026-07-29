function validation = validatePidMetrics(metrics, cfg)
%VALIDATEPIDMETRICS Apply per-loop hard gates and normalized scoring.

loops = pid_tuning_core.normalizeEvaluationLoops(cfg);
if isfield(metrics, "loopMetrics") && ~isempty(metrics.loopMetrics)
    loopMetrics = metrics.loopMetrics;
else
    loopMetrics = metrics;
    loops = loops(1);
end

loopTemplate = struct("name", "", "role", "", "passed", false, ...
    "failures", strings(0, 1), "score", 0);
loopValidations = repmat(loopTemplate, 0, 1);
allFailures = strings(0, 1);
totalScore = 0;
for index = 1:min(numel(loops), numel(loopMetrics))
    if ~loops(index).enabled
        continue;
    end
    current = localValidateLoop(loopMetrics(index), loops(index), cfg);
    loopValidations(end + 1, 1) = current; %#ok<AGROW>
    prefixed = "loop:" + string(loops(index).name) + ":" + current.failures;
    allFailures = [allFailures; prefixed(:)]; %#ok<AGROW>
    totalScore = totalScore + max(0, double(loops(index).weight)) * current.score;
end

validation = struct();
validation.passed = isempty(allFailures);
validation.failures = allFailures;
validation.score = totalScore;
validation.loopValidations = loopValidations;
end

function validation = localValidateLoop(metrics, loop, cfg)
targets = loop.targets;
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

checks = {
    "overshootPct", "overshootPctMax", false, "overshoot";
    "settlingTime", "settlingTimeMax", false, "settling_time";
    "steadyStateError", "steadyStateErrorAbsMax", true, "steady_state_error";
    "iae", "iaeMax", false, "iae";
    "ise", "iseMax", false, "ise";
    "itae", "itaeMax", false, "itae";
    "maxAbsControl", "maxAbsControlMax", false, "max_abs_control";
    "controlEnergy", "controlEnergyMax", false, "control_energy";
    "maxAbsCurrent", "maxAbsCurrentMax", false, "max_abs_current";
    "outputRipple", "outputRippleMax", false, "output_ripple";
    "controlSaturationFraction", "controlSaturationFractionMax", false, "control_saturation";
    "trackingRmse", "trackingRmseMax", false, "tracking_rmse";
    "disturbancePeak", "disturbancePeakMax", false, "disturbance_peak";
    };
for index = 1:size(checks, 1)
    metricName = checks{index, 1};
    targetName = checks{index, 2};
    absoluteValue = checks{index, 3};
    failureName = checks{index, 4};
    if ~isfield(metrics, metricName) || ~isfield(targets, targetName)
        continue;
    end
    value = double(metrics.(metricName));
    if absoluteValue
        value = abs(value);
    end
    if value > double(targets.(targetName))
        failures(end + 1) = failureName; %#ok<AGROW>
    end
end

score = localNormalizedScore(metrics, targets, cfg.weights);
if ~isempty(failures)
    score = score + cfg.weights.failurePenalty * numel(unique(failures));
end
validation = struct( ...
    "name", string(loop.name), ...
    "role", string(loop.role), ...
    "passed", isempty(failures), ...
    "failures", unique(failures, "stable"), ...
    "score", score);
end

function score = localNormalizedScore(metrics, targets, weights)
score = 0;
score = score + localWeight(weights, "iae") * localScaledMetric(metrics, "iae", "normalizedIae", targets, "iaeMax", 0);
score = score + localWeight(weights, "ise") * localScaledMetric(metrics, "ise", "normalizedIse", targets, "iseMax", 0);
score = score + localWeight(weights, "itae") * localScaledMetric(metrics, "itae", "normalizedItae", targets, "itaeMax", 0);
score = score + localWeight(weights, "overshootPct") * localScaledMetric(metrics, "overshootPct", "", targets, "overshootPctMax", 100);
score = score + localWeight(weights, "settlingTime") * localScaledMetric(metrics, "settlingTime", "", targets, "settlingTimeMax", 0);
score = score + localWeight(weights, "steadyStateError") * localScaledMetric(metrics, "steadyStateError", "normalizedSteadyStateError", targets, "steadyStateErrorAbsMax", 0);
score = score + localWeight(weights, "controlEnergy") * localScaledMetric(metrics, "controlEnergy", "normalizedControlEnergy", targets, "controlEnergyMax", 0);
score = score + localWeight(weights, "maxAbsControl") * localScaledMetric(metrics, "maxAbsControl", "normalizedMaxAbsControl", targets, "maxAbsControlMax", 0);
score = score + localWeight(weights, "maxAbsCurrent") * localTargetOnlyMetric(metrics, "maxAbsCurrent", targets, "maxAbsCurrentMax");
score = score + localWeight(weights, "outputRipple") * localScaledMetric(metrics, "outputRipple", "normalizedOutputRipple", targets, "outputRippleMax", 0);
score = score + localWeight(weights, "controlSaturationFraction") * localScaledMetric(metrics, "controlSaturationFraction", "", targets, "controlSaturationFractionMax", 1);
score = score + localWeight(weights, "trackingRmse") * localScaledMetric(metrics, "trackingRmse", "normalizedTrackingRmse", targets, "trackingRmseMax", 0);
score = score + localWeight(weights, "disturbancePeak") * localTargetOnlyMetric(metrics, "disturbancePeak", targets, "disturbancePeakMax");
end

function value = localScaledMetric(metrics, rawName, normalizedName, targets, targetName, fallbackScale)
raw = localMetric(metrics, rawName);
target = localFiniteTarget(targets, targetName);
if ~isempty(target)
    value = localDivide(raw, target);
elseif strlength(string(normalizedName)) > 0 && isfield(metrics, normalizedName)
    value = abs(localFinite(double(metrics.(normalizedName))));
elseif fallbackScale > 0
    value = abs(localFinite(raw)) / fallbackScale;
else
    value = 0;
end
end

function value = localTargetOnlyMetric(metrics, metricName, targets, targetName)
target = localFiniteTarget(targets, targetName);
if isempty(target)
    value = 0;
else
    value = localDivide(localMetric(metrics, metricName), target);
end
end

function value = localMetric(metrics, name)
if ~isfield(metrics, name)
    value = inf;
else
    value = double(metrics.(name));
end
value = abs(localFinite(value));
end

function target = localFiniteTarget(targets, name)
target = [];
if isfield(targets, name)
    candidate = double(targets.(name));
    if isscalar(candidate) && isfinite(candidate) && candidate >= 0
        target = candidate;
    end
end
end

function value = localDivide(metric, target)
if target == 0
    if metric == 0
        value = 0;
    else
        value = 1e9;
    end
else
    value = abs(localFinite(metric)) / target;
end
end

function value = localWeight(weights, name)
if isfield(weights, name)
    value = double(weights.(name));
else
    value = 0;
end
end

function value = localFinite(value)
if ~isfinite(value)
    value = 1e9;
end
end