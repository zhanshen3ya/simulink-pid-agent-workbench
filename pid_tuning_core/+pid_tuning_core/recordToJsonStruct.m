function value = recordToJsonStruct(record, state, cfg)
%RECORDTOJSONSTRUCT Convert a tuning record to a stable JSON-friendly struct.

candidate = pid_tuning_core.normalizePidCandidate(record.candidate, cfg);
metrics = record.metrics;
validation = record.validation;

value = struct();
value.timestamp = string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss"));
value.elapsedSeconds = localField(state, "elapsedSeconds", 0);
value.iteration = record.iteration;
value.candidateIndex = record.candidateIndex;
value.globalIndex = localField(record, "globalIndex", localField(state, "testedCount", []));
value.candidate = candidate;
value.metrics = metrics;
value.passed = validation.passed;
value.failures = validation.failures;
value.score = validation.score;
value.summary = string(pid_tuning_core.formatPidCandidate(candidate));
end

function value = localField(source, fieldName, fallback)
if isstruct(source) && isfield(source, fieldName)
    value = source.(fieldName);
else
    value = fallback;
end
end

