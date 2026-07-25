classdef PidAgentWebApp < handle
    %PIDAGENTWEBAPP Host the PID web console inside a MATLAB UI figure.

    properties (SetAccess = private)
        UIFigure
        HTML
        ModelContext = struct()
        BridgeReady = false
    end

    methods
        function app = PidAgentWebApp(context)
            app.createComponents();
            app.updateContext(context);
        end

        function updateContext(app, context)
            context.embedded = true;
            context.apiBaseUrl = "http://127.0.0.1:8788";
            app.ModelContext = context;
            app.UIFigure.Name = "PID Agent - " + string(context.modelName);
            app.HTML.Data = context;
        end

        function showView(app, viewName)
            if isempty(app.HTML) || ~isvalid(app.HTML)
                return;
            end
            sendEventToHTMLSource(app.HTML, "PidAgentNavigate", ...
                struct("view", string(viewName)));
        end

        function focus(app)
            if isempty(app.UIFigure) || ~isvalid(app.UIFigure)
                return;
            end
            app.UIFigure.Visible = "on";
            app.UIFigure.WindowState = "normal";
            figure(app.UIFigure);
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
            if isappdata(0, "PidAgentWebApp")
                rmappdata(0, "PidAgentWebApp");
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            rootDir = fileparts(fileparts(mfilename("fullpath")));
            htmlPath = fullfile(rootDir, "local_pid_gateway", "web", ...
                "index_custom.html");
            app.UIFigure = uifigure("Name", "PID Agent", ...
                "Position", [80, 70, 1500, 860], ...
                "CloseRequestFcn", @(~, ~) delete(app));
            layout = uigridlayout(app.UIFigure, [1, 1]);
            layout.Padding = [0, 0, 0, 0];
            layout.RowSpacing = 0;
            layout.ColumnSpacing = 0;
            app.HTML = uihtml(layout, "HTMLSource", htmlPath, ...
                "HTMLEventReceivedFcn", @(~, event) app.handleHtmlEvent(event));
        end

        function handleHtmlEvent(app, event)
            eventName = string(event.HTMLEventName);
            switch eventName
                case "BridgeReady"
                    app.BridgeReady = true;
                case "SyncCurrentModel"
                    [context, confirmed] = pid_agent_ui.prepareCurrentContext();
                    if confirmed
                        app.updateContext(context);
                    end
                case "LocatePid"
                    data = event.HTMLEventData;
                    if isstruct(data) && isfield(data, "path")
                        app.locatePid(string(data.path));
                    end
                case "OpenManager"
                    pid_agent_ui.openManager();
            end
        end

        function locatePid(~, blockPath)
            if strlength(blockPath) == 0
                return;
            end
            try
                modelName = string(bdroot(char(blockPath)));
                open_system(modelName);
                hilite_system(blockPath, "find");
            catch exception
                warning("PIDAgent:LocateFailed", ...
                    "Could not locate PID block %s: %s", ...
                    blockPath, exception.message);
            end
        end
    end
end
