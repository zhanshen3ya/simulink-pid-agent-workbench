function cfg = prepareRunLogging(cfg)
%PREPARERUNLOGGING Create a per-run directory and JSON log paths.

if ~isfield(cfg, "logging") || isempty(cfg.logging)
    cfg.logging = struct();
end

if ~isfield(cfg.logging, "outputDir") || strlength(string(cfg.logging.outputDir)) == 0
    cfg.logging.outputDir = fullfile(pwd, "pid_tuning_runs");
end

if ~exist(cfg.logging.outputDir, "dir")
    mkdir(cfg.logging.outputDir);
end

if ~isfield(cfg.logging, "runId") || strlength(string(cfg.logging.runId)) == 0
    cfg.logging.runId = "job_" + string(datetime("now", "Format", "yyyyMMdd_HHmmss"));
end

if ~isfield(cfg.logging, "runDir") || strlength(string(cfg.logging.runDir)) == 0
    cfg.logging.runDir = fullfile(cfg.logging.outputDir, char(cfg.logging.runId));
end

if ~exist(cfg.logging.runDir, "dir")
    mkdir(cfg.logging.runDir);
end

cfg.logging.currentStatusFile = fullfile(cfg.logging.runDir, "current_status.json");
cfg.logging.historyFile = fullfile(cfg.logging.runDir, "history.jsonl");
cfg.logging.bestResultFile = fullfile(cfg.logging.runDir, "best_result.json");
cfg.logging.configFile = fullfile(cfg.logging.runDir, "config.json");

cfgForJson = cfg;
if isfield(cfgForJson, "ai")
    cfgForJson = rmfield(cfgForJson, "ai");
end
pid_tuning_core.writeJsonFile(cfg.logging.configFile, cfgForJson);
end
