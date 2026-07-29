function [t, values] = extractSignalVector(simOutput, signalName)
%EXTRACTSIGNALVECTOR Extract one unambiguous scalar signal from a simulation.

signalName = char(string(signalName));
if strlength(string(signalName)) == 0
    error("Signal name cannot be empty.");
end

if isstruct(simOutput) && isfield(simOutput, signalName)
    [t, values] = localFromTimeseries(simOutput.(signalName), signalName);
    return;
end

if isa(simOutput, "Simulink.SimulationOutput")
    names = string(simOutput.who);
    if any(names == "logsout")
        logsout = simOutput.get("logsout");
        [found, t, values] = localTryDataset(logsout, signalName);
        if found
            return;
        end
    end

    if any(names == string(signalName))
        item = simOutput.get(signalName);
        [t, values] = localFromTimeseries(item, signalName);
        return;
    end
end

error("Signal '%s' was not found in logsout or SimulationOutput.", signalName);
end

function [found, t, values] = localTryDataset(dataset, signalName)
found = false;
t = [];
values = [];
if isempty(dataset)
    return;
end
if ~isa(dataset, "Simulink.SimulationData.Dataset")
    error("logsout is not a Simulink.SimulationData.Dataset.");
end

matches = [];
for index = 1:dataset.numElements
    element = dataset.getElement(index);
    elementName = string(localElementName(element));
    if elementName == string(signalName)
        matches(end + 1) = index; %#ok<AGROW>
    end
end
if isempty(matches)
    return;
end
if numel(matches) > 1
    error("Signal name '%s' is ambiguous in logsout (%d matches). Rename or log the intended signal with a unique name.", ...
        signalName, numel(matches));
end

element = dataset.getElement(matches(1));
if isa(element, "Simulink.SimulationData.Signal")
    [t, values] = localFromTimeseries(element.Values, signalName);
else
    [t, values] = localFromTimeseries(element, signalName);
end
found = true;
end

function name = localElementName(element)
name = "";
try
    name = string(element.Name);
catch
end
end

function [t, values] = localFromTimeseries(item, signalName)
if isa(item, "timeseries")
    t = item.Time;
    values = squeeze(item.Data);
    [t, values] = localRequireScalarSeries(t, values, signalName);
    return;
end

if istimetable(item)
    if width(item) ~= 1
        error("Signal '%s' is a timetable with %d variables. Select and log one scalar component.", ...
            signalName, width(item));
    end
    t = seconds(item.Properties.RowTimes - item.Properties.RowTimes(1));
    values = item{:, 1};
    [t, values] = localRequireScalarSeries(t, values, signalName);
    return;
end

if isnumeric(item) && ismatrix(item) && size(item, 2) == 2
    t = item(:, 1);
    values = item(:, 2);
    [t, values] = localRequireScalarSeries(t, values, signalName);
    return;
end

error("Signal '%s' uses unsupported or non-scalar storage type: %s.", ...
    signalName, class(item));
end

function [t, values] = localRequireScalarSeries(t, values, signalName)
t = t(:);
if ~isvector(values)
    error("Signal '%s' is vector-valued. Log the intended scalar component separately.", signalName);
end
values = values(:);
if numel(t) ~= numel(values)
    error("Signal '%s' has inconsistent time and data lengths.", signalName);
end
end