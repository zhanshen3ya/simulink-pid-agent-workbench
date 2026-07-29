function plan = buildTuningPlan(catalog)
%BUILDTUNINGPLAN Convert selected catalog entries into validated tuning units.

controllers = catalog.controllers;
if isempty(controllers)
    error("PIDAgent:EmptyCatalog", "No PID controllers were discovered.");
end
selected = controllers([controllers.selected]);
if isempty(selected)
    error("PIDAgent:NoSelection", "Select at least one PID controller.");
end
[~, sortIndex] = sort([selected.order]);
selected = selected(sortIndex);
keys = strings(numel(selected), 1);
for index = 1:numel(selected)
    if strlength(string(selected(index).groupId)) == 0
        keys(index) = "single:" + selected(index).controllerId;
    else
        keys(index) = "group:" + string(selected(index).groupId);
    end
end

uniqueKeys = unique(keys, "stable");
units = repmat(localEmptyUnit(), 0, 1);
for keyIndex = 1:numel(uniqueKeys)
    members = selected(keys == uniqueKeys(keyIndex));
    if numel(members) > 2
        error("PIDAgent:GroupTooLarge", ...
            "Group %s contains %d controllers; each unit supports at most two.", ...
            uniqueKeys(keyIndex), numel(members));
    end
    localValidateMembers(members, uniqueKeys(keyIndex));
    modelNames = unique(string({members.modelName}));
    if numel(modelNames) ~= 1 || modelNames(1) ~= string(catalog.topModelName)
        executionStatus = "blocked-referenced-model";
    else
        executionStatus = "pending";
    end

    loops = localEvaluationLoops(members);
    primaryLoop = loops([loops.primary]);
    unit = localEmptyUnit();
    unit.unitId = "unit-" + compose("%02d", keyIndex);
    unit.name = localUnitName(members, keyIndex);
    unit.order = min([members.order]);
    unit.mode = localUnitMode(members);
    unit.searchStrategy = localSearchStrategy(loops);
    unit.modelName = string(catalog.topModelName);
    unit.modelPath = string(catalog.topModelPath);
    unit.controllerIds = string({members.controllerId});
    unit.pidBlocks = localPlanBlocks(members);
    unit.evaluationLoops = loops;
    unit.referenceSignalName = primaryLoop.referenceSignalName;
    unit.outputSignalName = primaryLoop.outputSignalName;
    unit.controlSignalName = primaryLoop.controlSignalName;
    unit.currentSignalName = primaryLoop.currentSignalName;
    unit.stopTime = "10";
    unit.maxIterations = 8;
    unit.numCandidates = 12;
    unit.status = executionStatus;
    units(end + 1, 1) = unit; %#ok<AGROW>
end

[~, unitOrder] = sort([units.order]);
units = units(unitOrder);
for index = 1:numel(units)
    units(index).order = index;
end
plan = struct();
plan.schemaVersion = 2;
plan.planId = "plan-" + string(datetime("now", "Format", "yyyyMMdd-HHmmss"));
plan.createdAt = localTimestamp();
plan.updatedAt = plan.createdAt;
plan.projectRoot = string(catalog.projectRoot);
plan.topModelName = string(catalog.topModelName);
plan.topModelPath = string(catalog.topModelPath);
plan.status = "ready";
plan.currentUnit = 0;
plan.units = units;
plan.unitCount = numel(units);
end

function localValidateMembers(members, key)
if numel(members) == 2
    roles = lower(string({members.role}));
    isCascade = all(ismember(["inner", "outer"], roles));
    isCoupled = all(roles == "coupled");
    if ~(isCascade || isCoupled)
        error("PIDAgent:InvalidDualLoopRoles", ...
            "Group %s must be one inner/outer cascade pair or two explicitly coupled loops.", key);
    end
end
primaryCount = sum([members.primaryEvaluation]);
if ~isscalar(members) && primaryCount ~= 1
    error("PIDAgent:InvalidPrimaryLoop", ...
        "Group %s must have exactly one primary evaluation loop.", key);
end
for index = 1:numel(members)
    item = members(index);
    requiredSignals = [string(item.referenceSignalName), ...
        string(item.outputSignalName), string(item.controlSignalName)];
    if any(strlength(requiredSignals) == 0)
        error("PIDAgent:MissingEvaluationSignal", ...
            "PID %s requires reference, output, and control signal names.", item.name);
    end
    if requiredSignals(1) == requiredSignals(2)
        error("PIDAgent:InvalidEvaluationSignals", ...
            "PID %s cannot use the same reference and output signal.", item.name);
    end
    if ~(isscalar(item.evaluationWeight) && isfinite(item.evaluationWeight) && ...
            item.evaluationWeight > 0)
        error("PIDAgent:InvalidLoopWeight", ...
            "PID %s evaluation weight must be positive and finite.", item.name);
    end
    if ~(isscalar(item.controlLowerLimit) && isfinite(item.controlLowerLimit) && ...
            isscalar(item.controlUpperLimit) && isfinite(item.controlUpperLimit) && ...
            item.controlLowerLimit < item.controlUpperLimit)
        error("PIDAgent:InvalidControlLimits", ...
            "PID %s requires finite control limits with lower < upper.", item.name);
    end
    targets = [item.overshootPctMax, item.settlingTimeMax, ...
        item.steadyStateErrorAbsMax];
    if any(~isfinite(targets)) || any(targets < 0)
        error("PIDAgent:InvalidLoopTargets", ...
            "PID %s required evaluation targets must be finite and nonnegative.", item.name);
    end
    optionalTargets = [item.trackingRmseMax, item.maxAbsCurrentMax, ...
        item.outputRippleMax, item.controlSaturationFractionMax];
    invalidOptional = ~(isnan(optionalTargets) | ...
        (isfinite(optionalTargets) & optionalTargets >= 0));
    if any(invalidOptional) || ...
            (isfinite(item.controlSaturationFractionMax) && ...
            item.controlSaturationFractionMax > 1)
        error("PIDAgent:InvalidOptionalLoopTargets", ...
            "PID %s optional targets must be NaN or valid nonnegative limits.", item.name);
    end
    if isfinite(item.maxAbsCurrentMax) && ...
            strlength(string(item.currentSignalName)) == 0
        error("PIDAgent:MissingCurrentSignal", ...
            "PID %s has a current limit but no current signal.", item.name);
    end
