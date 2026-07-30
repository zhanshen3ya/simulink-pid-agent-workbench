function tests = test_buck_dual_loop_demo
%TEST_BUCK_DUAL_LOOP_DEMO Verify real cascade signal mappings and metrics.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDir, fullfile(rootDir, "pid_tuning_core"));
testCase.TestData.Root = rootDir;
end

function testCascadeConfiguration(testCase)
cfg = examples.buck_dual_loop_config();
loops = pid_tuning_core.normalizeEvaluationLoops(cfg);
roles = lower(string({loops.role}));
outer = loops(find(roles == "outer", 1));
inner = loops(find(roles == "inner", 1));

verifyTrue(testCase, outer.primary);
verifyFalse(testCase, inner.primary);
verifyEqual(testCase, outer.controlSignalName, inner.referenceSignalName);
verifyEqual(testCase, outer.controlSignalName, "iRef");
verifyEqual(testCase, inner.outputSignalName, "iL");
verifyEqual(testCase, inner.controlSignalName, "u");
verifyLessThan(testCase, inner.targets.settlingTimeMax, ...
    outer.targets.settlingTimeMax);
end

function testBaselineEvaluatesBothLoops(testCase)
oldFolder = cd(testCase.TestData.Root);
cleanup = onCleanup(@() cd(oldFolder));
report = examples.validate_buck_dual_loop_demo();

verifyEqual(testCase, report.metrics.loopCount, 2);
verifyEqual(testCase, string({report.metrics.loopMetrics.role}), ...
    ["outer", "inner"]);
verifyTrue(testCase, all([report.metrics.loopMetrics.simulationSuccess]));
verifyTrue(testCase, all([report.metrics.loopMetrics.isStable]));
verifyTrue(testCase, report.validation.passed, ...
    strjoin(report.validation.failures, ", "));
end
