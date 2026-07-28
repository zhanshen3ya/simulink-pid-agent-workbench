function info = inspectPidModel(modelFile)
%INSPECTPIDMODEL Inspect a Simulink model for tunable PID blocks and logged signals.

[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(modelFile);
load_system(resolvedPath);

blocks = localFindAllVariants(modelName, "Type", "Block");

emptyPid = struct("name", "", "path", "", "blockType", "", ...
    "maskType", "", "referenceBlock", "", "currentPid", ...
    struct("Kp", 0, "Ki", 0, "Kd", 0, "N", 100), ...
    "signalSuggestion", localEmptySignalSuggestion());
pidBlocks = repmat(emptyPid, 0, 1);

loggedSignals = localLoggedSignals(modelName);
for idx = 1:numel(blocks)
    blockPath = blocks{idx};
    blockType = string(localGetParam(blockPath, "BlockType"));
    maskType = string(localGetParam(blockPath, "MaskType"));
    referenceBlock = string(localGetParam(blockPath, "ReferenceBlock"));
    dialogParams = localGetDialogParams(blockPath);

    descriptor = lower(blockType + " " + maskType + " " + referenceBlock);
    hasPidName = contains(descriptor, "pid");
    hasPidParams = isfield(dialogParams, "P") && isfield(dialogParams, "I") && ...
        isfield(dialogParams, "D");
    if ~(hasPidName && hasPidParams)
        continue;
    end

    params = pid_tuning_core.readPidBlockParams(blockPath);
    item = emptyPid;
    item.name = string(localGetParam(blockPath, "Name"));
    item.path = string(blockPath);
    item.blockType = blockType;
    item.maskType = maskType;
    item.referenceBlock = referenceBlock;
    item.currentPid = params.numeric;
    item.signalSuggestion = localSuggestSignals(blockPath, loggedSignals);
    pidBlocks(end + 1, 1) = item; %#ok<AGROW>
end

info = struct();
info.modelName = string(modelName);
info.modelPath = string(resolvedPath);
info.pidBlocks = pidBlocks;
info.loggedSignals = loggedSignals;
info.pidCount = numel(pidBlocks);
end

function suggestion = localEmptySignalSuggestion()
suggestion = struct( ...
    "referenceSignalName", "", ...
    "outputSignalName", "", ...
    "controlSignalName", "", ...
    "currentSignalName", "", ...
    "complete", false, ...
    "allLogged", false, ...
    "confidence", 0, ...
    "notes", strings(0, 1));
end

function suggestion = localSuggestSignals(blockPath, loggedSignals)
suggestion = localEmptySignalSuggestion();
notes = strings(0, 1);

try
    handles = get_param(blockPath, "PortHandles");
catch
    suggestion.notes = "PID 端口不可读取。";
    return;
end

if isfield(handles, "Inport") && ~isempty(handles.Inport)
    inputLine = localPortLine(handles.Inport(1));
    sourceBlock = localSourceBlock(inputLine);
    sourceType = lower(string(localGetParam(sourceBlock, "BlockType")));
    if ismember(sourceType, ["sum", "add"])
        [referenceName, measurementName] = localResolveSumInputs(sourceBlock);
        suggestion.referenceSignalName = referenceName;
        suggestion.outputSignalName = measurementName;
        if strlength(referenceName) > 0 && strlength(measurementName) > 0
            notes(end + 1, 1) = "由 PID 输入端前的误差求和块正负端识别。";
        else
            notes(end + 1, 1) = "误差求和块存在未命名的输入信号。";
        end
    else
        notes(end + 1, 1) = "PID 输入端未直接连接标准 Sum/Add 误差块。";
    end
end

if isfield(handles, "Outport") && ~isempty(handles.Outport)
    suggestion.controlSignalName = localLineName(localPortLine(handles.Outport(1)));
end

measurement = lower(suggestion.outputSignalName);
currentWords = ["current", "iref", "i_ref", "il", "i_l", "id", "iq", "ibat"];
if any(contains(measurement, currentWords)) || ...
        (strlength(measurement) > 0 && startsWith(measurement, "i"))
    suggestion.currentSignalName = suggestion.outputSignalName;
end

required = [suggestion.referenceSignalName, suggestion.outputSignalName, ...
    suggestion.controlSignalName];
suggestion.complete = all(strlength(required) > 0);
suggestion.allLogged = suggestion.complete && all(ismember(required, loggedSignals));
named = required(strlength(required) > 0);
suggestion.confidence = (sum(strlength(required) > 0) + ...
    sum(ismember(named, loggedSignals))) / 6;
if suggestion.complete && ~suggestion.allLogged
    notes(end + 1, 1) = "建议信号中存在尚未启用记录的信号。";
end
suggestion.notes = notes;
end

function [referenceName, measurementName] = localResolveSumInputs(sumBlock)
referenceName = "";
measurementName = "";
try
    handles = get_param(sumBlock, "PortHandles");
    inputHandles = handles.Inport;
catch
    return;
end
signs = regexprep(string(localGetParam(sumBlock, "Inputs")), "[^+-]", "");
for index = 1:numel(inputHandles)
    name = localLineName(localPortLine(inputHandles(index)));
    if strlength(name) == 0
        continue;
    end
    sign = "+";
    if strlength(signs) >= index
        sign = extractBetween(signs, index, index);
    end
    if sign == "+" && strlength(referenceName) == 0
        referenceName = name;
    elseif sign == "-" && strlength(measurementName) == 0
        measurementName = name;
    end
end
end

function lineHandle = localPortLine(portHandle)
lineHandle = -1;
try
    lineHandle = get_param(portHandle, "Line");
catch
end
if isempty(lineHandle)
    lineHandle = -1;
end
end

function blockPath = localSourceBlock(lineHandle)
blockPath = "";
if isequal(lineHandle, -1)
    return;
end
try
    sourcePort = get_param(lineHandle, "SrcPortHandle");
    if ~isempty(sourcePort) && sourcePort ~= -1
        blockPath = string(get_param(sourcePort, "Parent"));
    end
catch
end
end

function name = localLineName(lineHandle)
name = "";
if isequal(lineHandle, -1)
    return;
end
sourcePort = -1;
try
    name = string(get_param(lineHandle, "Name"));
    sourcePort = get_param(lineHandle, "SrcPortHandle");
catch
end
if strlength(name) > 0 || isempty(sourcePort) || sourcePort == -1
    return;
end

try
    rootLine = get_param(sourcePort, "Line");
    name = string(get_param(rootLine, "Name"));
catch
end
if strlength(name) > 0
    return;
end

try
    sourceBlock = string(get_param(sourcePort, "Parent"));
    modelName = string(bdroot(char(sourceBlock)));
    workspaceBlocks = localFindAllVariants(modelName, "BlockType", "ToWorkspace");
    for index = 1:numel(workspaceBlocks)
        handles = get_param(workspaceBlocks{index}, "PortHandles");
        if isempty(handles.Inport)
            continue;
        end
        workspaceLine = get_param(handles.Inport(1), "Line");
        if workspaceLine == -1
            continue;
        end
        workspaceSource = get_param(workspaceLine, "SrcPortHandle");
        if workspaceSource == sourcePort
            name = string(get_param(workspaceBlocks{index}, "VariableName"));
            return;
        end
    end
catch
end
end

function value = localGetParam(blockPath, parameter)
value = "";
if strlength(string(blockPath)) == 0
    return;
end
try
    value = get_param(blockPath, char(parameter));
catch
end
end

function params = localGetDialogParams(blockPath)
params = struct();
try
    params = get_param(blockPath, "DialogParameters");
catch
end
if isempty(params)
    params = struct();
end
end

function names = localLoggedSignals(modelName)
names = strings(0, 1);
lineHandles = localFindAllVariants(modelName, "FindAll", "on", "Type", "line");
for idx = 1:numel(lineHandles)
    try
        if ~strcmpi(get_param(lineHandles(idx), "DataLogging"), "on")
            continue;
        end
        signalName = string(get_param(lineHandles(idx), "Name"));
        if strlength(signalName) > 0
            names(end + 1, 1) = signalName; %#ok<AGROW>
        end
    catch
    end
end
workspaceBlocks = localFindAllVariants(modelName, "BlockType", "ToWorkspace");
for idx = 1:numel(workspaceBlocks)
    try
        variableName = string(get_param(workspaceBlocks{idx}, "VariableName"));
        if strlength(variableName) > 0
            names(end + 1, 1) = variableName; %#ok<AGROW>
        end
    catch
    end
end
names = unique(names, "stable");
end
function matches = localFindAllVariants(modelName, varargin)
commonArguments = {"LookUnderMasks", "all", "FollowLinks", "on"};
try
    matches = find_system(modelName, commonArguments{:}, ...
        "MatchFilter", @Simulink.match.allVariants, varargin{:});
catch
    matches = find_system(modelName, commonArguments{:}, varargin{:});
end
end
