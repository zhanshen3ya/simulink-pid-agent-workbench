function path = savePlan(plan)
%SAVEPLAN Persist a tuning plan and its execution state.
folder = fullfile(string(plan.projectRoot), ".pid-agent", "plans");
if ~isfolder(folder)
    mkdir(folder);
end
path = fullfile(folder, string(plan.planId) + ".json");
pid_tuning_core.writeJsonFile(path, plan);
end