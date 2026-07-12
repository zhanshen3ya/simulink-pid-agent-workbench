function simIn = applyPidCandidate(simIn, pidBlocks, candidate)
%APPLYPIDCANDIDATE Apply PID parameters to a SimulationInput object.

if isstruct(pidBlocks)
    candidate = pid_tuning_core.normalizePidCandidate(candidate, struct("pidBlocks", pidBlocks));
else
    legacyBlock.path = string(pidBlocks);
    legacyBlock.name = "pid1";
    legacyBlock.initialPid = struct("Kp", candidate.Kp, "Ki", candidate.Ki, "Kd", candidate.Kd, "N", candidate.N);
    pidBlocks = legacyBlock;
    candidate = pid_tuning_core.normalizePidCandidate(candidate, struct("pidBlocks", pidBlocks));
end

for idx = 1:numel(pidBlocks)
    blockPath = char(pidBlocks(idx).path);
    pid = candidate.pids(idx);

    simIn = simIn.setBlockParameter(blockPath, "P", num2str(pid.Kp, 16));
    simIn = simIn.setBlockParameter(blockPath, "I", num2str(pid.Ki, 16));
    simIn = simIn.setBlockParameter(blockPath, "D", num2str(pid.Kd, 16));

    if isfield(pid, "N")
        try
            simIn = simIn.setBlockParameter(blockPath, "N", num2str(pid.N, 16));
        catch
            % Some PID block variants do not expose the filter coefficient.
        end
    end
end
end
