function app = openManager()
%OPENMANAGER Open the multi-PID manager for the current model.

[context, confirmed] = pid_agent_ui.prepareCurrentContext();
if ~confirmed
    app = [];
    return;
end
app = pid_project_manager.launch(context.modelPath);
end
