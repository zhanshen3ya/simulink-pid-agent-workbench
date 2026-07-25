function app = openHistory()
%OPENHISTORY Open the embedded console and show tuning history.

app = pid_agent_ui.launch("current");
if ~isempty(app) && isvalid(app)
    app.showView("history");
end
end
