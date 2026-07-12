function saveIterationLog(records, state, cfg)
%SAVEITERATIONLOG Save MAT and CSV logs for each iteration.

if ~exist(cfg.logging.outputDir, "dir")
    mkdir(cfg.logging.outputDir);
end

iteration = records(1).iteration;

if cfg.logging.saveMat
    matFile = fullfile(cfg.logging.outputDir, sprintf("iteration_%03d.mat", iteration));
    save(matFile, "records", "state", "cfg");
end

if cfg.logging.saveCsv
    rows = repmat(struct(), numel(records), 1);
    for idx = 1:numel(records)
        c = pid_tuning_core.normalizePidCandidate(records(idx).candidate, cfg);
        m = records(idx).metrics;
        v = records(idx).validation;

        rows(idx).iteration = records(idx).iteration;
        rows(idx).candidateIndex = records(idx).candidateIndex;

        for pidIdx = 1:numel(c.pids)
            pid = c.pids(pidIdx);
            prefix = string(matlab.lang.makeValidName(char(pid.name)));
            rows(idx).(char(prefix + "_Kp")) = pid.Kp;
            rows(idx).(char(prefix + "_Ki")) = pid.Ki;
            rows(idx).(char(prefix + "_Kd")) = pid.Kd;
            rows(idx).(char(prefix + "_N")) = pid.N;
        end

        rows(idx).Kp = c.Kp;
        rows(idx).Ki = c.Ki;
        rows(idx).Kd = c.Kd;
        rows(idx).N = c.N;
        rows(idx).passed = v.passed;
        rows(idx).score = v.score;
        rows(idx).failures = strjoin(v.failures, "|");
        rows(idx).overshootPct = m.overshootPct;
        rows(idx).settlingTime = m.settlingTime;
        rows(idx).steadyStateError = m.steadyStateError;
        rows(idx).iae = m.iae;
        rows(idx).ise = m.ise;
        rows(idx).itae = m.itae;
        rows(idx).controlEnergy = m.controlEnergy;
        rows(idx).maxAbsControl = m.maxAbsControl;
    end

    tableRows = struct2table(rows);
    csvFile = fullfile(cfg.logging.outputDir, sprintf("iteration_%03d.csv", iteration));
    writetable(tableRows, csvFile);
end
end
