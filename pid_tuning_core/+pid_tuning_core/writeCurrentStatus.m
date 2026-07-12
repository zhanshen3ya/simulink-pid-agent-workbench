function writeCurrentStatus(status, state, currentRecord, recentRecords, cfg)
%WRITECURRENTSTATUS Write current_status.json for front-end polling.

if ~isfield(cfg.logging, "saveRealtimeJson") || ~cfg.logging.saveRealtimeJson
    return;
end

payload = struct();
payload.jobId = string(cfg.logging.runId);
payload.status = string(status);
payload.modelName = string(cfg.modelName);
payload.startedAt = string(state.startedAt);
payload.updatedAt = string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"));
payload.elapsedSeconds = localField(state, "elapsedSeconds", 0);
payload.currentIteration = localField(state, "iteration", 0);
payload.maxIterations = cfg.maxIterations;
payload.numCandidatesPerIteration = cfg.numCandidates;
payload.testedCount = localField(state, "testedCount", 0);
payload.passedCount = localField(state, "passedCount", 0);
payload.failedCount = localField(state, "failedCount", 0);
payload.runDir = string(cfg.logging.runDir);
payload.aiEnabled = logical(cfg.ai.enabled);
payload.aiMode = string(cfg.ai.mode);

if ~isempty(currentRecord)
    payload.current = pid_tuning_core.recordToJsonStruct(currentRecord, state, cfg);
else
    payload.current = [];
end

if ~isempty(state.best)
    payload.best = pid_tuning_core.recordToJsonStruct(state.best, state, cfg);
else
    payload.best = [];
end

if ~isempty(state.bestPassing)
    payload.bestPassing = pid_tuning_core.recordToJsonStruct(state.bestPassing, state, cfg);
else
    payload.bestPassing = [];
end

payload.recent = [];
if ~isempty(recentRecords)
    count = min(10, numel(recentRecords));
    startIdx = numel(recentRecords) - count + 1;
    recent = recentRecords(startIdx:end);
    payload.recent = arrayfun(@(r) pid_tuning_core.recordToJsonStruct(r, state, cfg), recent);
end

pid_tuning_core.writeJsonFile(cfg.logging.currentStatusFile, payload);
end

function value = localField(source, fieldName, fallback)
if isstruct(source) && isfield(source, fieldName)
    value = source.(fieldName);
else
    value = fallback;
end
end

