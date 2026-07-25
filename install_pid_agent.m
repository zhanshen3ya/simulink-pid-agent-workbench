function result = install_pid_agent(persistPath)
%INSTALL_PID_AGENT Install the Simulink PID Agent Toolstrip integration.

if nargin < 1
    persistPath = true;
end
result = pid_agent_ui.install(logical(persistPath));
end
