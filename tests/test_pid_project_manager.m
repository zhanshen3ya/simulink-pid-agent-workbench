function test_pid_project_manager()
%TEST_PID_PROJECT_MANAGER Verify multi-system scanning and plan constraints.
rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(genpath(rootDir));
if ~isfile(fullfile(rootDir, "pid_ai_multi_system_demo.slx"))
    examples.create_multi_system_pid_demo();
end
catalog = pid_project_manager.scanProjectPids(...
    fullfile(rootDir, "pid_ai_multi_system_demo.slx"));
assert(catalog.controllerCount == 5, "Expected five PID controllers.");
controllers = catalog.controllers;
for index = 1:numel(controllers)
    controllers(index).selected = true;
    controllers(index).referenceSignalName = "r" + index;
    controllers(index).outputSignalName = "y" + index;
    controllers(index).controlSignalName = "u" + index;
    controllers(index).controlLowerLimit = -100;
    controllers(index).controlUpperLimit = 100;
    controllers(index).primaryEvaluation = true;
end
parents = unique(string({controllers.parentSystem}), "stable");
groupNumber = 0;
for parentIndex = 1:numel(parents)
    indices = find(string({controllers.parentSystem}) == parents(parentIndex));
    if numel(indices) == 2
        groupNumber = groupNumber + 1;
        controllers(indices(1)).groupId = "group-" + groupNumber;
        controllers(indices(1)).role = "outer";
        controllers(indices(1)).primaryEvaluation = true;
        controllers(indices(2)).groupId = "group-" + groupNumber;
        controllers(indices(2)).role = "inner";
        controllers(indices(2)).primaryEvaluation = false;
    end
end
catalog.controllers = controllers;
plan = pid_project_manager.buildTuningPlan(catalog);
assert(plan.unitCount == 3, "Expected two joint units and one single unit.");
assert(all(arrayfun(@(unit) numel(unit.pidBlocks) <= 2, plan.units)), ...
    "A tuning unit exceeded the two-PID safety limit.");
assert(all(arrayfun(@(unit) numel(unit.evaluationLoops) == numel(unit.pidBlocks), ...
    plan.units)), "Every selected PID must have an independent evaluation loop.");
assert(sum(string({plan.units.searchStrategy}) == "cascade") == 2, ...
    "The two inner/outer groups must use staged cascade tuning.");

invalidCatalog = catalog;
for index = 1:3
    invalidCatalog.controllers(index).selected = true;
    invalidCatalog.controllers(index).groupId = "invalid-three";
end
for index = 4:numel(invalidCatalog.controllers)
    invalidCatalog.controllers(index).selected = false;
end
caught = false;
try
    pid_project_manager.buildTuningPlan(invalidCatalog);
catch exception
    caught = exception.identifier == "PIDAgent:GroupTooLarge";
end
assert(caught, "A three-PID joint group must be rejected.");

invalidPrimary = catalog;
groupIds = string({invalidPrimary.controllers.groupId});
firstGroup = find(strlength(groupIds) > 0, 1);
sameGroup = find(groupIds == groupIds(firstGroup));
invalidPrimary.controllers(sameGroup(1)).primaryEvaluation = true;
invalidPrimary.controllers(sameGroup(2)).primaryEvaluation = true;
caught = false;
try
    pid_project_manager.buildTuningPlan(invalidPrimary);
catch exception
    caught = exception.identifier == "PIDAgent:InvalidPrimaryLoop";
end
assert(caught, "A dual-loop group with two primary loops must be rejected.");
fprintf("PID project manager tests passed.\n");
end