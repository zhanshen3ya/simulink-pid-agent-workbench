function result = demo_buck_dual_loop_tuning()
%DEMO_BUCK_DUAL_LOOP_TUNING Jointly tune voltage and current PI controllers.

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "pid_ai_buck_dual_loop_demo";
cfg.stopTime = "0.3";

cfg.pidBlocks(1).name = "voltage";
cfg.pidBlocks(1).path = "pid_ai_buck_dual_loop_demo/Outer_Voltage_PI";
cfg.pidBlocks(1).bounds.Kp = [0.01, 0.15];
cfg.pidBlocks(1).bounds.Ki = [4, 24];
cfg.pidBlocks(1).bounds.Kd = [0, 0];
cfg.pidBlocks(1).bounds.N = [100, 100];

cfg.pidBlocks(2).name = "current";
cfg.pidBlocks(2).path = "pid_ai_buck_dual_loop_demo/Inner_Current_PI";
cfg.pidBlocks(2).bounds.Kp = [0.015, 0.08];
cfg.pidBlocks(2).bounds.Ki = [2, 20];
cfg.pidBlocks(2).bounds.Kd = [0, 0];
cfg.pidBlocks(2).bounds.N = [100, 100];

cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";
cfg.currentSignalName = "iL";
cfg.metrics.controlUpperLimit = 0.95;

cfg.maxIterations = 6;
cfg.numCandidates = 10;
cfg.stopOnFirstPass = false;

cfg.targets.overshootPctMax = 12;
cfg.targets.settlingTimeMax = 0.27;
cfg.targets.steadyStateErrorAbsMax = 0.1;
cfg.targets.iaeMax = 0.65;
cfg.targets.maxAbsControlMax = 0.95;
cfg.targets.maxAbsCurrentMax = 6;
cfg.targets.outputRippleMax = 0.2;
cfg.targets.controlSaturationFractionMax = 0.02;

result = main_pid_search(cfg);
end