function tests = test_pid_agent_ui
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDir);
addpath(fullfile(rootDir, "pid_tuning_core"));
addpath(fullfile(rootDir, "pid_project_manager"));
addpath(fullfile(rootDir, "examples"));
testCase.TestData.RootDir = rootDir;
end

function teardown(~)
models = ["pid_ai_second_order_demo", "pid_ai_cascade_two_pid_demo"];
for model = models
    if bdIsLoaded(model)
        close_system(model, 0);
    end
end
end

function testCurrentModelContext(testCase)
modelPath = fullfile(testCase.TestData.RootDir, "pid_ai_second_order_demo.slx");
open_system(modelPath);
context = pid_agent_ui.resolveCurrentContext();

verifyEqual(testCase, context.modelName, "pid_ai_second_order_demo");
verifyEqual(testCase, context.modelInfo.pidCount, 1);
verifyEqual(testCase, context.modelPath, string(modelPath));
end

function testSelectedTwoPidContext(testCase)
modelPath = fullfile(testCase.TestData.RootDir, "pid_ai_cascade_two_pid_demo.slx");
open_system(modelPath);
outerPath = "pid_ai_cascade_two_pid_demo/Outer PID";
innerPath = "pid_ai_cascade_two_pid_demo/Inner PID";
set_param(outerPath, "Selected", "on");
set_param(innerPath, "Selected", "on");

context = pid_agent_ui.resolveCurrentContext();

verifyEqual(testCase, sort(context.selectedPidPaths), sort([outerPath; innerPath]));
verifyEqual(testCase, context.modelInfo.pidCount, 2);
end

function testGatewayRequestBuilder(testCase)
import matlab.net.http.RequestMethod

getRequest = pid_agent_ui.buildGatewayRequest("GET");
verifyEqual(testCase, getRequest.Method, RequestMethod.GET);

postRequest = pid_agent_ui.buildGatewayRequest("POST", struct("type", "codex"));
verifyEqual(testCase, postRequest.Method, RequestMethod.POST);
verifyEqual(testCase, postRequest.Body.Data, struct("type", "codex"));
end
