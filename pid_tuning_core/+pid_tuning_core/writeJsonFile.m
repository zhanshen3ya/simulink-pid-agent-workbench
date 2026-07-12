function writeJsonFile(filePath, payload)
%WRITEJSONFILE Atomically write a JSON file using UTF-8.

payload = pid_tuning_core.jsonSafe(payload);
text = jsonencode(payload, "PrettyPrint", true);
tmpPath = char(string(filePath) + ".tmp");

fid = fopen(tmpPath, "w", "n", "UTF-8");
if fid < 0
    warning("Could not write JSON file: %s", filePath);
    return;
end
fprintf(fid, "%s", text);
fclose(fid);
movefile(tmpPath, filePath, "f");
end
