function writeBestResult(state, cfg)
%WRITEBESTRESULT Persist the current best result.

if ~isfield(cfg.logging, "saveRealtimeJson") || ~cfg.logging.saveRealtimeJson
    return;
end

payload = struct();
payload.jobId = string(cfg.logging.runId);
payload.updatedAt = string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"));

if ~isempty(state.bestPassing)
    payload.kind = "bestPassing";
    payload.result = pid_tuning_core.recordToJsonStruct(state.bestPassing, state, cfg);
elseif ~isempty(state.best)
    payload.kind = "bestScored";
    payload.result = pid_tuning_core.recordToJsonStruct(state.best, state, cfg);
else
    payload.kind = "none";
    payload.result = [];
end

pid_tuning_core.writeJsonFile(cfg.logging.bestResultFile, payload);
end

