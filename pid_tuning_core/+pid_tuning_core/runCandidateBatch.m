function simResults = runCandidateBatch(candidates, cfg)
%RUNCANDIDATEBATCH Simulate every PID candidate.

simInputs(numel(candidates), 1) = Simulink.SimulationInput(cfg.modelName);

for idx = 1:numel(candidates)
    simIn = Simulink.SimulationInput(cfg.modelName);
    simIn = simIn.setModelParameter("StopTime", char(cfg.stopTime));
    simIn = simIn.setModelParameter("FastRestart", "on");
    simIn = pid_tuning_core.applyPidCandidate(simIn, cfg.pidBlocks, candidates(idx));
    simInputs(idx) = simIn;
end

simResults = repmat(struct("success", false, "output", [], "error", ""), numel(candidates), 1);

if cfg.useParallel
    rawOutputs = parsim(simInputs, "ShowProgress", "off", "TransferBaseWorkspaceVariables", "on");
else
    rawOutputs = cell(numel(simInputs), 1);
    for idx = 1:numel(simInputs)
        try
            rawOutputs{idx} = sim(simInputs(idx));
        catch err
            simResults(idx).success = false;
            simResults(idx).output = [];
            simResults(idx).error = string(err.message);
        end
    end
end

for idx = 1:numel(candidates)
    try
        if ~cfg.useParallel && isempty(rawOutputs{idx})
            continue;
        end

        if cfg.useParallel
            out = rawOutputs(idx);
        else
            out = rawOutputs{idx};
        end
        errMsg = "";
        try
            errMsg = string(out.ErrorMessage);
        catch
        end
        simResults(idx).success = strlength(errMsg) == 0;
        simResults(idx).output = out;
        simResults(idx).error = errMsg;
    catch err
        simResults(idx).success = false;
        simResults(idx).output = [];
        simResults(idx).error = string(err.message);
    end
end
end
