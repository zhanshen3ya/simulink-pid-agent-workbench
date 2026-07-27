function scan_model_to_json(requestPath, outputPath)
%SCAN_MODEL_TO_JSON JSON bridge used by autopid.runners.MatlabRunner.
request = jsondecode(fileread(requestPath));
result = scan_model(string(request.model_file));
localWriteJson(outputPath, result);
end

function localWriteJson(path, value)
fileId = fopen(path, "w", "n", "UTF-8");
if fileId < 0
    error("AutoPID:JsonWrite", "Cannot open output path: %s", path);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, jsonencode(value, "PrettyPrint", true), "char");
end
