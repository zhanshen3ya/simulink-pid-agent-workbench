function result = main_pid_search(cfg)
%MAIN_PID_SEARCH Run staged closed-loop PID generation and Simulink validation.

rootDir = fileparts(mfilename("fullpath"));
addpath(genpath(rootDir));
if nargin < 1 || isempty(cfg)
    cfg = pid_tuning_core.defaultPidTuningConfig();
end
if strlength(string(cfg.modelName)) == 0 || cfg.modelName == "your_model"
    error("Set cfg.modelName before running PID search.");
end

rng(cfg.randomSeed);
load_system(cfg.modelName);
fastRestartCleanup = onCleanup(@() localDisableFastRestart(cfg.modelName)); %#ok<NASGU>
[cfg, currentPid] = pid_tuning_core.setupPidBlocks(cfg);
cfg.evaluationLoops = pid_tuning_core.normalizeEvaluationLoops(cfg);
stages = pid_tuning_core.buildTuningStages(cfg);
cfg = pid_tuning_core.prepareRunLogging(cfg);
runTimer = tic;

state = localInitialState(cfg, stages);
if ~isfield(cfg, "evaluateBaseline") || cfg.evaluateBaseline
    state.baseline = localEvaluateBaseline(cfg, state, runTimer);
    state.elapsedSeconds = toc(runTimer);
end
pid_tuning_core.writeCurrentStatus("running", state, [], [], cfg);
localPrintRunHeader(cfg, stages);

globalIteration = 0;
finalCurrent = [];
finalRecent = [];
for stageIndex = 1:numel(stages)
    stage = stages(stageIndex);
    stageCfg = localStageConfig(cfg, stage, state.searchCenter);
    state.currentStage = string(stage.name);
    state.stageIndex = stageIndex;
    state.stageCount = numel(stages);
    state.best = [];
    state.bestPassing = [];
    state.searchScale = stageCfg.search.initialScale;
    fprintf("\nStage %d/%d: %s (%d iterations)\n", ...
        stageIndex, numel(stages), stage.name, stage.iterations);

    for stageIteration = 1:stage.iterations
        globalIteration = globalIteration + 1;
        state.iteration = globalIteration;
        state.stageIteration = stageIteration;
        candidates = pid_tuning_core.generatePidCandidates( ...
            state, stageCfg, stageCfg.numCandidates);
        fprintf("Iteration %d/%d, stage %d/%d: testing %d candidates...\n", ...
            globalIteration, cfg.maxIterations, stageIteration, ...
            stage.iterations, numel(candidates));

        records = repmat(localEmptyRecord(), 1, numel(candidates));
        simResults = pid_tuning_core.runCandidateBatch(candidates, stageCfg);
        for candidateIndex = 1:numel(candidates)
            metrics = pid_tuning_core.evaluatePidRun( ...
                simResults(candidateIndex), candidates(candidateIndex), stageCfg);
            validation = pid_tuning_core.validatePidMetrics(metrics, stageCfg);
            records(candidateIndex) = localRecord(globalIteration, stage, ...
                stageIteration, candidateIndex, candidates(candidateIndex), ...
                metrics, validation, state.testedCount + 1);
            state.testedCount = state.testedCount + 1;
            if validation.passed
                state.passedCount = state.passedCount + 1;
            else
                state.failedCount = state.failedCount + 1;
            end
            state.elapsedSeconds = toc(runTimer);
            pid_tuning_core.writeCandidateHistory(records(candidateIndex), state, cfg);
            pid_tuning_core.writeCurrentStatus( ...
                "running", state, records(candidateIndex), ...
                records(1:candidateIndex), cfg);
        end

        state = pid_tuning_core.updatePidSearchState(state, records, stageCfg);
        state.elapsedSeconds = toc(runTimer);
        pid_tuning_core.saveIterationLog(records, state, cfg);
        pid_tuning_core.writeBestResult(state, cfg);
        pid_tuning_core.writeCurrentStatus("running", state, records(end), records, cfg);
        fprintf("Best stage score: %.6g\n", min([records.score]));
        finalCurrent = records(end);
        finalRecent = records;
        if ~isempty(state.bestPassing) && cfg.stopOnFirstPass
            fprintf("Stage target passed; advancing to the next stage.\n");
            break;
        end
    end

    selected = localSelectedRecord(state);
    if isempty(selected)
        error("PID tuning stage %s produced no candidate result.", stage.name);
    end
    state.searchCenter = selected.candidate;
    state.stageSummaries(stageIndex) = localStageSummary(stage, selected);
end

if isempty(state.bestPassing)
    warning("No candidate passed all final-stage validation targets.");
else
    fprintf("\nFinal PID: %s\n", ...
        pid_tuning_core.formatPidCandidate(state.bestPassing.candidate));
end
state.currentStage = "completed";
state.elapsedSeconds = toc(runTimer);
pid_tuning_core.writeBestResult(state, cfg);
pid_tuning_core.writeCurrentStatus("completed", state, finalCurrent, finalRecent, cfg);
result = state;
result.config = cfg;
result.pidBlockOriginal = currentPid;
result.finalCandidate = state.searchCenter;
end

