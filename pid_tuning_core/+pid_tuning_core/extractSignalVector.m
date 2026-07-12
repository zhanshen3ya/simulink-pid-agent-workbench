function [t, values] = extractSignalVector(simOutput, signalName)
%EXTRACTSIGNALVECTOR Extract a named signal from Simulink SimulationOutput.

signalName = char(signalName);

if isa(simOutput, "Simulink.SimulationOutput")
    if isprop(simOutput, "logsout") || any(strcmp(simOutput.who, "logsout"))
        logsout = simOutput.get("logsout");
        [t, values] = localFromDataset(logsout, signalName);
        return;
    end

    names = simOutput.who;
    if any(strcmp(names, signalName))
        item = simOutput.get(signalName);
        [t, values] = localFromTimeseries(item);
        return;
    end
end

error("Signal '%s' was not found. Log it to logsout or SimulationOutput.", signalName);
end

function [t, values] = localFromDataset(dataset, signalName)
if ~isa(dataset, "Simulink.SimulationData.Dataset")
    error("logsout is not a Simulink.SimulationData.Dataset.");
end

element = dataset.get(signalName);
if isempty(element)
    error("Signal '%s' not found in logsout.", signalName);
end

if isa(element, "Simulink.SimulationData.Signal")
    [t, values] = localFromTimeseries(element.Values);
else
    [t, values] = localFromTimeseries(element);
end
end

function [t, values] = localFromTimeseries(item)
if isa(item, "timeseries")
    t = item.Time;
    values = squeeze(item.Data);
    if ~isvector(values)
        values = values(:, 1);
    end
    return;
end

if istimetable(item)
    t = seconds(item.Properties.RowTimes - item.Properties.RowTimes(1));
    values = item{:, 1};
    return;
end

if isnumeric(item) && size(item, 2) >= 2
    t = item(:, 1);
    values = item(:, 2);
    return;
end

error("Unsupported signal storage type: %s.", class(item));
end

