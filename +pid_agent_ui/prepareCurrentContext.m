function [context, confirmed] = prepareCurrentContext()
%PREPARECURRENTCONTEXT Ensure the current model is saved for worker MATLAB.

context = pid_agent_ui.resolveCurrentContext();
confirmed = false;
if strlength(string(context.modelPath)) == 0
    error("PIDAgent:UnsavedModel", ...
        "Save the current Simulink model before starting PID tuning.");
end

if context.modelDirty
    answer = questdlg(...
        "The current model has unsaved changes. Save it before PID tuning?", ...
        "PID Agent", "Save and continue", "Cancel", "Save and continue");
    if string(answer) ~= "Save and continue"
        return;
    end
    save_system(context.modelName);
    context = pid_agent_ui.resolveCurrentContext();
end
confirmed = true;
end
