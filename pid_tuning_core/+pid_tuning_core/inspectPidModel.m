function info = inspectPidModel(modelFile)
%INSPECTPIDMODEL Inspect a Simulink model for tunable PID blocks and logged signals.

[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(modelFile);
load_system(resolvedPath);

blocks = localFindAllVariants(modelName, "Type", "Block");

emptyPid = struct("name", "", "path", "", "blockType", "", ...
    "maskType", "", "referenceBlock", "", "currentPid", ...
    struct("Kp", 0, "Ki", 0, "Kd", 0, "N", 100));
pidBlocks = repmat(emptyPid, 0, 1);

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
    pidBlocks(end + 1, 1) = item; %#ok<AGROW>
end

info = struct();
info.modelName = string(modelName);
info.modelPath = string(resolvedPath);
info.pidBlocks = pidBlocks;
info.loggedSignals = localLoggedSignals(modelName);
info.pidCount = numel(pidBlocks);
end

function value = localGetParam(blockPath, parameter)
value = "";
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
