function [cfg, currentPid] = setupPidBlocks(cfg)
%SETUPPIDBLOCKS Normalize single-PID and multi-PID configuration.

load_system(cfg.modelName);

pidBlocks = localConfiguredBlocks(cfg);
if isempty(pidBlocks)
    discovered = pid_tuning_core.discoverPidBlocks(cfg.modelName);
    if isempty(discovered)
        error("No PID Controller block found in model %s.", cfg.modelName);
    end

    if isfield(cfg, "tuneAllDiscoveredPidBlocks") && cfg.tuneAllDiscoveredPidBlocks
        for idx = 1:numel(discovered)
            pidBlocks(idx).path = string(discovered{idx}); %#ok<AGROW>
        end
    else
        pidBlocks(1).path = string(discovered{1});
    end
end


if numel(pidBlocks) > 2
    error("PIDAgent:TooManyPidBlocks", ...
        "A single tuning task supports at most two PID blocks. Use the PID manager to create sequential tuning units.");
end

for idx = 1:numel(pidBlocks)
    if ~isfield(pidBlocks(idx), "path") || strlength(string(pidBlocks(idx).path)) == 0
        error("cfg.pidBlocks(%d).path is empty.", idx);
    end

    if ~isfield(pidBlocks(idx), "name") || strlength(string(pidBlocks(idx).name)) == 0
        pidBlocks(idx).name = "pid" + idx;
    else
        pidBlocks(idx).name = string(pidBlocks(idx).name);
    end

    pidBlocks(idx).path = string(pidBlocks(idx).path);

    currentPid(idx) = pid_tuning_core.readPidBlockParams(pidBlocks(idx).path); %#ok<AGROW>
    pidBlocks(idx).currentPid = currentPid(idx).numeric;
    pidBlocks(idx).initialPid = localInitialPid(cfg, idx, currentPid(idx).numeric);
    pidBlocks(idx).bounds = localBounds(cfg, pidBlocks, idx);
end

cfg.pidBlocks = pidBlocks;
cfg.pidBlockPaths = string({pidBlocks.path});
cfg.pidBlockPath = cfg.pidBlockPaths(1);
cfg.initialCandidate = localCandidateFromPidBlocks(pidBlocks);
end

function pidBlocks = localConfiguredBlocks(cfg)
pidBlocks = struct([]);

if isfield(cfg, "pidBlocks") && ~isempty(cfg.pidBlocks)
    input = cfg.pidBlocks;
    for idx = 1:numel(input)
        if isfield(input(idx), "path")
            pidBlocks(idx).path = string(input(idx).path); %#ok<AGROW>
        elseif isfield(input(idx), "blockPath")
            pidBlocks(idx).path = string(input(idx).blockPath); %#ok<AGROW>
        else
            error("cfg.pidBlocks(%d) must contain path or blockPath.", idx);
        end

        if isfield(input(idx), "name")
            pidBlocks(idx).name = string(input(idx).name);
        end
        if isfield(input(idx), "bounds")
            pidBlocks(idx).bounds = input(idx).bounds;
        end
        if isfield(input(idx), "initialPid")
            pidBlocks(idx).initialPid = input(idx).initialPid;
        end
    end
    return;
end

if isfield(cfg, "pidBlockPaths") && ~isempty(cfg.pidBlockPaths)
    paths = string(cfg.pidBlockPaths);
    for idx = 1:numel(paths)
        pidBlocks(idx).path = paths(idx); %#ok<AGROW>
    end
    return;
end

if isfield(cfg, "pidBlockPath") && strlength(string(cfg.pidBlockPath)) > 0
    pidBlocks(1).path = string(cfg.pidBlockPath);
end
end

function initialPid = localInitialPid(cfg, idx, fallback)
initialPid = fallback;

if isfield(cfg, "pidBlocks") && numel(cfg.pidBlocks) >= idx && ...
        isfield(cfg.pidBlocks(idx), "initialPid") && ~isempty(cfg.pidBlocks(idx).initialPid)
    initialPid = localMergePid(cfg.pidBlocks(idx).initialPid, fallback);
    return;
end

if isfield(cfg, "initialPids") && ~isempty(cfg.initialPids)
    if numel(cfg.initialPids) >= idx
        initialPid = localMergePid(cfg.initialPids(idx), fallback);
    end
    return;
end

if isfield(cfg, "initialPid") && ~isempty(cfg.initialPid)
    if isfield(cfg.initialPid, "pids") && numel(cfg.initialPid.pids) >= idx
        initialPid = localMergePid(cfg.initialPid.pids(idx), fallback);
    elseif idx == 1
        initialPid = localMergePid(cfg.initialPid, fallback);
    end
end
end

function bounds = localBounds(cfg, pidBlocks, idx)
if isfield(pidBlocks(idx), "bounds") && ~isempty(pidBlocks(idx).bounds)
    bounds = pidBlocks(idx).bounds;
elseif isfield(cfg, "bounds") && numel(cfg.bounds) >= idx
    bounds = cfg.bounds(idx);
else
    bounds = cfg.bounds(1);
end

bounds = localCompleteBounds(bounds);
end

function bounds = localCompleteBounds(bounds)
defaults.Kp = [0, 200];
defaults.Ki = [0, 200];
defaults.Kd = [0, 50];
defaults.N = [1, 1000];

fields = ["Kp", "Ki", "Kd", "N"];
for field = fields
    if ~isfield(bounds, field) || numel(bounds.(field)) ~= 2
        bounds.(field) = defaults.(field);
    end
end
end

function pid = localMergePid(source, fallback)
pid = fallback;
if isfield(source, "Kp")
    pid.Kp = source.Kp;
elseif isfield(source, "P")
    pid.Kp = source.P;
end
if isfield(source, "Ki")
    pid.Ki = source.Ki;
elseif isfield(source, "I")
    pid.Ki = source.I;
end
if isfield(source, "Kd")
    pid.Kd = source.Kd;
elseif isfield(source, "D")
    pid.Kd = source.D;
end
if isfield(source, "N")
    pid.N = source.N;
end
end

function candidate = localCandidateFromPidBlocks(pidBlocks)
pids = repmat(struct("name", "", "Kp", 0, "Ki", 0, "Kd", 0, "N", 100), numel(pidBlocks), 1);

for idx = 1:numel(pidBlocks)
    pids(idx).name = string(pidBlocks(idx).name);
    pids(idx).Kp = pidBlocks(idx).initialPid.Kp;
    pids(idx).Ki = pidBlocks(idx).initialPid.Ki;
    pids(idx).Kd = pidBlocks(idx).initialPid.Kd;
    pids(idx).N = pidBlocks(idx).initialPid.N;
end

candidate = struct("pids", pids, "Kp", pids(1).Kp, "Ki", pids(1).Ki, ...
    "Kd", pids(1).Kd, "N", pids(1).N);
end

