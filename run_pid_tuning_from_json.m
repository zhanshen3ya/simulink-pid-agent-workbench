function result = run_pid_tuning_from_json(configFile)
%RUN_PID_TUNING_FROM_JSON Start a PID tuning run from a validated JSON file.

raw = jsondecode(fileread(configFile));
required = ["modelPath", "pidBlocks", "runId"];
for field = required
    if ~isfield(raw, field)
        error("Missing required configuration field: %s", field);
    end
end
if isempty(raw.pidBlocks)
    error("At least one PID block must be selected.");
end

rootDir = fileparts(mfilename("fullpath"));
addpath(genpath(rootDir));

modelPath = string(raw.modelPath);
[modelName, ~, modelDir] = pid_tuning_core.resolveSimulinkModel(modelPath);
if strlength(modelDir) > 0
    addpath(modelDir);
    cd(modelDir);
end

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = string(modelName);
cfg.pidBlocks = localPidBlocks(raw.pidBlocks);
cfg.logging.outputDir = fullfile(rootDir, "pid_tuning_runs");
cfg.logging.runId = string(raw.runId);

cfg = localAssignString(cfg, raw, "stopTime");
cfg = localAssignString(cfg, raw, "referenceSignalName");
cfg = localAssignString(cfg, raw, "outputSignalName");
cfg = localAssignString(cfg, raw, "controlSignalName");
cfg = localAssignString(cfg, raw, "currentSignalName");
cfg = localAssignNumber(cfg, raw, "randomSeed");
cfg = localAssignNumber(cfg, raw, "maxIterations");
cfg = localAssignNumber(cfg, raw, "numCandidates");
cfg = localAssignLogical(cfg, raw, "stopOnFirstPass");
cfg = localAssignLogical(cfg, raw, "useParallel");
cfg = localAssignAi(cfg, raw);

if isfield(raw, "targets") && isstruct(raw.targets)
    targetFields = ["overshootPctMax", "settlingTimeMax", ...
        "steadyStateErrorAbsMax", "iaeMax", "iseMax", "itaeMax", ...
        "maxAbsControlMax", "controlEnergyMax", "maxAbsCurrentMax", ...
        "outputRippleMax", "controlSaturationFractionMax"];
    for field = targetFields
        if isfield(raw.targets, field)
            cfg.targets.(field) = double(raw.targets.(field));
        end
    end
end

if isfield(raw, "controlUpperLimit")
    value = double(raw.controlUpperLimit);
    if ~isscalar(value) || ~isfinite(value) || value <= 0
        error("controlUpperLimit must be a positive finite scalar.");
    end
    cfg.metrics.controlUpperLimit = value;
end

result = main_pid_search(cfg);
end

function blocks = localPidBlocks(input)
template = struct("name", "", "path", "", "bounds", struct());
blocks = repmat(template, numel(input), 1);
boundFields = ["Kp", "Ki", "Kd", "N"];
for idx = 1:numel(input)
    item = input(idx);
    if ~isfield(item, "path") || strlength(string(item.path)) == 0
        error("pidBlocks(%d).path is required.", idx);
    end
    blocks(idx).path = string(item.path);
    if isfield(item, "name") && strlength(string(item.name)) > 0
        blocks(idx).name = string(item.name);
    else
        blocks(idx).name = "pid" + idx;
    end
    if isfield(item, "bounds") && isstruct(item.bounds)
        for field = boundFields
            if isfield(item.bounds, field)
                bounds = double(item.bounds.(field));
                if numel(bounds) ~= 2 || any(~isfinite(bounds)) || bounds(1) > bounds(2)
                    error("pidBlocks(%d).bounds.%s must be [min, max].", idx, field);
                end
                blocks(idx).bounds.(field) = reshape(bounds, 1, 2);
            end
        end
    end
end
end

function cfg = localAssignString(cfg, raw, field)
if isfield(raw, field) && strlength(string(raw.(field))) > 0
    cfg.(field) = string(raw.(field));
end
end

function cfg = localAssignNumber(cfg, raw, field)
if isfield(raw, field)
    value = double(raw.(field));
    if ~isscalar(value) || ~isfinite(value)
        error("%s must be a finite scalar.", field);
    end
    cfg.(field) = value;
end
end

function cfg = localAssignLogical(cfg, raw, field)
if isfield(raw, field)
    cfg.(field) = logical(raw.(field));
end
end
function cfg = localAssignAi(cfg, raw)
if ~isfield(raw, "ai") || ~isstruct(raw.ai)
    return;
end

ai = raw.ai;
if isfield(ai, "mode")
    cfg.ai.mode = lower(string(ai.mode));
end
if isfield(ai, "sourceLabel")
    cfg.ai.sourceLabel = string(ai.sourceLabel);
end
cfg.ai.enabled = cfg.ai.mode ~= "none";
if isfield(ai, "candidatesPerIteration")
    cfg.ai.candidatesPerIteration = max(0, floor(double(ai.candidatesPerIteration)));
end
if isfield(ai, "maxHistoryRecords")
    cfg.ai.maxHistoryRecords = max(0, floor(double(ai.maxHistoryRecords)));
end
if isfield(ai, "failOnError")
    cfg.ai.failOnError = logical(ai.failOnError);
end

if isfield(ai, "api") && isstruct(ai.api)
    apiFields = ["baseUrl", "model"];
    for field = apiFields
        if isfield(ai.api, field)
            cfg.ai.api.(field) = string(ai.api.(field));
        end
    end
    numericFields = ["temperature", "maxTokens", "timeoutSeconds"];
    for field = numericFields
        if isfield(ai.api, field)
            cfg.ai.api.(field) = double(ai.api.(field));
        end
    end
end

if isfield(ai, "local") && isstruct(ai.local)
    stringFields = ["pythonExe", "scriptPath"];
    for field = stringFields
        if isfield(ai.local, field)
            cfg.ai.local.(field) = string(ai.local.(field));
        end
    end
    if isfield(ai.local, "timeoutSeconds")
        cfg.ai.local.timeoutSeconds = double(ai.local.timeoutSeconds);
    end
end
end