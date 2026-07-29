function apply_pid_job_from_json(requestFile, responseFile)
%APPLY_PID_JOB_FROM_JSON Bridge apply and rollback actions for the local gateway.

request = jsondecode(fileread(requestFile));
action = lower(string(request.action));
if action == "apply"
    expectedFingerprint = "";
    if isfield(request, "expectedModelFingerprint")
        expectedFingerprint = string(request.expectedModelFingerprint);
    end
    receipt = pid_tuning_core.applyPidCandidateToModel( ...
        request.modelPath, request.pidBlocks, request.candidate, ...
        request.runDir, expectedFingerprint);
elseif action == "rollback"
    receipt = pid_tuning_core.rollbackPidModel(request.manifestPath);
else
    error("Unsupported PID model action: %s", action);
end
pid_tuning_core.writeJsonFile(responseFile, receipt);
end