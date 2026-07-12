function candidate = normalizePidCandidate(candidate, cfg)
%NORMALIZEPIDCANDIDATE Convert legacy and multi-PID candidates to one shape.

if isfield(candidate, "pids") && ~isempty(candidate.pids)
    pids = candidate.pids(:);
else
    pids = struct("name", "pid1", ...
        "Kp", localGet(candidate, "Kp", localGet(candidate, "P", 0)), ...
        "Ki", localGet(candidate, "Ki", localGet(candidate, "I", 0)), ...
        "Kd", localGet(candidate, "Kd", localGet(candidate, "D", 0)), ...
        "N", localGet(candidate, "N", 100));
end

if ~isempty(cfg) && isfield(cfg, "pidBlocks")
    for idx = 1:numel(cfg.pidBlocks)
        if numel(pids) < idx
            pids(idx).name = string(cfg.pidBlocks(idx).name);
            pids(idx).Kp = cfg.pidBlocks(idx).initialPid.Kp;
            pids(idx).Ki = cfg.pidBlocks(idx).initialPid.Ki;
            pids(idx).Kd = cfg.pidBlocks(idx).initialPid.Kd;
            pids(idx).N = cfg.pidBlocks(idx).initialPid.N;
        end
        pids(idx).name = string(cfg.pidBlocks(idx).name);
    end
end

for idx = 1:numel(pids)
    if ~isfield(pids(idx), "name") || strlength(string(pids(idx).name)) == 0
        pids(idx).name = "pid" + idx;
    else
        pids(idx).name = string(pids(idx).name);
    end
    pids(idx).Kp = localGet(pids(idx), "Kp", localGet(pids(idx), "P", 0));
    pids(idx).Ki = localGet(pids(idx), "Ki", localGet(pids(idx), "I", 0));
    pids(idx).Kd = localGet(pids(idx), "Kd", localGet(pids(idx), "D", 0));
    pids(idx).N = localGet(pids(idx), "N", 100);
end

candidate = struct("pids", pids, "Kp", pids(1).Kp, "Ki", pids(1).Ki, ...
    "Kd", pids(1).Kd, "N", pids(1).N, ...
    "source", string(localGet(candidate, "source", "program")));
end

function value = localGet(source, field, fallback)
if isfield(source, field) && ~isempty(source.(field))
    value = source.(field);
else
    value = fallback;
end
end

