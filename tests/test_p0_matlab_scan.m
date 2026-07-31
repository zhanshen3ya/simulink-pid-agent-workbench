function tests = test_p0_matlab_scan
%TEST_P0_MATLAB_SCAN Verify the read-only MATLAB scan contract.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDir, fullfile(rootDir, "matlab"), ...
    fullfile(rootDir, "pid_tuning_core"), fullfile(rootDir, "examples"));
testCase.TestData.Root = rootDir;
end

function testSecondOrderScanContract(testCase)
modelPath = fullfile(testCase.TestData.Root, "pid_ai_second_order_demo.slx");
verifyTrue(testCase, isfile(modelPath));
[~, modelName] = fileparts(modelPath);
wasLoaded = bdIsLoaded(modelName);
if ~wasLoaded
    load_system(modelPath);
end
cleanup = onCleanup(@() localCloseIfNeeded(modelName, wasLoaded));
dirtyBefore = string(get_param(modelName, "Dirty"));

result = scan_model(modelPath);

verifyEqual(testCase, string(result.schema_version), "autopid.matlab_scan.v1");
verifyGreaterThan(testCase, numel(result.blocks), 0);
verifyLessThan(testCase, numel(result.blocks), 50, ...
    "Library implementation blocks must not be expanded.");
verifyGreaterThan(testCase, numel(result.ports), 0);
verifyGreaterThan(testCase, numel(result.signals), 0);
verifyEqual(testCase, numel(result.controllers), 1);
verifyTrue(testCase, all(isfield(result.controllers, ...
    ["parameters", "input_ports", "output_ports", "safe_to_modify"])));
verifyEqual(testCase, string(get_param(modelName, "Dirty")), dirtyBefore);
end

function testPidInspectionSuggestsLoggedSignals(testCase)
modelPath = fullfile(testCase.TestData.Root, "pid_ai_second_order_demo.slx");
info = pid_tuning_core.inspectPidModel(modelPath);

verifyEqual(testCase, numel(info.pidBlocks), 1);
suggestion = info.pidBlocks(1).signalSuggestion;
verifyEqual(testCase, string(suggestion.referenceSignalName), "r");
verifyEqual(testCase, string(suggestion.outputSignalName), "y");
verifyEqual(testCase, string(suggestion.controlSignalName), "u");
verifyTrue(testCase, suggestion.complete);
verifyTrue(testCase, suggestion.allLogged);
end

function testCascadeContainsTwoControllers(testCase)
modelPath = fullfile(testCase.TestData.Root, "pid_ai_cascade_two_pid_demo.slx");
verifyTrue(testCase, isfile(modelPath));
result = scan_model(modelPath);
verifyEqual(testCase, numel(result.controllers), 2);
verifyTrue(testCase, all(arrayfun(@(item) ...
    all(isfield(item.parameters, ["P", "I", "D"])), result.controllers)));
end

function testMultiSystemRoleSuggestionsPreferNearestBlockName(testCase)
modelPath = fullfile(testCase.TestData.Root, "pid_ai_multi_system_demo.slx");
verifyTrue(testCase, isfile(modelPath));
info = pid_tuning_core.inspectPidModel(modelPath);
paths = string({info.pidBlocks.path});
roles = string({info.pidBlocks.suggestedRole});
innerMask = endsWith(paths, "/Inner PID");
outerMask = endsWith(paths, "/Outer PID");
verifyEqual(testCase, nnz(innerMask), 2);
verifyEqual(testCase, nnz(outerMask), 2);
verifyEqual(testCase, roles(innerMask), repmat("inner", 1, nnz(innerMask)));
verifyEqual(testCase, roles(outerMask), repmat("outer", 1, nnz(outerMask)));
end

function testBuckCascadeSignalsPassThroughSaturation(testCase)
modelPath = fullfile(testCase.TestData.Root, "pid_ai_buck_dual_loop_demo.slx");
info = pid_tuning_core.inspectPidModel(modelPath);
verifyEqual(testCase, sort(string(info.loggedSignals)), ...
    sort(["iL"; "iRef"; "r"; "u"; "y"]));
verifyEqual(testCase, numel(info.cascadePairs), 1);

paths = string({info.pidBlocks.path});
inner = info.pidBlocks(contains(paths, "Inner_Current_PI"));
outer = info.pidBlocks(contains(paths, "Outer_Voltage_PI"));
verifyEqual(testCase, string(inner.signalSuggestion.referenceSignalName), "iRef");
verifyEqual(testCase, string(inner.signalSuggestion.outputSignalName), "iL");
verifyEqual(testCase, string(inner.signalSuggestion.controlSignalName), "u");
verifyEqual(testCase, string(outer.signalSuggestion.controlSignalName), "iRef");
verifyEqual(testCase, string(inner.suggestedRole), "inner");
verifyEqual(testCase, string(outer.suggestedRole), "outer");
verifyEqual(testCase, string(inner.cascadePartnerPath), string(outer.path));
verifyEqual(testCase, string(outer.cascadePartnerPath), string(inner.path));
verifyTrue(testCase, inner.signalSuggestion.allLogged);
verifyTrue(testCase, outer.signalSuggestion.allLogged);
end

function testTransformedCascadeUsesTopologyInsteadOfSignalEquality(testCase)
[modelPath, modelName] = localCreateTransformedCascadeModel();
cleanup = onCleanup(@() localCloseAndDeleteModel(modelName, modelPath));
info = pid_tuning_core.inspectPidModel(modelPath);

