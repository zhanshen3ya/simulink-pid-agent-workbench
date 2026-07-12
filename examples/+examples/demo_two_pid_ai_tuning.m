function result = demo_two_pid_ai_tuning()
%DEMO_TWO_PID_AI_TUNING Tune inner and outer PID blocks as one candidate.

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "pid_ai_cascade_two_pid_demo";
cfg.stopTime = "8";

cfg.pidBlocks(1).name = "outer";
cfg.pidBlocks(1).path = "pid_ai_cascade_two_pid_demo/Outer PID";
cfg.pidBlocks(1).bounds.Kp = [0, 40];
cfg.pidBlocks(1).bounds.Ki = [0, 30];
cfg.pidBlocks(1).bounds.Kd = [0, 10];
cfg.pidBlocks(1).bounds.N = [10, 500];

cfg.pidBlocks(2).name = "inner";
cfg.pidBlocks(2).path = "pid_ai_cascade_two_pid_demo/Inner PID";
cfg.pidBlocks(2).bounds.Kp = [0, 60];
cfg.pidBlocks(2).bounds.Ki = [0, 40];
cfg.pidBlocks(2).bounds.Kd = [0, 10];
cfg.pidBlocks(2).bounds.N = [10, 500];

cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";

cfg.maxIterations = 8;
cfg.numCandidates = 14;
cfg.stopOnFirstPass = false;

cfg.targets.overshootPctMax = 12;
cfg.targets.settlingTimeMax = 6;
cfg.targets.steadyStateErrorAbsMax = 0.05;

result = main_pid_search(cfg);
end

