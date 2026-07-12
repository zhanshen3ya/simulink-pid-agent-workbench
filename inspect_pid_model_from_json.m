function info = inspect_pid_model_from_json(requestFile, responseFile)
%INSPECT_PID_MODEL_FROM_JSON Inspect a model requested by the local gateway.

request = jsondecode(fileread(requestFile));
if ~isfield(request, "modelPath")
    error("modelPath is required.");
end

originalDir = pwd;
restoreDir = onCleanup(@() cd(originalDir)); %#ok<NASGU>
modelPath = string(request.modelPath);
if isfile(modelPath)
    cd(fileparts(char(modelPath)));
end
info = pid_tuning_core.inspectPidModel(modelPath);
pid_tuning_core.writeJsonFile(responseFile, info);
end
