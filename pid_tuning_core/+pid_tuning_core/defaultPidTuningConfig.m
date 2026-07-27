function cfg = defaultPidTuningConfig()
%DEFAULTPIDTUNINGCONFIG Default configuration for closed-loop PID search.

cfg = struct();

cfg.modelName = "your_model";
cfg.pidBlockPath = "";
cfg.pidBlockPaths = strings(0, 1);
cfg.pidBlocks = struct([]);
cfg.tuneAllDiscoveredPidBlocks = false;
cfg.stopTime = "10";

cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";
cfg.currentSignalName = "";

cfg.randomSeed = 1;
cfg.maxIterations = 20;
cfg.numCandidates = 16;
cfg.stopOnFirstPass = true;
cfg.useParallel = false;
cfg.evaluateBaseline = true;

cfg.initialPid = [];
cfg.initialPids = [];
cfg.initialCandidate = [];

cfg.bounds = struct();
cfg.bounds.Kp = [0, 200];
cfg.bounds.Ki = [0, 200];
cfg.bounds.Kd = [0, 50];
cfg.bounds.N = [1, 1000];

cfg.search = struct();
cfg.search.initialScale = 0.35;
cfg.search.minScale = 0.03;
cfg.search.scaleDecay = 0.82;
cfg.search.eliteCount = 4;
cfg.search.randomFraction = 0.35;

rootDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
cfg.ai = struct();
cfg.ai.enabled = false;
cfg.ai.mode = "none";
cfg.ai.sourceLabel = "";
cfg.ai.suggestFcn = [];
cfg.ai.candidatesPerIteration = 4;
cfg.ai.maxHistoryRecords = 12;
cfg.ai.failOnError = false;
cfg.ai.api = struct();
cfg.ai.api.baseUrl = "";
cfg.ai.api.model = "";
cfg.ai.api.apiKeyEnvVar = "PID_AI_API_KEY";
cfg.ai.api.temperature = 0.25;
cfg.ai.api.maxTokens = 2000;
cfg.ai.api.timeoutSeconds = 120;
cfg.ai.local = struct();
cfg.ai.local.pythonExe = "python";
cfg.ai.local.scriptPath = fullfile(rootDir, "examples", "local_ai_pid_provider.py");
cfg.ai.local.runnerPath = fullfile(rootDir, "local_pid_gateway", "local_ai_runner.py");
cfg.ai.local.timeoutSeconds = 120;

cfg.metrics = struct();
cfg.metrics.settlingBand = 0.02;
cfg.metrics.tailFraction = 0.1;
cfg.metrics.maxAbsOutput = 1e6;
cfg.metrics.maxAbsErrorForStable = 1e6;
cfg.metrics.controlUpperLimit = inf;
cfg.metrics.controlSaturationTolerance = 1e-3;

cfg.targets = struct();
cfg.targets.overshootPctMax = 10;
cfg.targets.settlingTimeMax = 5;
cfg.targets.steadyStateErrorAbsMax = 0.02;
cfg.targets.iaeMax = inf;
cfg.targets.iseMax = inf;
cfg.targets.itaeMax = inf;
cfg.targets.maxAbsControlMax = inf;
cfg.targets.controlEnergyMax = inf;
cfg.targets.maxAbsCurrentMax = inf;
cfg.targets.outputRippleMax = inf;
cfg.targets.controlSaturationFractionMax = inf;

cfg.weights = struct();
cfg.weights.iae = 1.0;
cfg.weights.ise = 0.25;
cfg.weights.itae = 0.5;
cfg.weights.overshootPct = 0.2;
cfg.weights.settlingTime = 0.5;
cfg.weights.steadyStateError = 10.0;
cfg.weights.controlEnergy = 0.001;
cfg.weights.maxAbsControl = 0.01;
cfg.weights.maxAbsCurrent = 0.01;
cfg.weights.outputRipple = 1.0;
cfg.weights.controlSaturationFraction = 1.0;
cfg.weights.failurePenalty = 1e6;

cfg.logging = struct();
cfg.logging.outputDir = fullfile(pwd, "pid_tuning_runs");
cfg.logging.runId = "";
cfg.logging.runDir = "";
cfg.logging.currentStatusFile = "";
cfg.logging.historyFile = "";
cfg.logging.bestResultFile = "";
cfg.logging.configFile = "";
cfg.logging.saveMat = true;
cfg.logging.saveCsv = true;
cfg.logging.saveRealtimeJson = true;
end

