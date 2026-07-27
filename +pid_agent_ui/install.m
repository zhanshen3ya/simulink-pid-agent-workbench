function result = install(persistPath)
%INSTALL Add PID Agent to the MATLAB path and refresh Simulink UI.

arguments
    persistPath (1, 1) logical = true
end
rootDir = string(fileparts(fileparts(mfilename("fullpath"))));
localAddProjectPaths(rootDir);

replacedComponentPath = "";
toolstripReloaded = false;
if exist("slReloadToolstripConfig", "file") > 0
    slReloadToolstripConfig;
    toolstripReloaded = true;
end

if exist("slLoadedToolstripComponents", "file") > 0
    components = slLoadedToolstripComponents;
    for index = 1:numel(components)
        if string(components(index).name) ~= "pidAgent"
            continue;
        end
        componentPath = string(components(index).path);
        if localNormalizePath(componentPath) ~= localNormalizePath(rootDir)
            replacedComponentPath = componentPath;
            slPersistToolstripComponent("pidAgent", false);
            slDestroyToolstripComponent("pidAgent");
            localAddProjectPaths(rootDir);
            slReloadToolstripConfig;
        end
        break;
    end
end

if exist("sl_refresh_customizations", "file") > 0
    sl_refresh_customizations;
end

loadedComponentPath = "";
if exist("slLoadedToolstripComponents", "file") > 0
    components = slLoadedToolstripComponents;
    for index = 1:numel(components)
        if string(components(index).name) == "pidAgent"
            loadedComponentPath = string(components(index).path);
            break;
        end
    end
    if localNormalizePath(loadedComponentPath) ~= localNormalizePath(rootDir)
        error("PIDAgent:ToolstripLoadFailed", ...
            "PID Agent Toolstrip loaded from an unexpected path: %s", ...
            loadedComponentPath);
    end
    slPersistToolstripComponent("pidAgent", persistPath);
end

pathSaved = true;
if persistPath
    pathSaved = savepath == 0;
end

result = struct("root", rootDir, "pathSaved", pathSaved, ...
    "toolstripReloaded", toolstripReloaded, ...
    "loadedComponentPath", loadedComponentPath, ...
    "replacedComponentPath", replacedComponentPath);
fprintf("PID Agent installed from: %s\n", rootDir);
if strlength(replacedComponentPath) > 0
    fprintf("Replaced conflicting Toolstrip component from: %s\n", ...
        replacedComponentPath);
end
if ~pathSaved
    warning("PIDAgent:PathNotSaved", ...
        "MATLAB could not save the path. Run addpath('%s') after restart.", rootDir);
end
end

function localAddProjectPaths(rootDir)
addpath(rootDir, "-begin");
addpath(fullfile(rootDir, "pid_tuning_core"), "-begin");
addpath(fullfile(rootDir, "pid_project_manager"), "-begin");
addpath(fullfile(rootDir, "examples"), "-begin");
end

function value = localNormalizePath(value)
value = lower(replace(strip(string(value)), "/", "\"));
value = strip(value, "right", "\");
end
