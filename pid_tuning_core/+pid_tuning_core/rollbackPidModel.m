function receipt = rollbackPidModel(manifestPath)
%ROLLBACKPIDMODEL Restore PID parameters recorded before an apply operation.

if ~isfile(manifestPath)
    error("Apply manifest does not exist: %s", manifestPath);
end
manifest = jsondecode(fileread(manifestPath));
[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(manifest.modelPath);
if isfield(manifest, "appliedModelFingerprint") && ...
        strlength(string(manifest.appliedModelFingerprint)) > 0
    currentFingerprint = pid_tuning_core.fileSha256(resolvedPath);
    if currentFingerprint ~= lower(string(manifest.appliedModelFingerprint))
        error("PIDAgent:ModelChangedAfterApply", ...
            "The model file changed after PID parameters were applied. Automatic rollback was stopped to protect the newer changes.");
    end
end
wasLoaded = bdIsLoaded(modelName);
load_system(resolvedPath);
if wasLoaded && strcmpi(get_param(modelName, "Dirty"), "on")
    error("Model %s has unsaved changes. Save the model before rolling back PID parameters.", modelName);
end
original = manifest.original;
if iscell(original)
    original = [original{:}];
end
for index = 1:numel(original)
    blockPath = string(original(index).path);
    if string(bdroot(char(blockPath))) ~= string(modelName)
        error("Rollback PID block does not belong to the target model: %s", blockPath);
    end
    set_param(blockPath, "P", string(original(index).P), ...
        "I", string(original(index).I), "D", string(original(index).D));
    if isfield(original(index), "N") && strlength(string(original(index).N)) > 0
        try
            set_param(blockPath, "N", string(original(index).N));
        catch
        end
    end
end
save_system(modelName, resolvedPath);
receipt = struct("rolledBack", true, "modelPath", string(resolvedPath), ...
    "manifestPath", string(manifestPath), ...
    "modelFingerprint", pid_tuning_core.fileSha256(resolvedPath), ...
    "rolledBackAt", string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX")));
end