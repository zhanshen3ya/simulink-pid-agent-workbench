function app = launchFromLibrary()
%LAUNCHFROMLIBRARY Select a loaded model and open PID Agent Manager.
blockDiagrams = string(find_system("SearchDepth", 0, "Type", "block_diagram"));
models = strings(0, 1);
for index = 1:numel(blockDiagrams)
    try
        if string(get_param(blockDiagrams(index), "BlockDiagramType")) == "model"
            models(end + 1, 1) = blockDiagrams(index); %#ok<AGROW>
        end
    catch
    end
end
models = models(models ~= "pid_agent_lib");
if isempty(models)
    error("PIDAgent:NoModel", "Open the target Simulink model first.");
elseif isscalar(models)
    selected = models;
else
    [choice, confirmed] = listdlg("PromptString", "Select the model to tune:", ...
        "SelectionMode", "single", "ListString", cellstr(models));
    if ~confirmed
        app = [];
        return;
    end
    selected = models(choice);
end
open_system(selected);
app = pid_agent_ui.launch("current");
end