end
end

function loops = localEvaluationLoops(members)
template = struct("name", "", "role", "single", "pidPath", "", ...
    "referenceSignalName", "", "outputSignalName", "", ...
    "controlSignalName", "", "currentSignalName", "", ...
    "weight", 1, "enabled", true, "primary", false, ...
    "targets", struct(), "metrics", struct());
loops = repmat(template, numel(members), 1);
for index = 1:numel(members)
    item = members(index);
    targets = struct("overshootPctMax", item.overshootPctMax, ...
        "settlingTimeMax", item.settlingTimeMax, ...
        "steadyStateErrorAbsMax", item.steadyStateErrorAbsMax, ...
        "maxAbsControlMax", max(abs([item.controlLowerLimit, item.controlUpperLimit])));
    optionalNames = ["trackingRmseMax", "maxAbsCurrentMax", ...
        "outputRippleMax", "controlSaturationFractionMax"];
    for optionalName = optionalNames
        optionalValue = double(item.(optionalName));
        if isfinite(optionalValue)
            targets.(optionalName) = optionalValue;
        end
    end
    loops(index) = struct("name", string(item.name) + " loop", ...
        "role", string(item.role), "pidPath", string(item.path), ...
        "referenceSignalName", string(item.referenceSignalName), ...
        "outputSignalName", string(item.outputSignalName), ...
        "controlSignalName", string(item.controlSignalName), ...
        "currentSignalName", string(item.currentSignalName), ...
        "weight", double(item.evaluationWeight), "enabled", true, ...
        "primary", logical(item.primaryEvaluation) || isscalar(members), ...
        "targets", targets, "metrics", struct( ...
        "controlLowerLimit", double(item.controlLowerLimit), ...
        "controlUpperLimit", double(item.controlUpperLimit)));
end
end

function unit = localEmptyUnit()
unit = struct("unitId", "", "name", "", "order", 0, "mode", "single", ...
    "searchStrategy", "joint", "modelName", "", "modelPath", "", ...
    "controllerIds", strings(0, 1), "pidBlocks", struct([]), ...
    "evaluationLoops", struct([]), "referenceSignalName", "", ...
    "outputSignalName", "", "controlSignalName", "", ...
    "currentSignalName", "", "stopTime", "10", "maxIterations", 8, ...
    "numCandidates", 12, "status", "pending", "resultRunId", "", ...
    "message", "");
end

function name = localUnitName(members, index)
if isscalar(members)
    name = string(members(1).name);
else
    name = "Group " + compose("%02d", index) + ": " + ...
        strjoin(string({members.name}), " + ");
end
end

function mode = localUnitMode(members)
if numel(members) == 2
    mode = "joint";
else
    mode = "single";
end
end

function strategy = localSearchStrategy(loops)
roles = lower(string({loops.role}));
if numel(loops) == 2 && all(ismember(["inner", "outer"], roles))
    strategy = "cascade";
else
    strategy = "joint";
end
end

function blocks = localPlanBlocks(members)
blocks = repmat(struct("name", "", "path", "", "role", "single", ...
    "bounds", struct()), numel(members), 1);
for index = 1:numel(members)
    blocks(index).name = string(members(index).name);
    blocks(index).path = string(members(index).path);
    blocks(index).role = string(members(index).role);
    blocks(index).bounds = localBoundsAround(members(index).currentPid);
end
end

function bounds = localBoundsAround(pid)
bounds = struct();
bounds.Kp = localRange(pid.Kp, 1);
bounds.Ki = localRange(pid.Ki, 1);
if double(pid.Kd) == 0
    bounds.Kd = [0, 0];
    bounds.N = [double(pid.N), double(pid.N)];
else
    bounds.Kd = localRange(pid.Kd, 0.1);
    bounds.N = localRange(pid.N, 10);
end
end

function range = localRange(value, zeroUpper)
value = double(value);
if value > 0
    range = [max(0, value / 4), value * 4];
elseif value < 0
    range = [value * 4, min(0, value / 4)];
else
    range = [0, zeroUpper];
end
end

function value = localTimestamp()
value = string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end