verifyEqual(testCase, numel(info.cascadePairs), 1);
pair = info.cascadePairs(1);
verifyEqual(testCase, string(pair.connectionKind), "transformed");
verifyEqual(testCase, string(pair.outerControlSignalName), "iRef");
verifyEqual(testCase, string(pair.innerReferenceSignalName), "iGridRef");
verifyTrue(testCase, any(endsWith(string(pair.transformBlocks), "/Current Reference Product")));

paths = string({info.pidBlocks.path});
outer = info.pidBlocks(endsWith(paths, "/Voltage PID"));
inner = info.pidBlocks(endsWith(paths, "/Current PID"));
verifyEqual(testCase, string(outer.suggestedRole), "outer");
verifyEqual(testCase, string(inner.suggestedRole), "inner");
verifyEqual(testCase, string(outer.cascadePartnerPath), string(inner.path));
verifyEqual(testCase, string(inner.cascadePartnerPath), string(outer.path));
end
function testJsonScanBridge(testCase)
requestPath = string(tempname) + ".json";
outputPath = string(tempname) + ".json";
cleanup = onCleanup(@() localDeleteFiles(requestPath, outputPath));
request = struct("model_file", fullfile(testCase.TestData.Root, ...
    "pid_ai_second_order_demo.slx"));
localWriteText(requestPath, jsonencode(request));
scan_model_to_json(requestPath, outputPath);
result = jsondecode(fileread(outputPath));
verifyEqual(testCase, string(result.schema_version), "autopid.matlab_scan.v1");
verifyEqual(testCase, numel(result.controllers), 1);
end

function testBaselineReturnsLoggedSignals(testCase)
request = struct();
request.model_file = fullfile(testCase.TestData.Root, ...
    "pid_ai_second_order_demo.slx");
request.stop_time = 10;
request.signals = struct("reference", "r", "measurement", "y", ...
    "raw_control", "u", "actuator_control", [], "current", []);
result = run_baseline(request);
verifyTrue(testCase, result.success, result.solver_error);
verifyGreaterThan(testCase, numel(result.signals.time), 10);
verifyEqual(testCase, numel(result.signals.time), numel(result.signals.reference));
verifyEqual(testCase, numel(result.signals.time), numel(result.signals.output));
verifyEqual(testCase, numel(result.signals.time), numel(result.signals.control));
end

function [modelPath, modelName] = localCreateTransformedCascadeModel()
[folder, baseName] = fileparts(tempname);
modelName = string(matlab.lang.makeValidName("pid_agent_" + baseName));
modelPath = fullfile(folder, modelName + ".slx");
new_system(modelName);
add_block("simulink/Sources/Step", modelName + "/Voltage Reference");
add_block("simulink/Sources/Constant", modelName + "/Voltage Feedback");
add_block("simulink/Math Operations/Sum", modelName + "/Voltage Error", "Inputs", "+-");
add_block("simulink/Continuous/PID Controller", modelName + "/Voltage PID");
add_block("simulink/Sources/Constant", modelName + "/Carrier", "Value", "1");
add_block("simulink/Math Operations/Product", modelName + "/Current Reference Product");
add_block("simulink/Sources/Constant", modelName + "/Current Feedback");
add_block("simulink/Math Operations/Sum", modelName + "/Current Error", "Inputs", "+-");
add_block("simulink/Continuous/PID Controller", modelName + "/Current PID");
add_block("simulink/Sinks/Terminator", modelName + "/PWM Input");
localAddLoggedLine(modelName, "Voltage Reference/1", "Voltage Error/1", "vRef");
localAddLoggedLine(modelName, "Voltage Feedback/1", "Voltage Error/2", "vOut");
add_line(modelName, "Voltage Error/1", "Voltage PID/1");
localAddLoggedLine(modelName, "Voltage PID/1", "Current Reference Product/1", "iRef");
add_line(modelName, "Carrier/1", "Current Reference Product/2");
localAddLoggedLine(modelName, "Current Reference Product/1", "Current Error/1", "iGridRef");
localAddLoggedLine(modelName, "Current Feedback/1", "Current Error/2", "iGrid");
add_line(modelName, "Current Error/1", "Current PID/1");
localAddLoggedLine(modelName, "Current PID/1", "PWM Input/1", "duty");
save_system(modelName, modelPath);
end

function localAddLoggedLine(modelName, source, destination, signalName)
lineHandle = add_line(modelName, source, destination);
set_param(lineHandle, "Name", signalName);
loggerName = "log_" + signalName;
add_block("simulink/Sinks/To Workspace", modelName + "/" + loggerName, ...
    "VariableName", signalName, "SaveFormat", "Timeseries");
add_line(modelName, source, loggerName + "/1", "autorouting", "on");
end

function localCloseAndDeleteModel(modelName, modelPath)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
if isfile(modelPath)
    delete(modelPath);
end
end
function localWriteText(path, text)
fileId = fopen(path, "w", "n", "UTF-8");
assert(fileId >= 0, "Cannot create temporary JSON file.");
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, text, "char");
end

function localDeleteFiles(varargin)
for index = 1:nargin
    if isfile(varargin{index})
        delete(varargin{index});
    end
end
end

function localCloseIfNeeded(modelName, wasLoaded)
if ~wasLoaded && bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end