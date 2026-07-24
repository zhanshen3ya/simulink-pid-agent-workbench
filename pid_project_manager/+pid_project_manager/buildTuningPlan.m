function plan = buildTuningPlan(catalog)
%BUILDTUNINGPLAN Convert selected catalog entries into ordered tuning units.

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
    modelNames = unique(string({members.modelName}));
    if numel(modelNames) ~= 1 || modelNames(1) ~= string(catalog.topModelName)
        executionStatus = "blocked-referenced-model";
    else
        executionStatus = "pending";
    end
    unit = localEmptyUnit();
    unit.unitId = "unit-" + compose("%02d", keyIndex);
    unit.name = localUnitName(members, keyIndex);
    unit.order = min([members.order]);
    unit.mode = localUnitMode(members);
    unit.modelName = string(catalog.topModelName);
    unit.modelPath = string(catalog.topModelPath);
    unit.controllerIds = string({members.controllerId});
    unit.pidBlocks = localPlanBlocks(members);
    unit.referenceSignalName = string(members(1).referenceSignalName);
    unit.outputSignalName = string(members(1).outputSignalName);
    unit.controlSignalName = string(members(1).controlSignalName);
    unit.currentSignalName = string(members(1).currentSignalName);
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
plan.schemaVersion = 1;
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

function unit = localEmptyUnit()
unit = struct("unitId", "", "name", "", "order", 0, "mode", "single", ...
    "modelName", "", "modelPath", "", "controllerIds", strings(0, 1), ...
    "pidBlocks", struct([]), "referenceSignalName", "r", ...
    "outputSignalName", "y", "controlSignalName", "u", ...
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

function blocks = localPlanBlocks(members)
defaultBounds = struct("Kp", [0, 200], "Ki", [0, 200], ...
    "Kd", [0, 50], "N", [1, 1000]);
blocks = repmat(struct("name", "", "path", "", "role", "single", ...
    "bounds", defaultBounds), numel(members), 1);
for index = 1:numel(members)
    blocks(index).name = string(members(index).name);
    blocks(index).path = string(members(index).path);
    blocks(index).role = string(members(index).role);
end
end

function value = localTimestamp()
value = string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end