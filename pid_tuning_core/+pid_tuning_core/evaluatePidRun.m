function metrics = evaluatePidRun(simResult, candidate, cfg)
%EVALUATEPIDRUN Calculate deterministic metrics for every configured loop.

loops = pid_tuning_core.normalizeEvaluationLoops(cfg);
loopTemplate = localEmptyLoopMetrics();
loopMetrics = repmat(loopTemplate, numel(loops), 1);
for index = 1:numel(loops)
    if loops(index).enabled
        loopMetrics(index) = localEvaluateLoop(simResult, loops(index));
    else
        loopMetrics(index).name = loops(index).name;
        loopMetrics(index).role = loops(index).role;
        loopMetrics(index).enabled = false;
    end
end

primaryIndex = find([loops.primary] & [loops.enabled], 1);
if isempty(primaryIndex)
    primaryIndex = find([loops.enabled], 1);
end
metrics = loopMetrics(primaryIndex);
metrics.candidate = candidate;
metrics.loopMetrics = loopMetrics;
metrics.loopCount = sum([loops.enabled]);
enabledMetrics = loopMetrics([loops.enabled]);
metrics.simulationSuccess = simResult.success && all([enabledMetrics.simulationSuccess]);
metrics.isFinite = all([enabledMetrics.isFinite]);
metrics.isStable = all([enabledMetrics.isStable]);
errors = string({enabledMetrics.error});
errors = errors(strlength(errors) > 0);
metrics.error = strjoin(unique(errors, "stable"), " | ");
end

function metrics = localEvaluateLoop(simResult, loop)
metrics = localEmptyLoopMetrics();
metrics.name = string(loop.name);
metrics.role = string(loop.role);
metrics.pidPath = string(loop.pidPath);
metrics.enabled = logical(loop.enabled);
metrics.simulationSuccess = simResult.success;
metrics.error = string(simResult.error);
if ~simResult.success
    return;
end

try
    [t, y] = pid_tuning_core.extractSignalVector( ...
        simResult.output, loop.outputSignalName);
    [tr, r] = pid_tuning_core.extractSignalVector( ...
        simResult.output, loop.referenceSignalName);
    [tu, u] = pid_tuning_core.extractSignalVector( ...
        simResult.output, loop.controlSignalName);
    r = localAlign(tr, r, t);
    u = localAlign(tu, u, t);
catch exception
    metrics.error = "Signal extraction failed for " + loop.name + ...
        ": " + string(exception.message);
    return;
end

t = t(:);
y = y(:);
r = r(:);
u = u(:);
if numel(t) < 2 || numel(y) ~= numel(t) || numel(r) ~= numel(t) || ...
        numel(u) ~= numel(t)
    metrics.error = "Loop " + loop.name + " produced inconsistent signal lengths.";
    return;
end
e = r - y;
metrics.isFinite = all(isfinite(t)) && all(isfinite(y)) && ...
    all(isfinite(r)) && all(isfinite(u)) && all(isfinite(e));
if ~metrics.isFinite
    metrics.error = "Loop " + loop.name + " produced non-finite samples.";
    return;
end

metrics = localTrackingMetrics(metrics, t, r, y, e, loop.metrics);
metrics.controlEnergy = trapz(t, u .^ 2);
metrics.maxAbsControl = max(abs(u));
duration = max(t(end) - t(1), eps);
controlScale = localControlScale(loop.metrics, metrics.maxAbsControl);
metrics.normalizedControlEnergy = metrics.controlEnergy / max(controlScale ^ 2 * duration, eps);
metrics.normalizedMaxAbsControl = metrics.maxAbsControl / max(controlScale, eps);
metrics.maxAbsOutput = max(abs(y));
metrics.maxAbsError = max(abs(e));
metrics.controlSaturationFraction = localSaturationFraction(u, loop.metrics);
metrics.maxAbsCurrent = localCurrentPeak(simResult.output, t, y, loop);

