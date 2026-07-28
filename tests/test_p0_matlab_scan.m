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