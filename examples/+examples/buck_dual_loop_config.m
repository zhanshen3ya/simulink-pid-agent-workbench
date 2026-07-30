function cfg = buck_dual_loop_config()
%BUCK_DUAL_LOOP_CONFIG Configure staged voltage-current cascade tuning.

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "pid_ai_buck_dual_loop_demo";
cfg.stopTime = "0.3";

cfg.pidBlocks(1).name = "voltage";
cfg.pidBlocks(1).path = cfg.modelName + "/Outer_Voltage_PI";
cfg.pidBlocks(1).bounds.Kp = [0.01, 0.15];
cfg.pidBlocks(1).bounds.Ki = [4, 24];
cfg.pidBlocks(1).bounds.Kd = [0, 0];
cfg.pidBlocks(1).bounds.N = [100, 100];

cfg.pidBlocks(2).name = "current";
cfg.pidBlocks(2).path = cfg.modelName + "/Inner_Current_PI";
cfg.pidBlocks(2).bounds.Kp = [0.015, 0.08];
cfg.pidBlocks(2).bounds.Ki = [2, 20];
cfg.pidBlocks(2).bounds.Kd = [0, 0];
cfg.pidBlocks(2).bounds.N = [100, 100];

cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "iRef";
cfg.currentSignalName = "iL";

cfg.maxIterations = 6;
cfg.numCandidates = 10;
cfg.stopOnFirstPass = false;

cfg.targets.overshootPctMax = 12;
cfg.targets.settlingTimeMax = 0.27;
cfg.targets.steadyStateErrorAbsMax = 0.1;
cfg.targets.iaeMax = 0.65;
cfg.targets.maxAbsControlMax = 8;
cfg.targets.maxAbsCurrentMax = 6;
cfg.targets.outputRippleMax = 0.2;
cfg.targets.controlSaturationFractionMax = 0.02;
cfg.metrics.controlLowerLimit = 0;
cfg.metrics.controlUpperLimit = 8;

outerTargets = cfg.targets;
outerMetrics = cfg.metrics;
innerTargets = cfg.targets;
innerTargets.overshootPctMax = 10;
innerTargets.settlingTimeMax = 0.08;
innerTargets.steadyStateErrorAbsMax = 0.1;
innerTargets.iaeMax = 0.2;
innerTargets.maxAbsControlMax = 0.95;
innerTargets.outputRippleMax = 0.1;
innerTargets.trackingRmseMax = 0.8;
innerMetrics = cfg.metrics;
innerMetrics.controlUpperLimit = 0.95;

cfg.evaluationLoops = [
    struct("name", "voltage", "role", "outer", ...
        "pidPath", cfg.pidBlocks(1).path, ...
        "referenceSignalName", "r", "outputSignalName", "y", ...
        "controlSignalName", "iRef", "currentSignalName", "iL", ...
        "weight", 1, "enabled", true, "primary", true, ...
        "targets", outerTargets, "metrics", outerMetrics), ...
    struct("name", "current", "role", "inner", ...
        "pidPath", cfg.pidBlocks(2).path, ...
        "referenceSignalName", "iRef", "outputSignalName", "iL", ...
        "controlSignalName", "u", "currentSignalName", "iL", ...
        "weight", 1, "enabled", true, "primary", false, ...
        "targets", innerTargets, "metrics", innerMetrics)];
end
