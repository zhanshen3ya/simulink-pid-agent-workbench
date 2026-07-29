classdef PidAgentManagerApp < handle
    %PIDAGENTMANAGERAPP Select, group, order, and execute PID tuning units.

    properties (SetAccess = private)
        UIFigure
        Catalog = struct()
        Plan = struct()
    end

    properties (Access = private)
        ModelField
        ControllerTable
        StatusArea
        RunButton
        StopTimeField
        IterationsField
        CandidatesField
        SelectedRow = 1
    end

    methods
        function app = PidAgentManagerApp(modelFile)
            app.createComponents();
            app.ModelField.Value = char(modelFile);
            app.scanModel();
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
            if isappdata(0, "PidAgentManagerApp")
                rmappdata(0, "PidAgentManagerApp");
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure("Name", "PID 调参管理器", ...
                "Position", [120, 120, 1380, 720], ...
                "CloseRequestFcn", @(~, ~) delete(app));
            root = uigridlayout(app.UIFigure, [4, 1]);
            root.RowHeight = {42, 42, "1x", 92};
            root.Padding = [12, 12, 12, 12];
            root.RowSpacing = 8;

            header = uigridlayout(root, [1, 5]);
            header.Layout.Row = 1;
            header.ColumnWidth = {64, "1x", 88, 88, 104};
            uilabel(header, "Text", "模型", "HorizontalAlignment", "right");
            app.ModelField = uieditfield(header, "text");
            uibutton(header, "Text", "扫描", ...
                "ButtonPushedFcn", @(~, ~) app.scanModel());
            uibutton(header, "Text", "定位", ...
                "ButtonPushedFcn", @(~, ~) app.locateSelected());
            uibutton(header, "Text", "清除高亮", ...
                "ButtonPushedFcn", @(~, ~) app.clearHighlight());

            actions = uigridlayout(root, [1, 12]);
            actions.Layout.Row = 2;
            actions.ColumnWidth = {108, 108, 108, 108, 108, 68, 68, 54, 62, 54, 70, "1x"};
            uibutton(actions, "Text", "按拓扑分组", ...
                "ButtonPushedFcn", @(~, ~) app.autoGroup());
            uibutton(actions, "Text", "全选可执行", ...
                "ButtonPushedFcn", @(~, ~) app.selectExecutable());
            uibutton(actions, "Text", "取消全选", ...
                "ButtonPushedFcn", @(~, ~) app.clearSelection());
            uibutton(actions, "Text", "保存计划", ...
                "ButtonPushedFcn", @(~, ~) app.savePlan());
            app.RunButton = uibutton(actions, "Text", "顺序执行", ...
                "ButtonPushedFcn", @(~, ~) app.runPlan());
            uilabel(actions, "Text", "停止时间", "HorizontalAlignment", "right");
            app.StopTimeField = uieditfield(actions, "numeric", ...
                "Limits", [0.01, Inf], "Value", 10);
            uilabel(actions, "Text", "轮数", "HorizontalAlignment", "right");
            app.IterationsField = uieditfield(actions, "numeric", ...
                "Limits", [1, Inf], "RoundFractionalValues", "on", "Value", 8);
            uilabel(actions, "Text", "候选/轮", "HorizontalAlignment", "right");
            app.CandidatesField = uieditfield(actions, "numeric", ...
                "Limits", [1, Inf], "RoundFractionalValues", "on", "Value", 12);

            app.ControllerTable = uitable(root);
            app.ControllerTable.Layout.Row = 3;
            app.ControllerTable.ColumnName = {"选择", "系统", "PID", "角色", ...
                "组", "顺序", "模式", "Kp", "Ki", "Kd", "N", ...
                "参考", "输出", "控制", "电流", "主评价", "权重", ...
                "控制下限", "控制上限", "超调上限(%)", "调节时间(s)", ...
                "稳态误差", "拓扑证据", "状态"};
            app.ControllerTable.ColumnEditable = [true, false, false, true, ...
                true, true, true, false, false, false, false, true, true, ...
                true, true, true, true, true, true, true, true, true, false, false];
            app.ControllerTable.ColumnFormat = {'logical', 'char', 'char', ...
                {'single', 'inner', 'outer', 'coupled'}, 'char', 'numeric', ...
                {'single', 'joint'}, 'numeric', 'numeric', 'numeric', ...
                'numeric', 'char', 'char', 'char', 'char', 'logical', ...
                'numeric', 'numeric', 'numeric', 'numeric', 'numeric', ...
                'numeric', 'char', 'char'};
            app.ControllerTable.ColumnWidth = {48, 180, 150, 72, 88, 56, 70, ...
                70, 70, 70, 70, 100, 100, 100, 100, 64, 60, 86, 86, 96, ...
                96, 86, 180, 150};
            app.ControllerTable.CellSelectionCallback = ...
                @(~, event) app.captureSelection(event);
            app.ControllerTable.CellEditCallback = ...
                @(~, ~) app.syncCatalogFromTable();

            app.StatusArea = uitextarea(root, "Editable", "off");
            app.StatusArea.Layout.Row = 4;
            app.StatusArea.Value = {'等待扫描模型。'};
        end

        function scanModel(app)
            app.setBusy(true, "正在扫描顶层模型、子系统和引用模型...");
            drawnow;
            try
                app.Catalog = pid_project_manager.scanProjectPids(...
                    string(app.ModelField.Value));
                app.ControllerTable.Data = app.catalogTable();
                app.SelectedRow = 1;
                pid_project_manager.saveCatalog(app.Catalog);
                app.setStatus(sprintf(...
                    "扫描完成：%d 个 PID；引用模型中的 PID 已标记并暂不自动执行。", ...
                    app.Catalog.controllerCount));
            catch exception
                app.setStatus("扫描失败：" + string(exception.message));
                uialert(app.UIFigure, exception.message, "PID 扫描失败");
            end
            app.setBusy(false);
        end

        function data = catalogTable(app)
            controllers = app.Catalog.controllers;
            count = numel(controllers);
            data = cell(count, 24);
            for index = 1:count
                item = controllers(index);
                evidence = char(item.topologyEvidence);
                if strlength(item.cascadePartnerPath) > 0
                    evidence = char(item.role + " -> " + item.cascadePartnerPath);
                end
                data(index, :) = {item.selected, char(item.parentSystem), ...
                    char(item.name), char(item.role), char(item.groupId), ...
                    item.order, char(item.mode), item.currentPid.Kp, ...
                    item.currentPid.Ki, item.currentPid.Kd, item.currentPid.N, ...
                    char(item.referenceSignalName), char(item.outputSignalName), ...
                    char(item.controlSignalName), char(item.currentSignalName), ...
                    item.primaryEvaluation, item.evaluationWeight, ...
                    item.controlLowerLimit, item.controlUpperLimit, ...
                    item.overshootPctMax, item.settlingTimeMax, ...
                    item.steadyStateErrorAbsMax, evidence, char(item.status)};
            end
        end

        function syncCatalogFromTable(app)
            data = app.ControllerTable.Data;
            if isempty(data)
                return;
            end
            for index = 1:size(data, 1)
                app.Catalog.controllers(index).selected = logical(data{index, 1});
                app.Catalog.controllers(index).role = string(data{index, 4});
                app.Catalog.controllers(index).groupId = string(data{index, 5});
                app.Catalog.controllers(index).order = double(data{index, 6});
                app.Catalog.controllers(index).mode = string(data{index, 7});
                app.Catalog.controllers(index).referenceSignalName = string(data{index, 12});
                app.Catalog.controllers(index).outputSignalName = string(data{index, 13});
                app.Catalog.controllers(index).controlSignalName = string(data{index, 14});
                app.Catalog.controllers(index).currentSignalName = string(data{index, 15});
                app.Catalog.controllers(index).primaryEvaluation = logical(data{index, 16});
                app.Catalog.controllers(index).evaluationWeight = double(data{index, 17});
                app.Catalog.controllers(index).controlLowerLimit = double(data{index, 18});
                app.Catalog.controllers(index).controlUpperLimit = double(data{index, 19});
                app.Catalog.controllers(index).overshootPctMax = double(data{index, 20});
                app.Catalog.controllers(index).settlingTimeMax = double(data{index, 21});
                app.Catalog.controllers(index).steadyStateErrorAbsMax = double(data{index, 22});
            end
            app.Catalog.selectedCount = sum([app.Catalog.controllers.selected]);
        end

        function autoGroup(app)
            app.syncCatalogFromTable();
            controllers = app.Catalog.controllers;
            for index = 1:numel(controllers)
                controllers(index).groupId = "";
                controllers(index).mode = "single";
                controllers(index).selected = false;
            end
            groupNumber = 0;
            used = false(1, numel(controllers));
            paths = string({controllers.path});
            for firstIndex = 1:numel(controllers)
                if used(firstIndex) || strlength(controllers(firstIndex).cascadePartnerPath) == 0
                    continue;
                end
                secondIndex = find(paths == controllers(firstIndex).cascadePartnerPath, 1);
                if isempty(secondIndex) || secondIndex == firstIndex || used(secondIndex)
                    continue;
                end
                symmetric = controllers(secondIndex).cascadePartnerPath == controllers(firstIndex).path;
                roles = lower([string(controllers(firstIndex).role), ...
                    string(controllers(secondIndex).role)]);
                if ~symmetric || ~all(ismember(["inner", "outer"], roles))
                    continue;
                end
                groupNumber = groupNumber + 1;
                groupId = "cascade-" + compose("%02d", groupNumber);
                pairIndices = [firstIndex, secondIndex];
                for pairIndex = pairIndices
                    controllers(pairIndex).groupId = groupId;
                    controllers(pairIndex).mode = "joint";
                    controllers(pairIndex).selected = true;
                    controllers(pairIndex).primaryEvaluation = ...
                        lower(string(controllers(pairIndex).role)) == "outer";

                    used(pairIndex) = true;
                end
            end
            app.Catalog.controllers = controllers;
            app.ControllerTable.Data = app.catalogTable();
            if groupNumber == 0
                app.setStatus(["没有发现可验证的级联拓扑，未进行自动分组。" ...
                    "请人工填写组、角色、逐环信号和限幅。"]);
            else
                app.setStatus(sprintf(["按信号连接证据建立 %d 个级联组。" ...
                    "执行前仍需核对逐环信号、限幅和目标。"], groupNumber));
            end
        end
        function selectExecutable(app)
            for index = 1:numel(app.Catalog.controllers)
                app.Catalog.controllers(index).selected = ...
                    ~app.Catalog.controllers(index).isReferencedModel;
            end
            app.ControllerTable.Data = app.catalogTable();
            app.syncCatalogFromTable();
        end

        function clearSelection(app)
            for index = 1:numel(app.Catalog.controllers)
                app.Catalog.controllers(index).selected = false;
            end
            app.ControllerTable.Data = app.catalogTable();
            app.syncCatalogFromTable();
        end

        function savePlan(app)
            try
                app.syncCatalogFromTable();
                pid_project_manager.saveCatalog(app.Catalog);
                app.Plan = pid_project_manager.buildTuningPlan(app.Catalog);
                for index = 1:numel(app.Plan.units)
                    app.Plan.units(index).stopTime = string(app.StopTimeField.Value);
                    app.Plan.units(index).maxIterations = app.IterationsField.Value;
                    app.Plan.units(index).numCandidates = app.CandidatesField.Value;
                end
                path = pid_project_manager.savePlan(app.Plan);
                app.setStatus("计划已保存：" + string(path));
            catch exception
                app.Plan = struct();
                app.setStatus("计划保存失败：" + string(exception.message));
                uialert(app.UIFigure, exception.message, "计划无效");
            end
        end

        function runPlan(app)
            app.savePlan();
            if isempty(fieldnames(app.Plan))
                return;
            end
            answer = uiconfirm(app.UIFigure, ...
                sprintf("将顺序执行 %d 个调参单元。每个单元最多两个 PID。", ...
                app.Plan.unitCount), "确认执行", ...
                "Options", {"执行", "取消"}, "DefaultOption", 2, "CancelOption", 2);
            if string(answer) ~= "执行"
                return;
            end
            app.setBusy(true, "调参计划执行中...");
            drawnow;
            try
                [app.Plan, ~] = pid_project_manager.runTuningPlan(...
                    app.Plan, @(plan, index) app.progressUpdate(plan, index));
                app.setStatus("调参计划完成：" + string(app.Plan.status));
            catch exception
                app.setStatus("调参计划失败：" + string(exception.message));
                uialert(app.UIFigure, exception.message, "执行失败");
            end
            app.setBusy(false);
        end

        function progressUpdate(app, plan, index)
            app.Plan = plan;
            if index == 0
                app.setStatus("计划状态：" + string(plan.status));
            else
                unit = plan.units(index);
                app.setStatus(sprintf("[%d/%d] %s：%s %s", index, ...
                    plan.unitCount, unit.name, unit.status, unit.message));
            end
            drawnow;
        end

        function captureSelection(app, event)
            if ~isempty(event.Indices)
                app.SelectedRow = event.Indices(1, 1);
            end
        end

        function locateSelected(app)
            if isempty(app.Catalog.controllers)
                return;
            end
            row = min(max(1, app.SelectedRow), numel(app.Catalog.controllers));
            item = app.Catalog.controllers(row);
            try
                open_system(item.modelName);
                hilite_system(item.path, "find");
                app.setStatus("已定位：" + item.path);
            catch exception
                app.setStatus("定位失败：" + string(exception.message));
            end
        end

        function clearHighlight(app)
            try
                hilite_system(string(app.ModelField.Value), "none");
            catch
            end
        end

        function setBusy(app, busy, message)
            if busy
                app.RunButton.Enable = "off";
                app.UIFigure.Pointer = "watch";
                if nargin >= 3
                    app.setStatus(message);
                end
            else
                app.RunButton.Enable = "on";
                app.UIFigure.Pointer = "arrow";
            end
        end

        function setStatus(app, message)
            app.StatusArea.Value = cellstr(string(message));
        end
    end
end