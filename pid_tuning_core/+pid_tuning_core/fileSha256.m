function value = fileSha256(filePath)
%FILESHA256 Return a lowercase SHA-256 digest for a file.

filePath = string(filePath);
if ~isfile(filePath)
    error("PIDAgent:FileNotFound", "File does not exist: %s", filePath);
end
fid = fopen(filePath, "rb");
if fid < 0
    error("PIDAgent:FileReadFailed", "Cannot read file: %s", filePath);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
digest = java.security.MessageDigest.getInstance("SHA-256");
while true
    bytes = fread(fid, 1024 * 1024, "*uint8");
    if isempty(bytes)
        break;
    end
    digest.update(typecast(bytes(:), "int8"));
end
hashBytes = typecast(digest.digest(), "uint8");
value = lower(string(reshape(dec2hex(hashBytes, 2).', 1, [])));
end