outputLimit = double(loop.metrics.maxAbsOutput);
errorLimit = double(loop.metrics.maxAbsErrorForStable);
metrics.isStable = metrics.isFinite && metrics.maxAbsOutput <= outputLimit && ...
    metrics.maxAbsError <= errorLimit && isfinite(metrics.settlingTime) && ...
    isfinite(metrics.maxAbsCurrent);
end

function metrics = localTrackingMetrics(metrics, t, r, y, e, options)
segments = localSegments(t, r, options);
segmentResults = repmat(struct("overshootPct", 0, "settlingTime", 0, ...
    "steadyStateError", 0, "disturbancePeak", 0), numel(segments), 1);
for index = 1:numel(segments)
    indices = segments{index};
    segmentResults(index) = localSegmentMetrics( ...
        t(indices), r(indices), y(indices), options);
end

metrics.overshootPct = max([segmentResults.overshootPct]);
metrics.settlingTime = max([segmentResults.settlingTime]);
[~, worstError] = max(abs([segmentResults.steadyStateError]));
metrics.steadyStateError = segmentResults(worstError).steadyStateError;
metrics.disturbancePeak = max([segmentResults.disturbancePeak]);
metrics.iae = trapz(t, abs(e));
metrics.ise = trapz(t, e .^ 2);
relativeTime = t - t(1);
metrics.itae = trapz(relativeTime, relativeTime .* abs(e));
metrics.trackingRmse = sqrt(mean(e .^ 2));
scale = max([max(abs(r)), max(r) - min(r), eps]);
duration = max(t(end) - t(1), eps);
metrics.normalizedIae = metrics.iae / max(scale * duration, eps);
metrics.normalizedIse = metrics.ise / max(scale ^ 2 * duration, eps);
metrics.normalizedItae = metrics.itae / max(scale * duration ^ 2, eps);
metrics.normalizedSteadyStateError = abs(metrics.steadyStateError) / scale;
metrics.normalizedTrackingRmse = metrics.trackingRmse / scale;

tailCount = max(1, round(numel(t) * double(options.tailFraction)));
tailIndices = (numel(t) - tailCount + 1):numel(t);
metrics.finalReference = mean(r(tailIndices));
metrics.finalOutput = mean(y(tailIndices));
metrics.outputRipple = max(y(tailIndices)) - min(y(tailIndices));
metrics.normalizedOutputRipple = metrics.outputRipple / max(scale, eps);
end

function result = localSegmentMetrics(t, r, y, options)
tailCount = max(1, round(numel(t) * double(options.tailFraction)));
tailIndices = (numel(t) - tailCount + 1):numel(t);
finalReference = mean(r(tailIndices));
finalOutput = mean(y(tailIndices));
initialReference = r(1);
initialOutput = y(1);
stepAmplitude = finalReference - initialReference;
responseAmplitude = finalReference - initialOutput;
referenceScale = max([abs(finalReference), abs(stepAmplitude), ...
    abs(responseAmplitude), max(abs(y - finalReference)), eps]);
band = max(double(options.settlingBand) * max(abs(responseAmplitude), ...
    abs(finalReference)), eps * referenceScale);

if abs(responseAmplitude) > double(options.referenceChangeTolerance) * referenceScale
    direction = sign(responseAmplitude);
    peakDeviation = max(direction * y) - direction * finalReference;
    overshoot = max(0, peakDeviation / max(abs(responseAmplitude), eps) * 100);
else
    overshoot = 0;
end

outside = find(abs(y - finalReference) > band);
if isempty(outside)
    settling = 0;
elseif outside(end) == numel(t)
    settling = inf;
else
    settling = t(outside(end) + 1) - t(1);
end
result = struct( ...
    "overshootPct", overshoot, ...
    "settlingTime", settling, ...
    "steadyStateError", finalReference - finalOutput, ...
    "disturbancePeak", max(abs(y - finalReference)));
end

