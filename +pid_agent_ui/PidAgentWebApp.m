classdef PidAgentWebApp < handle
    %PIDAGENTWEBAPP Host the PID web console inside a MATLAB UI figure.

    properties (SetAccess = private)
        UIFigure
        HTML
        ModelContext = struct()
        BridgeReady = false
        GatewayReady = false
        GatewayError = ""
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
                case "GatewayStatus"
                    data = event.HTMLEventData;
                    app.GatewayReady = isstruct(data) && isfield(data, "ok") && logical(data.ok);
                    if isstruct(data) && isfield(data, "error")
                        app.GatewayError = string(data.error);
                    else
                        app.GatewayError = "";
                    end
                case "GatewayRequest"
                    app.forwardGatewayRequest(event.HTMLEventData);
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

        function forwardGatewayRequest(app, data)
            response = struct("id", "", "ok", false, ...
                "payload", struct(), "error", "Invalid gateway request.", ...
                "statusCode", 0);
            if ~isstruct(data) || ~isfield(data, "id") || ~isfield(data, "path")
                sendEventToHTMLSource(app.HTML, ...
                    "PidAgentGatewayResponse", response);
                return;
            end

            response.id = string(data.id);
            requestPath = string(data.path);
            if ~startsWith(requestPath, "/api/") || contains(requestPath, "..")
                response.error = "Only local /api/ requests are allowed.";
                sendEventToHTMLSource(app.HTML, ...
                    "PidAgentGatewayResponse", response);
                return;
            end

            method = "GET";
            if isfield(data, "method")
                method = upper(string(data.method));
            end
            actionTokens = regexp(char(requestPath), ...
                '^/api/pid/jobs/([A-Za-z0-9_-]+)/(apply|rollback)$', ...
                'tokens', 'once');
            if method == "POST" && ~isempty(actionTokens)
                response = app.performModelAction(response, ...
                    string(actionTokens{1}), string(actionTokens{2}));
                sendEventToHTMLSource(app.HTML, ...
                    "PidAgentGatewayResponse", response);
                return;
            end

            url = "http://127.0.0.1:8788" + requestPath;
            try
                body = struct();
                if isfield(data, "body") && ~isempty(data.body)
                    body = data.body;
                end
                [payload, statusCode, statusText] = ...
                    pid_agent_ui.sendGatewayHttpRequest(method, url, body);
                response.payload = payload;
                response.statusCode = statusCode;
                if statusCode >= 200 && statusCode < 300
                    response.ok = true;
                    response.error = "";
                else
                    response.error = app.gatewayErrorMessage( ...
                        payload, statusCode, statusText);
                end
            catch exception
                response.error = string(exception.message);
            end
            sendEventToHTMLSource(app.HTML, ...
                "PidAgentGatewayResponse", response);
        end

        function response = performModelAction(~, response, jobId, action)
            rootDir = fileparts(fileparts(mfilename("fullpath")));
            runDir = fullfile(rootDir, "pid_tuning_runs", jobId);
            try
                if ~isfolder(runDir)
                    error("PIDAgent:JobNotFound", "Tuning job does not exist: %s", jobId);
                end
                manifestPath = fullfile(runDir, "apply_manifest.json");
                if action == "apply"
                    if isfile(manifestPath)
                        error("PIDAgent:AlreadyApplied", ...
                            "This result is already applied. Roll it back before applying again.");
                    end
                    statusPath = fullfile(runDir, "current_status.json");
                    if ~isfile(statusPath)
                        error("PIDAgent:JobNotCompleted", ...
                            "Tuning status is missing; parameters cannot be applied.");
                    end
                    jobStatus = jsondecode(fileread(statusPath));
                    if ~isfield(jobStatus, "status") || string(jobStatus.status) ~= "completed"
                        error("PIDAgent:JobNotCompleted", ...
                            "The tuning task is not complete; stage results cannot be applied.");
                    end
                    configPath = fullfile(runDir, "request_config.json");
                    resultPath = fullfile(runDir, "best_result.json");
                    if ~isfile(configPath) || ~isfile(resultPath)
                        error("PIDAgent:ResultMissing", "Tuning configuration or result is missing.");
                    end
                    config = jsondecode(fileread(configPath));
                    best = jsondecode(fileread(resultPath));
                    if ~isfield(best, "kind") || string(best.kind) ~= "bestPassing" || ...
                            ~isfield(best, "result") || ~isfield(best.result, "candidate")
                        error("PIDAgent:ResultNotPassed", ...
                            "Only a result that passes every hard metric can be applied.");
                    end
                    expectedFingerprint = "";
                    if isfield(config, "modelFingerprint")
                        expectedFingerprint = string(config.modelFingerprint);
                    end
                    receipt = pid_tuning_core.applyPidCandidateToModel( ...
                        config.modelPath, config.pidBlocks, ...
                        best.result.candidate, runDir, expectedFingerprint);
                else
                    if ~isfile(manifestPath)
                        error("PIDAgent:RollbackUnavailable", ...
                            "This tuning job has no applied parameters to roll back.");
                    end
                    receipt = pid_tuning_core.rollbackPidModel(manifestPath);
                    archivePath = fullfile(runDir, ...
                        "apply_manifest_rolled_back_" + string(posixtime(datetime("now"))) + ".json");
                    movefile(manifestPath, archivePath, "f");
                    receipt.archivedManifestPath = string(archivePath);
                end
                response.ok = true;
                response.payload = receipt;
                response.error = "";
                response.statusCode = 200;
            catch exception
                response.ok = false;
                response.statusCode = 400;
                response.error = string(exception.message);
                response.payload = struct("error", string(exception.message), ...
                    "message", string(exception.message), ...
                    "code", string(exception.identifier));
            end
        end

        function message = gatewayErrorMessage(~, payload, statusCode, statusText)
            message = "";
            if isstruct(payload)
                if isfield(payload, "message") && strlength(string(payload.message)) > 0
                    message = string(payload.message);
                elseif isfield(payload, "error") && strlength(string(payload.error)) > 0
                    message = string(payload.error);
                end
                if isfield(payload, "requestId") && strlength(string(payload.requestId)) > 0
                    message = message + "（请求 " + string(payload.requestId) + "）";
                end
            end
            if strlength(message) == 0
                message = "HTTP " + statusCode + " " + statusText;
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
