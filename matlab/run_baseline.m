function result = run_baseline(request)
%RUN_BASELINE Run the unmodified model and extract configured signals.

[modelName, resolvedPath] = pid_tuning_core.resolveSimulinkModel(request.model_file);
wasLoaded = bdIsLoaded(modelName);
load_system(resolvedPath);
cleanup = onCleanup(@() localCloseIfNeeded(modelName, wasLoaded));

result = struct("success", false, "solver_error", "", ...
    "signals", struct(), "metadata", struct("runner", "matlab"));
try
    simulationInput = Simulink.SimulationInput(modelName);
    simulationInput = simulationInput.setModelParameter( ...
        "StopTime", string(request.stop_time), "SaveOutput", "on");
    simulationOutput = sim(simulationInput);
    names = request.signals;
    [time, reference] = pid_tuning_core.extractSignalVector( ...
        simulationOutput, localRequiredName(names, "reference"));
    [outputTime, output] = pid_tuning_core.extractSignalVector( ...
        simulationOutput, localRequiredName(names, "measurement"));
    [controlTime, control] = pid_tuning_core.extractSignalVector( ...
        simulationOutput, localControlName(names));
    output = interp1(outputTime, output, time, "linear", "extrap");
    control = interp1(controlTime, control, time, "linear", "extrap");
    extraSignals = struct();
    [hasCurrent, currentName] = localOptionalName(names, "current");
    if hasCurrent
        [currentTime, current] = pid_tuning_core.extractSignalVector( ...
            simulationOutput, currentName);
        extraSignals.current = interp1(currentTime, current, time, "linear", "extrap");
    end
    result.success = true;
    result.signals = struct( ...
        "time", time(:), "reference", reference(:), ...
        "output", output(:), "control", control(:), ...
        "extra_signals", extraSignals);
catch exception
    result.solver_error = string(getReport(exception, "extended", "hyperlinks", "off"));
end
end

function name = localRequiredName(names, fieldName)
[present, name] = localOptionalName(names, fieldName);
if ~present
    error("AutoPID:SignalRequired", ...
        "MATLAB baseline requires signals.%s to name a logged signal.", fieldName);
end
end

function name = localControlName(names)
[present, name] = localOptionalName(names, "actuator_control");
if present
    return;
end
[present, name] = localOptionalName(names, "raw_control");
if ~present
    error("AutoPID:SignalRequired", ...
        "MATLAB baseline requires actuator_control or raw_control.");
end
end

function [present, name] = localOptionalName(names, fieldName)
present = false;
name = "";
if ~isfield(names, fieldName)
    return;
end
value = names.(fieldName);
if isempty(value)
    return;
end
text = string(value);
if isempty(text)
    return;
end
name = strtrim(text(1));
present = strlength(name) > 0;
end
function localCloseIfNeeded(modelName, wasLoaded)
if ~wasLoaded && bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end