function segments = localSegments(t, r, options)
minimumSamples = max(2, floor(double(options.minimumSegmentSamples)));
if isfinite(double(options.responseStartTime))
    first = find(t >= double(options.responseStartTime), 1);
    if isempty(first)
        first = 1;
    end
else
    first = 1;
end

scale = max([max(abs(r)), max(r) - min(r), eps]);
threshold = max(double(options.referenceChangeTolerance) * scale, eps);
changes = find(abs(diff(r)) > threshold) + 1;
changes = changes(changes >= first);
starts = unique([first; changes(:)], "stable");
ends = [starts(2:end) - 1; numel(t)];
segments = cell(0, 1);
for index = 1:numel(starts)
    if ends(index) - starts(index) + 1 >= minimumSamples
        segments{end + 1, 1} = starts(index):ends(index); %#ok<AGROW>
    end
end
if isempty(segments)
    segments = {first:numel(t)};
end
end

function aligned = localAlign(sourceTime, values, targetTime)
sourceTime = sourceTime(:);
values = values(:);
targetTime = targetTime(:);
if numel(sourceTime) == numel(targetTime) && ...
        all(abs(sourceTime - targetTime) <= 1e-9)
    aligned = values;
    return;
end
if targetTime(1) < sourceTime(1) || targetTime(end) > sourceTime(end)
    error("Signal time ranges do not overlap the evaluation interval.");
end
aligned = interp1(sourceTime, values, targetTime, "linear");
end

function scale = localControlScale(options, observedPeak)
limits = [double(options.controlLowerLimit), double(options.controlUpperLimit)];
finiteLimits = abs(limits(isfinite(limits)));
if isempty(finiteLimits)
    scale = max(double(observedPeak), 1);
else
    scale = max([finiteLimits(:); eps]);
end
end

function fraction = localSaturationFraction(control, options)
upper = double(options.controlUpperLimit);
lower = double(options.controlLowerLimit);
tolerance = double(options.controlSaturationTolerance);
saturated = false(size(control));
if isfinite(upper)
    saturated = saturated | control >= upper - tolerance * max(abs(upper), 1);
end
if isfinite(lower)
    saturated = saturated | control <= lower + tolerance * max(abs(lower), 1);
end
fraction = mean(saturated);
end

function peak = localCurrentPeak(simOutput, t, output, loop)
signalName = string(loop.currentSignalName);
if strlength(signalName) == 0 && any(lower(string(loop.role)) == ["inner", "current"])
    peak = max(abs(output));
    return;
end
if strlength(signalName) == 0
    peak = 0;
    return;
end
try
    [ti, current] = pid_tuning_core.extractSignalVector(simOutput, signalName);
    current = localAlign(ti, current, t);
    peak = max(abs(current));
catch
    peak = inf;
end
end

function metrics = localEmptyLoopMetrics()
metrics = struct( ...
    "name", "", ...
    "role", "", ...
    "pidPath", "", ...
    "enabled", true, ...
    "simulationSuccess", false, ...
    "error", "", ...
    "isFinite", false, ...
    "isStable", false, ...
    "overshootPct", inf, ...
    "settlingTime", inf, ...
    "steadyStateError", inf, ...
    "iae", inf, ...
    "ise", inf, ...
    "itae", inf, ...
    "normalizedIae", inf, ...
    "normalizedIse", inf, ...
    "normalizedItae", inf, ...
    "normalizedSteadyStateError", inf, ...
    "trackingRmse", inf, ...
    "normalizedTrackingRmse", inf, ...
    "disturbancePeak", inf, ...
    "controlEnergy", inf, ...
    "normalizedControlEnergy", inf, ...
    "maxAbsControl", inf, ...
    "normalizedMaxAbsControl", inf, ...
    "maxAbsCurrent", inf, ...
    "outputRipple", inf, ...
    "normalizedOutputRipple", inf, ...
    "controlSaturationFraction", inf, ...
    "maxAbsOutput", inf, ...
    "maxAbsError", inf, ...
    "finalReference", NaN, ...
    "finalOutput", NaN);
end