function state = localInitialState(cfg, stages)
state = struct();
state.iteration = 0;
state.stageIteration = 0;
state.currentStage = "baseline";
state.stageIndex = 0;
state.stageCount = numel(stages);
state.best = [];
state.bestPassing = [];
state.history = [];
state.searchCenter = cfg.initialCandidate;
state.searchScale = cfg.search.initialScale;
state.startedAt = char(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"));
state.elapsedSeconds = 0;
state.testedCount = 0;
state.passedCount = 0;
state.failedCount = 0;
state.baseline = [];
summaryTemplate = struct("name", "", "role", "", "passed", false, ...
    "score", inf, "candidate", struct());
state.stageSummaries = repmat(summaryTemplate, numel(stages), 1);
end

function record = localEvaluateBaseline(cfg, state, runTimer)
candidate = cfg.initialCandidate;
candidate.source = "baseline";
simulation = pid_tuning_core.runCandidateBatch(candidate, cfg);
metrics = pid_tuning_core.evaluatePidRun(simulation(1), candidate, cfg);
validation = pid_tuning_core.validatePidMetrics(metrics, cfg);
record = localRecord(0, struct("name", "baseline", "role", "baseline"), ...
    0, 0, candidate, metrics, validation, 0);
state.elapsedSeconds = toc(runTimer); %#ok<NASGU>
end

function record = localEmptyRecord()
record = struct("iteration", 0, "stage", "", "stageRole", "", ...
    "stageIteration", 0, "candidateIndex", 0, "globalIndex", 0, ...
    "candidate", struct(), "metrics", struct(), "validation", struct(), ...
    "score", inf, "passed", false);
end

function record = localRecord(iteration, stage, stageIteration, candidateIndex, ...
        candidate, metrics, validation, globalIndex)
record = struct();
record.iteration = iteration;
record.stage = string(stage.name);
record.stageRole = string(stage.role);
record.stageIteration = stageIteration;
record.candidateIndex = candidateIndex;
record.globalIndex = globalIndex;
record.candidate = candidate;
record.metrics = metrics;
record.validation = validation;
record.score = validation.score;
record.passed = validation.passed;
end

function stageCfg = localStageConfig(cfg, stage, center)
stageCfg = cfg;
stageCfg.activePidIndices = stage.activePidIndices;
stageCfg.initialCandidate = center;
for index = 1:numel(stageCfg.pidBlocks)
    stageCfg.pidBlocks(index).initialPid = center.pids(index);
end
loops = pid_tuning_core.normalizeEvaluationLoops(cfg);
for index = 1:numel(loops)
    loops(index).enabled = ismember(index, stage.evaluationLoopIndices);
    loops(index).primary = false;
end
if stage.role == "inner"
    primaryIndex = find(lower(string({loops.role})) == "inner", 1);
elseif stage.role == "outer"
    primaryIndex = find(lower(string({loops.role})) == "outer", 1);
else
    primaryIndex = find([cfg.evaluationLoops.primary], 1);
end
if isempty(primaryIndex) || ~loops(primaryIndex).enabled
    primaryIndex = find([loops.enabled], 1);
end
loops(primaryIndex).primary = true;
stageCfg.evaluationLoops = loops;
if stage.jointRefine
    fraction = max(0.01, min(1, double(cfg.search.jointRefineFraction)));
    fields = ["Kp", "Ki", "Kd", "N"];
    for pidIndex = stage.activePidIndices
        for field = fields
            original = double(cfg.pidBlocks(pidIndex).bounds.(field));
            span = original(2) - original(1);
            value = double(center.pids(pidIndex).(field));
            stageCfg.pidBlocks(pidIndex).bounds.(field) = [ ...
                max(original(1), value - span * fraction), ...
                min(original(2), value + span * fraction)];
        end
    end
end
end

function selected = localSelectedRecord(state)
if ~isempty(state.bestPassing)
    selected = state.bestPassing;
else
    selected = state.best;
end
end

function summary = localStageSummary(stage, selected)
summary = struct("name", string(stage.name), "role", string(stage.role), ...
    "passed", logical(selected.passed), "score", double(selected.score), ...
    "candidate", selected.candidate);
end

function localPrintRunHeader(cfg, stages)
fprintf("Model: %s\n", cfg.modelName);
fprintf("Run ID: %s\n", cfg.logging.runId);
fprintf("Run dir: %s\n", cfg.logging.runDir);
fprintf("PID blocks: %d, stages: %d\n", numel(cfg.pidBlocks), numel(stages));
for index = 1:numel(cfg.pidBlocks)
    pid = cfg.initialCandidate.pids(index);
    fprintf("  %s: %s | Kp=%g, Ki=%g, Kd=%g, N=%g\n", ...
        pid.name, cfg.pidBlocks(index).path, pid.Kp, pid.Ki, pid.Kd, pid.N);
end
end

function localDisableFastRestart(modelName)
try
    if bdIsLoaded(modelName)
        set_param(modelName, "FastRestart", "off");
    end
catch
end
end