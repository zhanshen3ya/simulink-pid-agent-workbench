function result = demo_pid_ai_tuning()
%DEMO_PID_AI_TUNING Run PID tuning on the generated demo model.

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "pid_ai_second_order_demo";
cfg.pidBlockPath = "pid_ai_second_order_demo/PID Controller";
cfg.stopTime = "10";

cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";

cfg.maxIterations = 8;
cfg.numCandidates = 12;
cfg.stopOnFirstPass = false;

cfg.bounds.Kp = [0, 80];
cfg.bounds.Ki = [0, 80];
cfg.bounds.Kd = [0, 20];
cfg.bounds.N = [10, 500];

cfg.targets.overshootPctMax = 8;
cfg.targets.settlingTimeMax = 4;
cfg.targets.steadyStateErrorAbsMax = 0.03;

result = main_pid_search(cfg);
end
