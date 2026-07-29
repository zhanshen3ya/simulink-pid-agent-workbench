function loops = normalizeEvaluationLoops(cfg)
%NORMALIZEEVALUATIONLOOPS Build complete per-loop evaluation definitions.

template = localTemplate();
if isfield(cfg, "evaluationLoops") && ~isempty(cfg.evaluationLoops)
    input = cfg.evaluationLoops;
else
    input = struct( ...
        "name", "primary", ...
        "role", "single", ...
        "pidPath", localPrimaryPidPath(cfg), ...
        "referenceSignalName", string(cfg.referenceSignalName), ...
        "outputSignalName", string(cfg.outputSignalName), ...
        "controlSignalName", string(cfg.controlSignalName), ...
        "currentSignalName", string(cfg.currentSignalName), ...
        "weight", 1, ...
        "enabled", true, ...
        "primary", true);
end

loops = repmat(template, numel(input), 1);
for index = 1:numel(input)
    item = input(index);
    loops(index) = localCopyKnownFields(template, item);
    if strlength(loops(index).name) == 0
        loops(index).name = "loop" + index;
    end
    if strlength(loops(index).role) == 0
        loops(index).role = "single";
    end
    loops(index).targets = localMergeStruct(cfg.targets, localStructField(item, "targets"));
    loops(index).metrics = localMergeStruct(cfg.metrics, localStructField(item, "metrics"));
    loops(index).pidIndex = localPidIndex(cfg, loops(index).pidPath, index);
end

enabled = [loops.enabled];
if ~any(enabled)
    error("At least one evaluation loop must be enabled.");
end
primaryCandidates = find(enabled & [loops.primary]);
if numel(primaryCandidates) > 1
    error("Only one enabled evaluation loop can be primary.");
end
primaryIndex = primaryCandidates(1:min(1, numel(primaryCandidates)));
if isempty(primaryIndex)
    primaryIndex = find(enabled, 1);
    loops(primaryIndex).primary = true;
end
for index = setdiff(1:numel(loops), primaryIndex)
    loops(index).primary = false;
end
end

function template = localTemplate()
template = struct( ...
    "name", "", ...
    "role", "single", ...
    "pidPath", "", ...
    "pidIndex", 0, ...
    "referenceSignalName", "", ...
    "outputSignalName", "", ...
    "controlSignalName", "", ...
    "currentSignalName", "", ...
    "weight", 1, ...
    "enabled", true, ...
    "primary", false, ...
    "targets", struct(), ...
    "metrics", struct());
end

function output = localCopyKnownFields(output, input)
stringFields = ["name", "role", "pidPath", "referenceSignalName", ...
    "outputSignalName", "controlSignalName", "currentSignalName"];
for field = stringFields
    if isfield(input, field)
        output.(field) = string(input.(field));
    end
end
if isfield(input, "weight")
    value = double(input.weight);
    if isscalar(value) && isfinite(value) && value > 0
        output.weight = value;
    end
end
for field = ["enabled", "primary"]
    if isfield(input, field)
        output.(field) = logical(input.(field));
    end
end
end

function result = localMergeStruct(base, override)
result = base;
if ~isstruct(override) || isempty(override)
    return;
end
fields = fieldnames(override);
for index = 1:numel(fields)
    result.(fields{index}) = override.(fields{index});
end
end

function value = localStructField(source, name)
value = struct();
if isstruct(source) && isfield(source, name) && isstruct(source.(name))
    value = source.(name);
end
end

function path = localPrimaryPidPath(cfg)
path = "";
if isfield(cfg, "pidBlocks") && ~isempty(cfg.pidBlocks) && isfield(cfg.pidBlocks(1), "path")
    path = string(cfg.pidBlocks(1).path);
end
end

function index = localPidIndex(cfg, path, fallback)
index = 0;
if strlength(path) > 0 && isfield(cfg, "pidBlocks") && ~isempty(cfg.pidBlocks)
    paths = string({cfg.pidBlocks.path});
    match = find(paths == path, 1);
    if isempty(match)
        error("Evaluation loop PID path is not one of the selected PID blocks: %s", path);
    end
    index = match;
end
if index == 0 && fallback <= numel(cfg.pidBlocks)
    index = fallback;
end
end