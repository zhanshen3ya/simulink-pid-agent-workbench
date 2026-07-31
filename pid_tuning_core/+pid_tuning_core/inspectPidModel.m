function info = inspectPidModel(modelFile)
%INSPECTPIDMODEL Inspect a Simulink model for tunable PID blocks and logged signals.

[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(modelFile);
load_system(resolvedPath);

blocks = localFindAllVariants(modelName, "Type", "Block");

emptyPid = struct("name", "", "path", "", "blockType", "", ...
    "maskType", "", "referenceBlock", "", "currentPid", ...
    struct("Kp", 0, "Ki", 0, "Kd", 0, "N", 100), ...
    "signalSuggestion", localEmptySignalSuggestion(), ...
    "suggestedRole", "", "tuningOrder", NaN, "cascadePartnerPath", "", ...
    "cascadeConnectionKind", "", "cascadeTransformBlocks", strings(0, 1));
pidBlocks = repmat(emptyPid, 0, 1);

[loggedSignals, signalCatalog, duplicateSignalNames] = localLoggedSignals(modelName);
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

[pidBlocks, cascadePairs] = localAnnotateCascade(pidBlocks);

info = struct();
info.modelName = string(modelName);
info.modelPath = string(resolvedPath);
info.pidBlocks = pidBlocks;
info.loggedSignals = loggedSignals;
info.loggedSignalCatalog = signalCatalog;
info.duplicateLoggedSignalNames = duplicateSignalNames;
info.pidCount = numel(pidBlocks);
info.cascadePairs = cascadePairs;
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

function [referenceName, measurementName, referenceSourcePort, measurementSourcePort] = localResolveSumInputs(sumBlock)
referenceName = "";
measurementName = "";
referenceSourcePort = -1;
measurementSourcePort = -1;
try
    handles = get_param(sumBlock, "PortHandles");
    inputHandles = handles.Inport;
catch
    return;
end
signs = regexprep(string(localGetParam(sumBlock, "Inputs")), "[^+-]", "");
for index = 1:numel(inputHandles)
    lineHandle = localPortLine(inputHandles(index));
    name = localLineName(lineHandle);
    sourcePort = -1;
    if ~isequal(lineHandle, -1)
        try
            sourcePort = get_param(lineHandle, "SrcPortHandle");
        catch
        end
    end
    sign = "+";
    if strlength(signs) >= index
        sign = extractBetween(signs, index, index);
    end
    if sign == "+"
        if referenceSourcePort == -1
            referenceSourcePort = sourcePort;
        end
        if strlength(referenceName) == 0 && strlength(name) > 0
            referenceName = name;
        end
    elseif sign == "-"
        if measurementSourcePort == -1
            measurementSourcePort = sourcePort;
        end
        if strlength(measurementName) == 0 && strlength(name) > 0
            measurementName = name;
        end
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
if strlength(name) == 0
    name = localDownstreamLoggedName(lineHandle);
end
end

function name = localDownstreamLoggedName(lineHandle)
name = "";
transparentTypes = ["saturate", "saturation", "deadzone", "ratetransition", ...
    "datatypeconversion", "signalconversion"];
try
    destinationPorts = get_param(lineHandle, "DstPortHandle");
catch
    return;
end
for portIndex = 1:numel(destinationPorts)
    try
        destinationBlock = string(get_param(destinationPorts(portIndex), "Parent"));
        blockType = lower(string(get_param(destinationBlock, "BlockType")));
        if ~any(blockType == transparentTypes)
            continue;
        end
        handles = get_param(destinationBlock, "PortHandles");
        for outputIndex = 1:numel(handles.Outport)
            outputLine = get_param(handles.Outport(outputIndex), "Line");
            if isnumeric(outputLine) && outputLine > 0
                name = localLineName(outputLine);
                if strlength(name) > 0
                    return;
                end
            end
        end
    catch
    end
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

function [blocks, pairs] = localAnnotateCascade(blocks)
pairTemplate = struct("outerPath", "", "innerPath", "", ...
    "confidence", 0, "evidence", "", "connectionKind", "", ...
    "transformBlocks", strings(0, 1), "outerControlSignalName", "", ...
    "innerReferenceSignalName", "");
pairs = repmat(pairTemplate, 0, 1);
for outerIndex = 1:numel(blocks)
    for innerIndex = 1:numel(blocks)
        if outerIndex == innerIndex
            continue;
        end
        [connected, connectionKind, transformBlocks] = localCascadeConnection( ...
            blocks(outerIndex).path, blocks(innerIndex).path);
        if ~connected
            continue;
        end
        outerControl = string(blocks(outerIndex).signalSuggestion.controlSignalName);
        innerReference = string(blocks(innerIndex).signalSuggestion.referenceSignalName);
        blocks(outerIndex).suggestedRole = "outer";
        blocks(outerIndex).tuningOrder = 2;
        blocks(outerIndex).cascadePartnerPath = blocks(innerIndex).path;
        blocks(outerIndex).cascadeConnectionKind = connectionKind;
        blocks(outerIndex).cascadeTransformBlocks = transformBlocks;
        blocks(innerIndex).suggestedRole = "inner";
        blocks(innerIndex).tuningOrder = 1;
        blocks(innerIndex).cascadePartnerPath = blocks(outerIndex).path;
        blocks(innerIndex).cascadeConnectionKind = connectionKind;
        blocks(innerIndex).cascadeTransformBlocks = transformBlocks;
        pair = pairTemplate;
        pair.outerPath = blocks(outerIndex).path;
        pair.innerPath = blocks(innerIndex).path;
        pair.connectionKind = connectionKind;
        pair.transformBlocks = transformBlocks;
        pair.outerControlSignalName = outerControl;
        pair.innerReferenceSignalName = innerReference;
        signalConfidence = min(blocks(outerIndex).signalSuggestion.confidence, ...
            blocks(innerIndex).signalSuggestion.confidence);
        if connectionKind == "direct"
            pair.confidence = max(0.9, signalConfidence);
            pair.evidence = "Outer PID output directly feeds the inner PID reference.";
        else
            pair.confidence = max(0.8, signalConfidence);
            pair.evidence = "Outer PID output reaches the inner PID reference through: " + ...
                strjoin(localBlockNames(transformBlocks), " -> ");
        end
        pairs(end + 1, 1) = pair; %#ok<AGROW>
    end
end
% Block-name evidence is only a fallback and never overwrites topology evidence.
for index = 1:numel(blocks)
    if strlength(string(blocks(index).suggestedRole)) > 0
        continue;
    end
    [role, order] = localRoleFromPath(blocks(index).name, blocks(index).path);
    blocks(index).suggestedRole = role;
    blocks(index).tuningOrder = order;
end
end

function [connected, connectionKind, transformBlocks] = localCascadeConnection(outerPath, innerPath)
connected = false;
connectionKind = "";
transformBlocks = strings(0, 1);
outerPort = -1;
referencePort = localReferenceSourcePort(innerPath);
try
    handles = get_param(outerPath, "PortHandles");
    if ~isempty(handles.Outport)
        outerPort = handles.Outport(1);
    end
catch
end
if outerPort == -1 || referencePort == -1
    return;
end
[connected, transformBlocks] = localTraceSourcePort( ...
    outerPort, referencePort, 0, zeros(0, 1));
if connected
    if isempty(transformBlocks)
        connectionKind = "direct";
    else
        connectionKind = "transformed";
    end
end
end

function sourcePort = localReferenceSourcePort(pidPath)
sourcePort = -1;
try
    handles = get_param(pidPath, "PortHandles");
    if isempty(handles.Inport)
        return;
    end
    inputLine = localPortLine(handles.Inport(1));
    sumBlock = localSourceBlock(inputLine);
    blockType = lower(string(localGetParam(sumBlock, "BlockType")));
    if ~ismember(blockType, ["sum", "add"])
        return;
    end
    [~, ~, sourcePort] = localResolveSumInputs(sumBlock);
catch
end
end

function [connected, transformBlocks] = localTraceSourcePort(currentPort, targetPort, depth, visitedPorts)
connected = false;
transformBlocks = strings(0, 1);
if currentPort == targetPort
    connected = true;
    return;
end
if depth >= 8 || any(visitedPorts == currentPort)
    return;
end
visitedPorts(end + 1, 1) = currentPort;
lineHandle = -1;
try
    lineHandle = get_param(currentPort, "Line");
catch
end
if isempty(lineHandle) || lineHandle == -1
    return;
end
try
    destinationPorts = get_param(lineHandle, "DstPortHandle");
catch
    return;
end
for index = 1:numel(destinationPorts)
    try
        destinationBlock = string(get_param(destinationPorts(index), "Parent"));
        nextPorts = localTransformOutputPorts(destinationBlock);
    catch
        continue;
    end
    for portIndex = 1:numel(nextPorts)
        [found, tail] = localTraceSourcePort( ...
            nextPorts(portIndex), targetPort, depth + 1, visitedPorts);
        if found
            connected = true;
            transformBlocks = [destinationBlock; tail(:)];
            return;
        end
    end
end
end

function outputPorts = localTransformOutputPorts(blockPath)
outputPorts = zeros(0, 1);
blockType = regexprep(lower(string(localGetParam(blockPath, "BlockType"))), "[^a-z0-9]", "");
allowed = ["gain", "product", "sum", "add", "saturate", "saturation", "deadzone", ...
    "ratetransition", "datatypeconversion", "signalconversion", "switch", ...
    "minmax", "math", "trigonometry", "bias", "unaryminus", "abs", ...
    "lookupnddirect"];
if blockType == "goto"
    outputPorts = localFromOutputPorts(blockPath);
    return;
end
if ~any(blockType == allowed)
    return;
end
try
    handles = get_param(blockPath, "PortHandles");
    outputPorts = handles.Outport(:);
catch
end
end

function outputPorts = localFromOutputPorts(gotoBlock)
outputPorts = zeros(0, 1);
tag = string(localGetParam(gotoBlock, "GotoTag"));
if strlength(tag) == 0
    return;
end
modelName = string(bdroot(char(gotoBlock)));
fromBlocks = localFindAllVariants(modelName, "BlockType", "From");
for index = 1:numel(fromBlocks)
    if string(localGetParam(fromBlocks{index}, "GotoTag")) ~= tag
        continue;
    end
    try
        handles = get_param(fromBlocks{index}, "PortHandles");
        outputPorts = [outputPorts; handles.Outport(:)]; %#ok<AGROW>
    catch
    end
end
end

function names = localBlockNames(paths)
names = strings(size(paths));
for index = 1:numel(paths)
    names(index) = string(localGetParam(paths(index), "Name"));
    if strlength(names(index)) == 0
        names(index) = paths(index);
    end
end
end
function [role, order] = localRoleFromPath(blockName, blockPath)
role = "";
order = NaN;
segments = flip(split(string(blockPath), "/"));
if strlength(string(blockName)) > 0
    segments = [string(blockName); segments(:)];
end
for index = 1:numel(segments)
    role = localRoleFromDescriptor(segments(index));
    if role == "inner"
        order = 1;
        return;
    elseif role == "outer"
        order = 2;
        return;
    end
end
end

function role = localRoleFromDescriptor(value)
descriptor = lower(string(value));
explicitInner = any(contains(descriptor, ["inner", "内环"]));
explicitOuter = any(contains(descriptor, ["outer", "外环"]));
if explicitInner ~= explicitOuter
    if explicitInner
        role = "inner";
    else
        role = "outer";
    end
    return;
end
innerDomain = any(contains(descriptor, ["current", "torque", "电流", "转矩"]));
outerDomain = any(contains(descriptor, ["voltage", "position", "speed", ...
    "电压", "位置", "速度"]));
if innerDomain ~= outerDomain
    if innerDomain
        role = "inner";
    else
        role = "outer";
    end
else
    role = "";
end
end
function [names, catalog, duplicateNames] = localLoggedSignals(modelName)
entryTemplate = struct("name", "", "storage", "", "sourcePath", "", ...
    "sourcePort", NaN, "selector", "");
catalog = repmat(entryTemplate, 0, 1);
lineHandles = localFindAllVariants(modelName, "FindAll", "on", "Type", "line");
for idx = 1:numel(lineHandles)
    try
        if ~strcmpi(get_param(lineHandles(idx), "DataLogging"), "on")
            continue;
        end
        signalName = string(get_param(lineHandles(idx), "Name"));
        if strlength(signalName) == 0
            continue;
        end
        item = entryTemplate;
        item.name = signalName;
        item.storage = "logsout";
        item.sourcePath = localLineSourcePath(lineHandles(idx));
        item.sourcePort = localLineSourcePort(lineHandles(idx));
        item.selector = "logsout:" + signalName;
        catalog(end + 1, 1) = item; %#ok<AGROW>
    catch
    end
end
workspaceBlocks = localFindAllVariants(modelName, "BlockType", "ToWorkspace");
for idx = 1:numel(workspaceBlocks)
    try
        variableName = string(get_param(workspaceBlocks{idx}, "VariableName"));
        if strlength(variableName) == 0
            continue;
        end
        item = entryTemplate;
        item.name = variableName;
        item.storage = "workspace";
        item.sourcePath = localWorkspaceSourcePath(workspaceBlocks{idx});
        item.sourcePort = localWorkspaceSourcePort(workspaceBlocks{idx});
        item.selector = "workspace:" + variableName;
        catalog(end + 1, 1) = item; %#ok<AGROW>
    catch
    end
end
allNames = string({catalog.name}).';
names = unique(allNames, "stable");
duplicateNames = strings(0, 1);
for idx = 1:numel(names)
    if sum(allNames == names(idx)) > 1
        duplicateNames(end + 1, 1) = names(idx); %#ok<AGROW>
    end
end
end

function path = localLineSourcePath(lineHandle)
path = "";
sourceHandle = get_param(lineHandle, "SrcBlockHandle");
if isnumeric(sourceHandle) && sourceHandle > 0
    path = string(getfullname(sourceHandle));
end
end

function port = localLineSourcePort(lineHandle)
port = NaN;
portHandle = get_param(lineHandle, "SrcPortHandle");
if isnumeric(portHandle) && portHandle > 0
    port = double(get_param(portHandle, "PortNumber"));
end
end

function path = localWorkspaceSourcePath(blockPath)
path = "";
portHandles = get_param(blockPath, "PortHandles");
if isempty(portHandles.Inport)
    return;
end
lineHandle = get_param(portHandles.Inport(1), "Line");
if isnumeric(lineHandle) && lineHandle > 0
    path = localLineSourcePath(lineHandle);
end
end

function port = localWorkspaceSourcePort(blockPath)
port = NaN;
portHandles = get_param(blockPath, "PortHandles");
if isempty(portHandles.Inport)
    return;
end
lineHandle = get_param(portHandles.Inport(1), "Line");
if isnumeric(lineHandle) && lineHandle > 0
    port = localLineSourcePort(lineHandle);
end
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
