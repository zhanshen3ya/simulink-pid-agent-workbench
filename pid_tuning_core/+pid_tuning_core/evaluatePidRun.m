function metrics = evaluatePidRun(simResult, candidate, cfg)
%EVALUATEPIDRUN Calculate deterministic metrics from a simulation result.

metrics = struct();
metrics.candidate = candidate;
metrics.simulationSuccess = simResult.success;
metrics.error = simResult.error;
metrics.isFinite = false;
metrics.isStable = false;

metricNames = ["overshootPct", "settlingTime", "steadyStateError", ...
    "iae", "ise", "itae", "controlEnergy", "maxAbsControl", ...
    "maxAbsCurrent", "outputRipple", "controlSaturationFraction"];
for name = metricNames
    metrics.(name) = inf;
end

if ~simResult.success
    return;
end

try
    [t, y] = pid_tuning_core.extractSignalVector(simResult.output, cfg.outputSignalName);
catch err
    metrics.error = "Output signal extraction failed: " + string(err.message);
    return;
end

try
    [tr, r] = pid_tuning_core.extractSignalVector(simResult.output, cfg.referenceSignalName);
    if numel(tr) ~= numel(t) || any(abs(tr(:) - t(:)) > 1e-9)
        r = interp1(tr(:), r(:), t(:), "linear", "extrap");
    end
catch err
    metrics.error = "Reference signal extraction failed: " + string(err.message);
    return;
end

try
    [tu, u] = pid_tuning_core.extractSignalVector(simResult.output, cfg.controlSignalName);
    if numel(tu) ~= numel(t) || any(abs(tu(:) - t(:)) > 1e-9)
        u = interp1(tu(:), u(:), t(:), "linear", "extrap");
    end
catch err
    metrics.error = "Control signal extraction failed: " + string(err.message);
    return;
end

t = t(:);
y = y(:);
r = r(:);
e = r - y;

metrics.isFinite = all(isfinite(t)) && all(isfinite(y)) && all(isfinite(r)) && all(isfinite(e));
if ~metrics.isFinite || numel(t) < 2
    metrics.error = "Simulation produced non-finite or insufficient samples.";
    return;
end

tailCount = max(1, round(numel(t) * cfg.metrics.tailFraction));
tailIdx = (numel(t) - tailCount + 1):numel(t);
finalRef = mean(r(tailIdx));
finalY = mean(y(tailIdx));
initialY = y(1);
amplitude = max(abs(finalRef - initialY), eps);

metrics.finalReference = finalRef;
metrics.finalOutput = finalY;
metrics.steadyStateError = finalRef - finalY;

if finalRef >= initialY
    peakDeviation = max(y) - finalRef;
else
    peakDeviation = finalRef - min(y);
end
metrics.overshootPct = max(0, peakDeviation / amplitude * 100);

band = cfg.metrics.settlingBand * amplitude;
outside = find(abs(y - finalRef) > band);
if isempty(outside)
    metrics.settlingTime = 0;
elseif outside(end) == numel(t)
    metrics.settlingTime = inf;
else
    metrics.settlingTime = t(outside(end) + 1);
end

metrics.iae = trapz(t, abs(e));
metrics.ise = trapz(t, e .^ 2);
metrics.itae = trapz(t, t .* abs(e));

if isempty(u)
    metrics.controlEnergy = 0;
    metrics.maxAbsControl = 0;
else
    u = u(:);
    metrics.controlEnergy = trapz(t, u .^ 2);
    metrics.maxAbsControl = max(abs(u));
end

metrics.maxAbsOutput = max(abs(y));
metrics.maxAbsError = max(abs(e));
metrics.outputRipple = max(y(tailIdx)) - min(y(tailIdx));

metrics.maxAbsCurrent = 0;
if isfield(cfg, "currentSignalName") && strlength(string(cfg.currentSignalName)) > 0
    try
        [ti, current] = pid_tuning_core.extractSignalVector( ...
            simResult.output, cfg.currentSignalName);
        if numel(ti) ~= numel(t) || any(abs(ti(:) - t(:)) > 1e-9)
            current = interp1(ti(:), current(:), t(:), "linear", "extrap");
        end
        metrics.maxAbsCurrent = max(abs(current));
    catch err
        metrics.error = "Current signal extraction failed: " + string(err.message);
        metrics.maxAbsCurrent = inf;
    end
end

metrics.controlSaturationFraction = 0;
if ~isempty(u) && isfield(cfg.metrics, "controlUpperLimit") && ...
        isfinite(cfg.metrics.controlUpperLimit)
    tolerance = cfg.metrics.controlSaturationTolerance;
    saturatedThreshold = cfg.metrics.controlUpperLimit * (1 - tolerance);
    metrics.controlSaturationFraction = mean(u >= saturatedThreshold);
end

metrics.isStable = metrics.maxAbsOutput <= cfg.metrics.maxAbsOutput && ...
    metrics.maxAbsError <= cfg.metrics.maxAbsErrorForStable && ...
    isfinite(metrics.settlingTime) && isfinite(metrics.maxAbsCurrent);
end

