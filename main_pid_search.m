function result = main_pid_search(cfg)
%MAIN_PID_SEARCH Run closed-loop PID candidate generation and Simulink validation.

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
fastRestartCleanup = onCleanup(@() localDisableFastRestart(cfg.modelName));

[cfg, currentPid] = pid_tuning_core.setupPidBlocks(cfg);
cfg = pid_tuning_core.prepareRunLogging(cfg);
runTimer = tic;

state = struct();
state.iteration = 0;
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

pid_tuning_core.writeCurrentStatus("running", state, [], [], cfg);

fprintf("Model: %s\n", cfg.modelName);
fprintf("Run ID: %s\n", cfg.logging.runId);
fprintf("Run dir: %s\n", cfg.logging.runDir);
fprintf("PID blocks: %d\n", numel(cfg.pidBlocks));
for idx = 1:numel(cfg.pidBlocks)
    p = cfg.initialCandidate.pids(idx);
    fprintf("  %s: %s | Kp=%g, Ki=%g, Kd=%g, N=%g\n", ...
        p.name, cfg.pidBlocks(idx).path, p.Kp, p.Ki, p.Kd, p.N);
end

for iteration = 1:cfg.maxIterations
    state.iteration = iteration;
    candidates = pid_tuning_core.generatePidCandidates(state, cfg, cfg.numCandidates);

    fprintf("\nIteration %d/%d: testing %d candidates...\n", ...
        iteration, cfg.maxIterations, numel(candidates));

records = repmat(struct(), 1, numel(candidates));
    simResults = pid_tuning_core.runCandidateBatch(candidates, cfg);
    for idx = 1:numel(candidates)
        metrics = pid_tuning_core.evaluatePidRun(simResults(idx), candidates(idx), cfg);
        validation = pid_tuning_core.validatePidMetrics(metrics, cfg);

        records(idx).iteration = iteration;
        records(idx).candidateIndex = idx;
        records(idx).candidate = candidates(idx);
        records(idx).metrics = metrics;
        records(idx).validation = validation;
        records(idx).score = validation.score;
        records(idx).passed = validation.passed;

        state.testedCount = state.testedCount + 1;
        records(idx).globalIndex = state.testedCount;
        if validation.passed
            state.passedCount = state.passedCount + 1;
        else
            state.failedCount = state.failedCount + 1;
        end
        state.elapsedSeconds = toc(runTimer);

        pid_tuning_core.writeCandidateHistory(records(idx), state, cfg);
        pid_tuning_core.writeCurrentStatus("running", state, records(idx), records(1:idx), cfg);
    end

    state = pid_tuning_core.updatePidSearchState(state, records, cfg);
    state.elapsedSeconds = toc(runTimer);
    pid_tuning_core.saveIterationLog(records, state, cfg);
    pid_tuning_core.writeBestResult(state, cfg);
    pid_tuning_core.writeCurrentStatus("running", state, records(end), records, cfg);

    fprintf("Best score this iteration: %.6g\n", min([records.score]));
    if ~isempty(state.bestPassing)
        fprintf("Best passing PID: %s, score=%.6g\n", ...
            pid_tuning_core.formatPidCandidate(state.bestPassing.candidate), ...
            state.bestPassing.score);

        if cfg.stopOnFirstPass
            fprintf("Stopping because cfg.stopOnFirstPass is true.\n");
            break;
        end
    end
end

result = state;
result.config = cfg;
result.pidBlockOriginal = currentPid;

if isempty(state.bestPassing)
    warning("No candidate passed all validation targets. Returning best scored candidate.");
else
    fprintf("\nFinal PID: %s\n", ...
        pid_tuning_core.formatPidCandidate(state.bestPassing.candidate));
end

state.elapsedSeconds = toc(runTimer);
pid_tuning_core.writeBestResult(state, cfg);
finalCurrent = [];
finalRecent = [];
if exist("records", "var") && ~isempty(records)
    finalCurrent = records(end);
    finalRecent = records;
end
pid_tuning_core.writeCurrentStatus("completed", state, finalCurrent, finalRecent, cfg);
end




function localDisableFastRestart(modelName)
try
    if bdIsLoaded(modelName)
        set_param(modelName, "FastRestart", "off");
    end
catch
end
end