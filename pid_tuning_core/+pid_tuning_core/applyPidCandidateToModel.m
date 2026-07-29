function receipt = applyPidCandidateToModel(modelPath, pidBlocks, candidate, runDir, expectedFingerprint)
%APPLYPIDCANDIDATETOMODEL Persist a validated candidate with rollback data.

if nargin < 5
    expectedFingerprint = "";
end

[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(modelPath);
beforeFingerprint = pid_tuning_core.fileSha256(resolvedPath);
expectedFingerprint = lower(string(expectedFingerprint));
if strlength(expectedFingerprint) > 0 && beforeFingerprint ~= expectedFingerprint
    error("PIDAgent:ModelChangedSinceTuning", ...
        "The model file changed after this tuning task started. Run a new tuning task before applying parameters.");
end
wasLoaded = bdIsLoaded(modelName);
load_system(resolvedPath);
if wasLoaded && strcmpi(get_param(modelName, "Dirty"), "on")
    error("Model %s has unsaved changes. Save the model before applying tuned PID parameters.", modelName);
end
pids = localCandidatePids(candidate);
if numel(pids) ~= numel(pidBlocks)
    error("Candidate PID count does not match the selected PID blocks.");
end
if ~isfolder(runDir)
    mkdir(runDir);
end

backupPath = fullfile(runDir, "model_before_apply" + string(fileExtension(resolvedPath)));
copyfile(resolvedPath, backupPath, "f");
originalTemplate = struct("path", "", "P", "", "I", "", "D", "", "N", "");
original = repmat(originalTemplate, numel(pidBlocks), 1);
for index = 1:numel(pidBlocks)
    blockPath = string(pidBlocks(index).path);
    if string(bdroot(char(blockPath))) ~= string(modelName)
        error("PID block %s does not belong to model %s.", blockPath, modelName);
    end
    if getSimulinkBlockHandle(blockPath) < 0
        error("PID block does not exist: %s", blockPath);
    end

    original(index).path = blockPath;
    original(index).P = string(get_param(blockPath, "P"));
    original(index).I = string(get_param(blockPath, "I"));
    original(index).D = string(get_param(blockPath, "D"));
    try
        original(index).N = string(get_param(blockPath, "N"));
    catch
        original(index).N = "";
    end
end

try
    for index = 1:numel(pidBlocks)
        blockPath = string(pidBlocks(index).path);
        set_param(blockPath, ...
            "P", num2str(double(pids(index).Kp), 16), ...
            "I", num2str(double(pids(index).Ki), 16), ...
            "D", num2str(double(pids(index).Kd), 16));
        if isfield(pids(index), "N") && isfinite(double(pids(index).N))
            try
                set_param(blockPath, "N", num2str(double(pids(index).N), 16));
            catch
            end
        end
    end
    save_system(modelName, resolvedPath);
catch exception
    localRestoreOriginal(original);
    save_system(modelName, resolvedPath);
    rethrow(exception);
end

manifest = struct();
manifest.schemaVersion = 1;
manifest.appliedAt = string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
manifest.modelName = string(modelName);
manifest.modelPath = string(resolvedPath);
manifest.backupPath = string(backupPath);
manifest.beforeModelFingerprint = beforeFingerprint;
manifest.appliedModelFingerprint = pid_tuning_core.fileSha256(resolvedPath);
manifest.original = original;
manifest.appliedCandidate = candidate;
manifest.pidBlocks = pidBlocks;
manifestPath = fullfile(runDir, "apply_manifest.json");
pid_tuning_core.writeJsonFile(manifestPath, manifest);
receipt = struct("applied", true, "modelPath", string(resolvedPath), ...
    "backupPath", string(backupPath), "manifestPath", string(manifestPath), ...
    "candidate", candidate);
end

function pids = localCandidatePids(candidate)
if ~isstruct(candidate) || ~isfield(candidate, "pids")
    error("Candidate must contain a pids array.");
end
pids = candidate.pids;
if iscell(pids)
    pids = [pids{:}];
end
pids = pids(:);
for index = 1:numel(pids)
    for field = ["Kp", "Ki", "Kd"]
        if ~isfield(pids(index), field) || ~isscalar(pids(index).(field)) || ...
                ~isfinite(double(pids(index).(field)))
            error("Candidate PID %d has an invalid %s value.", index, field);
        end
    end
end
end

function localRestoreOriginal(original)
for index = 1:numel(original)
    set_param(original(index).path, "P", original(index).P, ...
        "I", original(index).I, "D", original(index).D);
    if strlength(original(index).N) > 0
        try
            set_param(original(index).path, "N", original(index).N);
        catch
        end
    end
end
end

function extension = fileExtension(path)
[~, ~, extension] = fileparts(path);
extension = string(extension);
end