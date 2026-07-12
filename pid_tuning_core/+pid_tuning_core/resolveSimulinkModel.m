function [modelName, resolvedPath, modelDir] = resolveSimulinkModel(modelInput)
%RESOLVESIMULINKMODEL Resolve and validate a .slx/.mdl path or MATLAB model name.

modelText = strtrim(string(modelInput));
modelText = strip(modelText, '"');
if strlength(modelText) == 0
    error("A Simulink model path or model name is required.");
end

if startsWith(lower(modelText), "file:///")
    modelText = extractAfter(modelText, 8);
    modelText = replace(modelText, "%20", " ");
end

if isfile(modelText)
    [modelDir, modelName, extension] = fileparts(char(modelText));
    localValidateExtension(extension, modelText);
    resolvedPath = char(modelText);
    modelName = string(modelName);
    modelDir = string(modelDir);
    return;
end

[inputDir, inputName, extension] = fileparts(char(modelText));
if strlength(string(inputDir)) > 0 || strlength(string(extension)) > 0
    error("Model file does not exist: %s", modelText);
end

resolved = which(char(modelText));
if isempty(resolved)
    error("Model was not found on the MATLAB path: %s", modelText);
end

[modelDir, resolvedName, extension] = fileparts(resolved);
localValidateExtension(extension, resolved);
modelName = string(resolvedName);
resolvedPath = resolved;
modelDir = string(modelDir);
end

function localValidateExtension(extension, source)
extension = lower(string(extension));
if ~ismember(extension, [".slx", ".mdl"])
    error("The selected file must be a .slx or .mdl model. Received: %s", source);
end
end
