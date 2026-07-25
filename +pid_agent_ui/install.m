function result = install(persistPath)
%INSTALL Add PID Agent to the MATLAB path and refresh Simulink UI.

arguments
    persistPath (1, 1) logical = true
end
rootDir = string(fileparts(fileparts(mfilename("fullpath"))));
addpath(rootDir);
addpath(fullfile(rootDir, "pid_tuning_core"));
addpath(fullfile(rootDir, "pid_project_manager"));
addpath(fullfile(rootDir, "examples"));

pathSaved = true;
if persistPath
    pathSaved = savepath == 0;
end
if exist("slReloadToolstripConfig", "file") > 0
    slReloadToolstripConfig;
end
if exist("sl_refresh_customizations", "file") > 0
    sl_refresh_customizations;
end

result = struct("root", rootDir, "pathSaved", pathSaved, ...
    "toolstripReloaded", true);
fprintf("PID Agent installed from: %s\n", rootDir);
if ~pathSaved
    warning("PIDAgent:PathNotSaved", ...
        "MATLAB could not save the path. Run addpath('%s') after restart.", rootDir);
end
end
