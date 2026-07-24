function [plan, results] = runTuningPlan(plan, progressFcn)
%RUNTUNINGPLAN Execute ready tuning units sequentially with checkpoints.
arguments
    plan struct
    progressFcn = []
end
results = repmat(struct("unitId", "", "result", []), 0, 1);
plan.status = "running";
plan.updatedAt = localTimestamp();
pid_project_manager.savePlan(plan);

for index = 1:numel(plan.units)
    plan.currentUnit = index;
    unit = plan.units(index);
    if startsWith(string(unit.status), "blocked")
        plan.units(index).message = ...
            "Referenced-model execution requires an explicit simulation mapping.";
        localNotify(progressFcn, plan, index);
        pid_project_manager.savePlan(plan);
        continue;
    end
    plan.units(index).status = "running";
    plan.units(index).message = "";
    localNotify(progressFcn, plan, index);
    pid_project_manager.savePlan(plan);
    try
        cfg = localConfig(plan, unit);
        result = main_pid_search(cfg);
        plan.units(index).status = "completed";
        plan.units(index).resultRunId = string(result.config.logging.runId);
        record = struct("unitId", string(unit.unitId), "result", result);
        results(end + 1, 1) = record; %#ok<AGROW>
    catch exception
        plan.units(index).status = "failed";
        plan.units(index).message = string(exception.message);
        plan.status = "failed";
        plan.updatedAt = localTimestamp();
        localNotify(progressFcn, plan, index);
        pid_project_manager.savePlan(plan);
        rethrow(exception);
    end
    plan.updatedAt = localTimestamp();
    localNotify(progressFcn, plan, index);
    pid_project_manager.savePlan(plan);
end

statuses = string({plan.units.status});
if any(startsWith(statuses, "blocked"))
    plan.status = "completed-with-blocked-units";
else
    plan.status = "completed";
end
plan.currentUnit = 0;
plan.updatedAt = localTimestamp();
pid_project_manager.savePlan(plan);
localNotify(progressFcn, plan, 0);
end

function cfg = localConfig(plan, unit)
cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = string(plan.topModelName);
cfg.pidBlocks = unit.pidBlocks;
cfg.stopTime = string(unit.stopTime);
cfg.maxIterations = double(unit.maxIterations);
cfg.numCandidates = double(unit.numCandidates);
cfg.stopOnFirstPass = false;
cfg.referenceSignalName = string(unit.referenceSignalName);
cfg.outputSignalName = string(unit.outputSignalName);
cfg.controlSignalName = string(unit.controlSignalName);
cfg.currentSignalName = string(unit.currentSignalName);
cfg.logging.outputDir = fullfile(string(plan.projectRoot), ...
    "pid_tuning_runs", string(plan.planId), string(unit.unitId));
cfg.logging.runId = string(plan.planId) + "-" + string(unit.unitId);
end

function localNotify(progressFcn, plan, index)
if ~isempty(progressFcn)
    progressFcn(plan, index);
end
end

function value = localTimestamp()
value = string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end