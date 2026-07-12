function writeCandidateHistory(record, state, cfg)
%WRITECANDIDATEHISTORY Append one candidate result to history.jsonl using UTF-8.

if ~isfield(cfg.logging, "saveRealtimeJson") || ~cfg.logging.saveRealtimeJson
    return;
end

entry = pid_tuning_core.recordToJsonStruct(record, state, cfg);
line = jsonencode(pid_tuning_core.jsonSafe(entry));

fid = fopen(cfg.logging.historyFile, "a", "n", "UTF-8");
if fid < 0
    warning("Could not open history log: %s", cfg.logging.historyFile);
    return;
end
fprintf(fid, "%s\n", line);
fclose(fid);
end
