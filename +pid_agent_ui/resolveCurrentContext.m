function context = resolveCurrentContext()
%RESOLVECURRENTCONTEXT Read the active Simulink model and selected PID blocks.

currentSystem = "";
try
    currentSystem = string(gcs);
catch
end
if strlength(currentSystem) == 0
    error("PIDAgent:NoCurrentSystem", ...
        "Open a Simulink model before starting PID Agent.");
end

modelName = string(bdroot(char(currentSystem)));
if strlength(modelName) == 0 || ~bdIsLoaded(modelName)
    error("PIDAgent:NoModel", "The current Simulink model is not loaded.");
end
if string(get_param(modelName, "BlockDiagramType")) ~= "model"
    error("PIDAgent:LibrarySelected", ...
        "Switch to a Simulink model before starting PID Agent.");
end

modelPath = string(get_param(modelName, "FileName"));
source = modelName;
if strlength(modelPath) > 0
    source = modelPath;
end
modelInfo = pid_tuning_core.inspectPidModel(source);

selectedPidPaths = strings(0, 1);
for index = 1:numel(modelInfo.pidBlocks)
    blockPath = string(modelInfo.pidBlocks(index).path);
    try
        if string(get_param(blockPath, "Selected")) == "on"
            selectedPidPaths(end + 1, 1) = blockPath; %#ok<AGROW>
        end
    catch
    end
end

projectRoot = "";
projectPath = "";
try
    project = currentProject;
    projectRoot = string(project.RootFolder);
    if isprop(project, "ProjectPath")
        projectPath = string(project.ProjectPath);
    end
catch
end

workingDirectory = "";
if strlength(modelPath) > 0
    workingDirectory = string(fileparts(modelPath));
end

context = struct();
context.embedded = true;
context.apiBaseUrl = "http://127.0.0.1:8788";
context.modelName = modelName;
context.modelPath = modelPath;
context.modelDirty = string(get_param(modelName, "Dirty")) == "on";
context.currentSystem = currentSystem;
context.selectedPidPaths = selectedPidPaths;
context.modelInfo = modelInfo;
context.workingDirectory = workingDirectory;
context.projectRoot = projectRoot;
context.projectPath = projectPath;
context.initialView = "run";
end
