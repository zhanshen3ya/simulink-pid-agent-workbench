function export = build_block_graph(modelFile)
%BUILD_BLOCK_GRAPH Export a read-only Block/Port/Signal graph for P0.

[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(modelFile);
wasLoaded = bdIsLoaded(modelName);
load_system(resolvedPath);
cleanup = onCleanup(@() localCloseIfNeeded(modelName, wasLoaded));

blockTemplate = struct("id", "", "name", "", "path", "", ...
    "block_type", "", "mask_type", "", "reference_block", "", ...
    "parameters", struct(), "link_status", "", "safe_to_modify", false);
portTemplate = struct("id", "", "block_id", "", "direction", "", "index", 0);
signalTemplate = struct("id", "", "name", "", "src_port", "", ...
    "dst_ports", strings(0, 1), "unit", "", "sample_time", "");
controllerTemplate = struct("id", "", "name", "", "path", "", ...
    "block_type", "", "mask_type", "", "reference_block", "", ...
    "parameters", struct(), "link_status", "", "safe_to_modify", false, ...
    "input_ports", strings(0, 1), "output_ports", strings(0, 1), ...
    "controller_type", "", "time_domain", "", "sample_time", "", ...
    "form", "", "parent", "", "output_limits", struct(), ...
    "anti_windup", struct());

blocks = repmat(blockTemplate, 0, 1);
ports = repmat(portTemplate, 0, 1);
signals = repmat(signalTemplate, 0, 1);
controllers = repmat(controllerTemplate, 0, 1);
portIds = containers.Map("KeyType", "char", "ValueType", "char");

blockPaths = localFindBlocks(modelName);
for blockIndex = 1:numel(blockPaths)
    blockPath = blockPaths{blockIndex};
    handle = get_param(blockPath, "Handle");
    blockId = localBlockId(modelName, handle);
    blockType = string(localGet(blockPath, "BlockType", ""));
    maskType = string(localGet(blockPath, "MaskType", ""));
    referenceBlock = string(localGet(blockPath, "ReferenceBlock", ""));
    linkStatus = string(localGet(blockPath, "LinkStatus", "none"));
    parameters = localParameters(blockPath, blockType);

    item = blockTemplate;
    item.id = blockId;
    item.name = string(localGet(blockPath, "Name", ""));
    item.path = string(blockPath);
    item.block_type = blockType;
    item.mask_type = maskType;
    item.reference_block = referenceBlock;
    item.parameters = parameters;
    item.link_status = linkStatus;
    item.safe_to_modify = ismember(lower(linkStatus), ["none", "inactive", "resolved"]);
    blocks(end + 1, 1) = item; %#ok<AGROW>

    handles = get_param(blockPath, "PortHandles");
    inputIds = localAddPorts(handles, "Inport", "in", blockId);
    outputIds = localAddPorts(handles, "Outport", "out", blockId);
    if localIsStandardPid(blockType, maskType, referenceBlock, parameters)
        controller = controllerTemplate;
        controller.id = item.id;
        controller.name = item.name;
        controller.path = item.path;
        controller.block_type = item.block_type;
        controller.mask_type = item.mask_type;
        controller.reference_block = item.reference_block;
        controller.parameters = item.parameters;
        controller.link_status = item.link_status;
        controller.safe_to_modify = item.safe_to_modify;
        controller.input_ports = inputIds;
        controller.output_ports = outputIds;
        controller.controller_type = "PID Controller";
        controller.time_domain = string(localGet(blockPath, "TimeDomain", "unknown"));
        controller.sample_time = string(localGet(blockPath, "SampleTime", ""));
        controller.form = string(localGet(blockPath, "Form", ""));
        controller.parent = string(get_param(blockPath, "Parent"));
        controller.output_limits = localOutputLimits(blockPath);
        controller.anti_windup = localAntiWindup(blockPath);
        controllers(end + 1, 1) = controller; %#ok<AGROW>
    end
end

outputPorts = find_system(modelName, "FindAll", "on", "Type", "port", "PortType", "outport");
for portIndex = 1:numel(outputPorts)
    sourceHandle = outputPorts(portIndex);
    lineHandle = get_param(sourceHandle, "Line");
    if isempty(lineHandle) || lineHandle == -1
        continue;
    end
    sourceKey = localHandleKey(sourceHandle);
    if ~isKey(portIds, sourceKey)
        continue;
    end
    destinationHandles = get_param(lineHandle, "DstPortHandle");
    destinationIds = strings(0, 1);
    for destinationIndex = 1:numel(destinationHandles)
        key = localHandleKey(destinationHandles(destinationIndex));
        if isKey(portIds, key)
            destinationIds(end + 1, 1) = string(portIds(key)); %#ok<AGROW>
        end
    end
    signal = signalTemplate;
    signal.id = "sig_" + string(numel(signals) + 1);
    signal.name = string(localGet(lineHandle, "Name", ""));
    signal.src_port = string(portIds(sourceKey));
    signal.dst_ports = destinationIds;
    signals(end + 1, 1) = signal; %#ok<AGROW>
end

export = struct();
export.schema_version = "autopid.matlab_scan.v1";
export.model_name = string(modelName);
export.model_path = string(resolvedPath);
export.blocks = blocks;
export.ports = ports;
export.signals = signals;
export.controllers = controllers;
export.virtual_edges = struct([]);
export.unresolved = strings(0, 1);

    function ids = localAddPorts(handles, fieldName, direction, blockId)
        ids = strings(0, 1);
        if ~isfield(handles, fieldName)
            return;
        end
        values = handles.(fieldName);
        for index = 1:numel(values)
            port = portTemplate;
            port.id = blockId + ":" + direction + ":" + index;
            port.block_id = blockId;
            port.direction = direction;
            port.index = index;
            ports(end + 1, 1) = port; %#ok<AGROW>
            portIds(localHandleKey(values(index))) = char(port.id);
            ids(end + 1, 1) = port.id; %#ok<AGROW>
        end
    end
end

function paths = localFindBlocks(modelName)
searchArgs = {"LookUnderMasks", "all", "FollowLinks", "off", "Type", "Block"};
try
    paths = find_system(modelName, "MatchFilter", @Simulink.match.allVariants, ...
        searchArgs{:});
catch
    paths = find_system(modelName, searchArgs{:});
end
paths = cellstr(paths);
end

function id = localBlockId(modelName, handle)
try
    sid = string(Simulink.ID.getSID(handle));
catch
    sid = string(modelName) + ":" + string(round(handle));
end
id = "blk_" + regexprep(sid, "[^A-Za-z0-9_]", "_");
end

function key = localHandleKey(handle)
key = sprintf("%.17g", double(handle));
end

function value = localGet(target, name, fallback)
try
    value = get_param(target, name);
catch
    value = fallback;
end
end

function parameters = localParameters(blockPath, blockType)
parameters = struct();
if ismember(lower(blockType), ["sum", "add"])
    parameters.Inputs = string(localGet(blockPath, "Inputs", ""));
end
dialog = localGet(blockPath, "DialogParameters", struct());
if isstruct(dialog) && all(isfield(dialog, ["P", "I", "D"]))
    for name = ["P", "I", "D", "N"]
        if isfield(dialog, name)
            parameters.(name) = string(localGet(blockPath, name, ""));
        end
    end
end
end

function result = localIsStandardPid(blockType, maskType, referenceBlock, parameters)
descriptor = lower(blockType + " " + maskType + " " + referenceBlock);
result = contains(descriptor, "pid") && all(isfield(parameters, ["P", "I", "D"]));
end

function limits = localOutputLimits(blockPath)
limits = struct();
for item = ["UpperSaturationLimit", "LowerSaturationLimit"]
    value = localGet(blockPath, item, "");
    if strlength(string(value)) > 0
        limits.(item) = string(value);
    end
end
end

function antiWindup = localAntiWindup(blockPath)
antiWindup = struct();
value = localGet(blockPath, "AntiWindupMode", "");
if strlength(string(value)) > 0
    antiWindup.mode = string(value);
end
end

function localCloseIfNeeded(modelName, wasLoaded)
if ~wasLoaded && bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end
