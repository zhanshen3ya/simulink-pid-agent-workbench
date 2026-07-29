function tests = test_pid_tuning_core
%TEST_PID_TUNING_CORE Verify staged dual-loop evaluation and scoring.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
rootDir = fileparts(fileparts(mfilename("fullpath")));
addpath(rootDir, fullfile(rootDir, "pid_tuning_core"));
testCase.TestData.Root = rootDir;
end

function testCascadeStagePlan(testCase)
cfg = localConfig();
cfg.search.strategy = "cascade";
cfg.maxIterations = 9;
stages = pid_tuning_core.buildTuningStages(cfg);
verifyEqual(testCase, string({stages.role}), ["inner", "outer", "joint"]);
verifyEqual(testCase, [stages.activePidIndices], [1, 2, 1, 2]);
verifyEqual(testCase, sum([stages.iterations]), 9);
verifyEqual(testCase, stages(1).evaluationLoopIndices, 1);
verifyEqual(testCase, stages(2).evaluationLoopIndices, [1, 2]);
end

function testBothLoopsPassTogether(testCase)
cfg = localConfig();
simulation = struct("success", true, "output", localSimulation(false), "error", "");
candidate = cfg.initialCandidate;
metrics = pid_tuning_core.evaluatePidRun(simulation, candidate, cfg);
validation = pid_tuning_core.validatePidMetrics(metrics, cfg);
verifyEqual(testCase, metrics.loopCount, 2);
verifyEqual(testCase, numel(metrics.loopMetrics), 2);
verifyEqual(testCase, numel(validation.loopValidations), 2);
verifyTrue(testCase, validation.passed, strjoin(validation.failures, ", "));
end

function testInnerFailureRejectsWholeCandidate(testCase)
cfg = localConfig();
simulation = struct("success", true, "output", localSimulation(true), "error", "");
metrics = pid_tuning_core.evaluatePidRun(simulation, cfg.initialCandidate, cfg);
validation = pid_tuning_core.validatePidMetrics(metrics, cfg);
verifyFalse(testCase, validation.passed);
verifyTrue(testCase, any(contains(validation.failures, "loop:current:")));
verifyFalse(testCase, validation.loopValidations(1).passed);
end

function testInactivePidIsFrozen(testCase)
cfg = localConfig();
cfg.activePidIndices = 1;
state = struct("iteration", 2, "stageIteration", 1, ...
    "searchCenter", cfg.initialCandidate, "searchScale", 0.3, ...
    "history", [], "currentStage", "inner-loop");
candidates = pid_tuning_core.generatePidCandidates(state, cfg, 8);
outer = arrayfun(@(item) item.pids(2), candidates);
verifyEqual(testCase, [outer.Kp], repmat(cfg.initialCandidate.pids(2).Kp, 1, 8));
verifyEqual(testCase, [outer.Ki], repmat(cfg.initialCandidate.pids(2).Ki, 1, 8));
end

function testInitialReferenceStepOvershootIsMeasured(testCase)
cfg = localConfig();
cfg.evaluationLoops = cfg.evaluationLoops(2);
cfg.evaluationLoops(1).role = "single";
cfg.evaluationLoops(1).primary = true;
cfg.evaluationLoops(1).targets.overshootPctMax = 10;
t = (0:0.01:2).';
r = ones(size(t));
y = 1 - exp(-5 * t) + 0.22 * exp(-3 * (t - 0.35).^2 / 0.01);
u = 0.5 * ones(size(t));
out = struct();
out.r = timeseries(r, t);
out.y = timeseries(y, t);
out.u = timeseries(u, t);
simulation = struct("success", true, "output", out, "error", "");
metrics = pid_tuning_core.evaluatePidRun(simulation, cfg.initialCandidate, cfg);
verifyGreaterThan(testCase, metrics.overshootPct, 10);
end

function cfg = localConfig()
cfg = pid_tuning_core.defaultPidTuningConfig();
bounds = struct("Kp", [0, 10], "Ki", [0, 10], "Kd", [0, 1], "N", [10, 500]);
cfg.pidBlocks = [
    struct("name", "inner", "path", "demo/Inner PID", "bounds", bounds), ...
    struct("name", "outer", "path", "demo/Outer PID", "bounds", bounds)];
cfg.initialCandidate = struct("pids", [
    struct("name", "inner", "Kp", 1, "Ki", 1, "Kd", 0, "N", 100), ...
    struct("name", "outer", "Kp", 1, "Ki", 1, "Kd", 0, "N", 100)]);
cfg.ai.enabled = false;
cfg.maxIterations = 9;
cfg.numCandidates = 8;
baseTargets = struct("overshootPctMax", 25, "settlingTimeMax", 2, ...
    "steadyStateErrorAbsMax", 0.1, "maxAbsCurrentMax", 3, ...
    "controlSaturationFractionMax", 0.1);
innerMetrics = cfg.metrics;
innerMetrics.controlLowerLimit = -2;
innerMetrics.controlUpperLimit = 2;
outerMetrics = cfg.metrics;
outerMetrics.controlLowerLimit = -5;
outerMetrics.controlUpperLimit = 5;
cfg.evaluationLoops = [
    struct("name", "current", "role", "inner", "pidPath", "demo/Inner PID", ...
        "referenceSignalName", "iRef", "outputSignalName", "iL", ...
        "controlSignalName", "duty", "currentSignalName", "iL", ...
        "weight", 1, "enabled", true, "primary", false, ...
        "targets", baseTargets, "metrics", innerMetrics), ...
    struct("name", "voltage", "role", "outer", "pidPath", "demo/Outer PID", ...
        "referenceSignalName", "r", "outputSignalName", "y", ...
        "controlSignalName", "iRef", "currentSignalName", "iL", ...
        "weight", 1, "enabled", true, "primary", true, ...
        "targets", baseTargets, "metrics", outerMetrics)];
end

function out = localSimulation(failInner)
t = (0:0.01:2).';
r = ones(size(t));
y = 1 - exp(-6 * t);
iRef = 2 * ones(size(t));
if failInner
    iL = 5 + sin(20 * t);
else
    iL = 2 * (1 - exp(-10 * t));
end
duty = 0.5 * ones(size(t));
out = struct();
out.r = timeseries(r, t);
out.y = timeseries(y, t);
out.iRef = timeseries(iRef, t);
out.iL = timeseries(iL, t);
out.duty = timeseries(duty, t);
end