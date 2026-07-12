projectRoot = fileparts(fileparts(mfilename('fullpath')));
cd(projectRoot);
addpath(genpath(pwd));
if ~exist('pid_ai_cascade_two_pid_demo.slx', 'file')
    examples.create_cascade_two_pid_demo;
end
cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "pid_ai_cascade_two_pid_demo";
cfg.stopTime = "4";
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
cfg.maxIterations = 1;
cfg.numCandidates = 2;
cfg.stopOnFirstPass = false;
cfg.logging.outputDir = fullfile(pwd, 'pid_tuning_runs');
cfg.logging.runId = "job_smoke_frontend_final";
result = main_pid_search(cfg);
disp("SMOKE_RUN_DIR=" + string(result.config.logging.runDir));
disp("SMOKE_HISTORY_EXISTS=" + string(isfile(result.config.logging.historyFile)));
disp("SMOKE_STATUS_EXISTS=" + string(isfile(result.config.logging.currentStatusFile)));
disp("SMOKE_BEST_EXISTS=" + string(isfile(result.config.logging.bestResultFile)));


