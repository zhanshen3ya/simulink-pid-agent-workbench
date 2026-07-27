function run_baseline_to_json(requestPath, outputPath)
%RUN_BASELINE_TO_JSON JSON bridge used by autopid.runners.MatlabRunner.
request = jsondecode(fileread(requestPath));
result = run_baseline(request);
fileId = fopen(outputPath, "w", "n", "UTF-8");
if fileId < 0
    error("AutoPID:JsonWrite", "Cannot open output path: %s", outputPath);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, jsonencode(result, "PrettyPrint", true), "char");
end
