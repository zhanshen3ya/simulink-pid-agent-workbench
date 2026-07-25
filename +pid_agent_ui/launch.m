function app = launch(mode)
%LAUNCH Open the embedded PID tuning console for the current model.

arguments
    mode (1, 1) string = "current"
end
[context, confirmed] = pid_agent_ui.prepareCurrentContext();
if ~confirmed
    app = [];
    return;
end

if mode == "selected" && numel(context.selectedPidPaths) > 2
    app = pid_project_manager.launch(context.modelPath);
    return;
end

pid_agent_ui.ensureGateway();
existing = getappdata(0, "PidAgentWebApp");
if ~isempty(existing) && isvalid(existing)
    app = existing;
    app.updateContext(context);
    app.focus();
    return;
end

app = pid_agent_ui.PidAgentWebApp(context);
setappdata(0, "PidAgentWebApp", app);
end
