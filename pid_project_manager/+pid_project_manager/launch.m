function app = launch(modelFile)
%LAUNCH Open PID Agent Manager for a Simulink model.
if nargin < 1 || strlength(string(modelFile)) == 0
    modelFile = string(bdroot);
end
if strlength(string(modelFile)) == 0
    error("PIDAgent:NoModel", "Open a Simulink model before launching PID Agent Manager.");
end
existing = getappdata(0, "PidAgentManagerApp");
if ~isempty(existing) && isvalid(existing)
    delete(existing);
end
app = pid_project_manager.PidAgentManagerApp(string(modelFile));
setappdata(0, "PidAgentManagerApp", app);
end