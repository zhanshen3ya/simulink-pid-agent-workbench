function stages = buildTuningStages(cfg)
%BUILDTUNINGSTAGES Build single, joint, or cascade tuning stages.

loops = pid_tuning_core.normalizeEvaluationLoops(cfg);
strategy = lower(string(cfg.search.strategy));
roles = lower(string({loops.role}));
isCascade = numel(cfg.pidBlocks) == 2 && ...
    any(roles == "inner") && any(roles == "outer");
if strategy == "auto"
    if isCascade
        strategy = "cascade";
    else
        strategy = "joint";
    end
end

stageTemplate = struct("name", "", "role", "", "iterations", 0, ...
    "activePidIndices", [], "evaluationLoopIndices", [], ...
    "jointRefine", false);
if strategy ~= "cascade" || ~isCascade
    stages = stageTemplate;
    stages.name = "joint";
    stages.role = "joint";
    stages.iterations = cfg.maxIterations;
    stages.activePidIndices = 1:numel(cfg.pidBlocks);
    stages.evaluationLoopIndices = find([loops.enabled]);
    stages.jointRefine = false;
    return;
end

innerLoopIndex = find(roles == "inner", 1);
outerLoopIndex = find(roles == "outer", 1);
innerPidIndex = loops(innerLoopIndex).pidIndex;
outerPidIndex = loops(outerLoopIndex).pidIndex;
if innerPidIndex < 1 || outerPidIndex < 1 || innerPidIndex == outerPidIndex
    error("Cascade loop definitions must map to two different selected PID blocks.");
end

counts = localStageCounts(cfg.maxIterations, cfg.search);
stages = repmat(stageTemplate, 3, 1);
stages(1) = struct("name", "inner-loop", "role", "inner", ...
    "iterations", counts(1), "activePidIndices", innerPidIndex, ...
    "evaluationLoopIndices", innerLoopIndex, "jointRefine", false);
stages(2) = struct("name", "outer-loop", "role", "outer", ...
    "iterations", counts(2), "activePidIndices", outerPidIndex, ...
    "evaluationLoopIndices", [innerLoopIndex, outerLoopIndex], ...
    "jointRefine", false);
stages(3) = struct("name", "joint-refine", "role", "joint", ...
    "iterations", counts(3), "activePidIndices", [innerPidIndex, outerPidIndex], ...
    "evaluationLoopIndices", [innerLoopIndex, outerLoopIndex], ...
    "jointRefine", true);
end

function counts = localStageCounts(total, search)
total = max(3, floor(double(total)));
inner = max(1, floor(total * double(search.innerStageFraction)));
outer = max(1, floor(total * double(search.outerStageFraction)));
joint = total - inner - outer;
if joint < 1
    joint = 1;
    if inner >= outer && inner > 1
        inner = inner - 1;
    elseif outer > 1
        outer = outer - 1;
    end
end
counts = [inner, outer, total - inner - outer];
if counts(3) < 1
    counts(3) = 1;
    counts(2) = max(1, total - counts(1) - counts(3));
end
end