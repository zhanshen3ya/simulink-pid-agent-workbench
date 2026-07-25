function health = ensureGateway()
%ENSUREGATEWAY Start or reuse the local PID gateway.

rootDir = string(fileparts(fileparts(mfilename("fullpath"))));
health = localHealth();
if ~isempty(health)
    localValidateRoot(health, rootDir);
    return;
end

scriptPath = fullfile(rootDir, "local_pid_gateway", "start_gateway_hidden.ps1");
if ~isfile(scriptPath)
    error("PIDAgent:MissingGatewayLauncher", ...
        "Gateway launcher does not exist: %s", scriptPath);
end

startInfo = System.Diagnostics.ProcessStartInfo;
startInfo.FileName = "powershell.exe";
startInfo.Arguments = sprintf(...
    '-NoProfile -ExecutionPolicy Bypass -File "%s"', scriptPath);
startInfo.WorkingDirectory = char(rootDir);
startInfo.UseShellExecute = false;
startInfo.CreateNoWindow = true;
process = System.Diagnostics.Process.Start(startInfo);
setappdata(0, "PidAgentGatewayProcess", process);

startedAt = tic;
while toc(startedAt) < 30
    pause(0.25);
    drawnow limitrate;
    health = localHealth();
    if ~isempty(health)
        localValidateRoot(health, rootDir);
        return;
    end
    if process.HasExited
        break;
    end
end

logPath = fullfile(rootDir, "local_pid_gateway", "gateway_embedded.log");
error("PIDAgent:GatewayStartFailed", ...
    "PID gateway did not start. Check: %s", logPath);
end

function health = localHealth()
health = [];
try
    options = weboptions("Timeout", 2, "ContentType", "json");
    response = webread("http://127.0.0.1:8788/api/health", options);
    if isstruct(response) && isfield(response, "ok") && logical(response.ok)
        health = response;
    end
catch
end
end

function localValidateRoot(health, expectedRoot)
if ~isfield(health, "root")
    return;
end
actual = localNormalizePath(string(health.root));
expected = localNormalizePath(expectedRoot);
if actual ~= expected
    error("PIDAgent:GatewayRootConflict", ...
        "Port 8788 is already used by another PID Agent workspace: %s", actual);
end
end

function value = localNormalizePath(value)
value = lower(replace(strip(string(value)), "/", "\"));
value = strip(value, "right", "\");
end
