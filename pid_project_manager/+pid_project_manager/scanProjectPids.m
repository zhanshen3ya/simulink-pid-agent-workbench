function catalog = scanProjectPids(modelFile)
%SCANPROJECTPIDS Build a catalog of PID Controller blocks.

arguments
    modelFile (1, 1) string
end

[topModel, resolvedPath] = pid_tuning_core.resolveSimulinkModel(modelFile);
resolvedPath = localAbsolutePath(string(resolvedPath));
load_system(resolvedPath);
modelNames = localReferencedModels(topModel);
controllers = repmat(localEmptyController(), 0, 1);
discoveryOrder = 0;

for modelIndex = 1:numel(modelNames)
    modelName = modelNames(modelIndex);
    try
        load_system(modelName);
    catch exception
        warning("PIDAgent:ModelLoadFailed", ...
            "Could not load referenced model %s: %s", modelName, exception.message);
        continue;
    end
    blocks = localFindPidBlocks(modelName);
    for blockIndex = 1:numel(blocks)
        discoveryOrder = discoveryOrder + 1;
        blockPath = string(blocks{blockIndex});
        params = pid_tuning_core.readPidBlockParams(blockPath);
        item = localEmptyController();
        item.controllerId = localStableId(blockPath);
        item.name = string(get_param(blockPath, "Name"));
        item.path = blockPath;
        item.modelName = modelName;
        item.modelPath = localModelPath(modelName);
        item.parentSystem = string(get_param(blockPath, "Parent"));
        item.referenceContext = localReferenceContext(topModel, modelName);
        item.isReferencedModel = modelName ~= topModel;
        item.blockType = string(get_param(blockPath, "BlockType"));
        item.maskType = string(localGetParam(blockPath, "MaskType"));
        item.referenceBlock = string(localGetParam(blockPath, "ReferenceBlock"));
        item.linkStatus = string(localGetParam(blockPath, "LinkStatus"));
        item.currentPid = params.numeric;
        item.rawPid = params.raw;
        item.parameterSource = localParameterSource(params.raw);
        item.selected = false;
        item.role = "single";
        item.groupId = "";
        item.order = discoveryOrder;
        item.mode = "single";
        item.referenceSignalName = "r";
        item.outputSignalName = "y";
        item.controlSignalName = "u";
        item.currentSignalName = "";
        item.status = localInitialStatus(item);
        controllers(end + 1, 1) = item; %#ok<AGROW>
    end
end

catalog = struct();
catalog.schemaVersion = 1;
catalog.generatedAt = string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
catalog.projectRoot = string(fileparts(resolvedPath));
catalog.topModelName = topModel;
catalog.topModelPath = string(resolvedPath);
catalog.modelNames = modelNames;
catalog.controllers = controllers;
catalog.controllerCount = numel(controllers);
catalog.selectedCount = 0;
end

function value = localAbsolutePath(value)
[folder, ~, ~] = fileparts(value);
if strlength(string(folder)) == 0
    value = string(fullfile(pwd, value));
end
end
function models = localReferencedModels(topModel)
models = string(topModel);
try
    referenced = string(find_mdlrefs(topModel, "AllLevels", true, ...
        "MatchFilter", @Simulink.match.allVariants));
    referenced = referenced(strlength(referenced) > 0);
    models = unique([models; referenced(:)], "stable");
catch
end
end

function blocks = localFindPidBlocks(modelName)
try
    candidates = find_system(modelName, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "MatchFilter", @Simulink.match.allVariants, ...
        "Type", "Block");
catch
    candidates = find_system(modelName, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "Type", "Block");
end
blocks = cell(0, 1);
for index = 1:numel(candidates)
    blockPath = candidates{index};
    blockType = string(localGetParam(blockPath, "BlockType"));
    maskType = string(localGetParam(blockPath, "MaskType"));
    referenceBlock = string(localGetParam(blockPath, "ReferenceBlock"));
    dialogParams = localDialogParameters(blockPath);
    descriptor = lower(blockType + " " + maskType + " " + referenceBlock);
    hasPidName = contains(descriptor, "pid");
    hasPidParams = isfield(dialogParams, "P") && isfield(dialogParams, "I") && ...
        isfield(dialogParams, "D");
    if hasPidName && hasPidParams
        blocks{end + 1, 1} = blockPath; %#ok<AGROW>
    end
end
end

function params = localDialogParameters(blockPath)
params = struct();
try
    params = get_param(blockPath, "DialogParameters");
catch
end
if isempty(params)
    params = struct();
end
end

function item = localEmptyController()
emptyPid = struct("Kp", 0, "Ki", 0, "Kd", 0, "N", 100);
emptyRaw = struct("P", "", "I", "", "D", "", "N", "");
emptySource = struct("P", "", "I", "", "D", "", "N", "");
item = struct("controllerId", "", "name", "", "path", "", ...
    "modelName", "", "modelPath", "", "parentSystem", "", ...
    "referenceContext", "", "isReferencedModel", false, ...
    "blockType", "", "maskType", "", "referenceBlock", "", ...
    "linkStatus", "", "currentPid", emptyPid, "rawPid", emptyRaw, ...
    "parameterSource", emptySource, "selected", false, "role", "single", ...
    "groupId", "", "order", 0, "mode", "single", ...
    "referenceSignalName", "r", "outputSignalName", "y", ...
    "controlSignalName", "u", "currentSignalName", "", "status", "ready");
end

function value = localGetParam(blockPath, parameter)
value = "";
try
    value = get_param(blockPath, parameter);
catch
end
end

function modelPath = localModelPath(modelName)
modelPath = "";
try
    modelPath = string(get_param(modelName, "FileName"));
catch
end
end

function context = localReferenceContext(topModel, modelName)
if modelName == topModel
    context = "top-model";
else
    context = "referenced-model:" + modelName;
end
end

function source = localParameterSource(raw)
source = struct();
fields = ["P", "I", "D", "N"];
for field = fields
    textValue = string(raw.(field));
    numericValue = str2double(textValue);
    if strlength(textValue) == 0
        source.(field) = "missing";
    elseif isfinite(numericValue)
        source.(field) = "literal";
    else
        source.(field) = "expression";
    end
end
end

function status = localInitialStatus(item)
if item.isReferencedModel
    status = "discovered-reference";
elseif item.linkStatus == "resolved" || item.linkStatus == "implicit"
    status = "ready-linked";
else
    status = "ready";
end
end

function id = localStableId(value)
digest = java.security.MessageDigest.getInstance("SHA-256");
bytes = digest.digest(uint8(unicode2native(char(value), "UTF-8")));
hex = lower(reshape(dec2hex(typecast(bytes, "uint8"), 2).', 1, []));
id = "pid-" + string(hex(1:16));
end