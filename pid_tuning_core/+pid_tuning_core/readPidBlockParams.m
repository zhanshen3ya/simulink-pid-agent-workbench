function params = readPidBlockParams(pidBlockPath)
%READPIDBLOCKPARAMS Read PID block parameters and numeric values when possible.

raw = struct();
raw.P = localGetParam(pidBlockPath, "P");
raw.I = localGetParam(pidBlockPath, "I");
raw.D = localGetParam(pidBlockPath, "D");
raw.N = localGetParam(pidBlockPath, "N");

numeric = struct();
numeric.Kp = localToNumber(raw.P, 1, pidBlockPath);
numeric.Ki = localToNumber(raw.I, 0, pidBlockPath);
numeric.Kd = localToNumber(raw.D, 0, pidBlockPath);
numeric.N = localToNumber(raw.N, 100, pidBlockPath);

params = struct();
params.blockPath = string(pidBlockPath);
params.raw = raw;
params.numeric = numeric;
end

function value = localGetParam(blockPath, name)
try
    value = get_param(blockPath, char(name));
catch
    value = "";
end
end

function value = localToNumber(rawValue, fallback, blockPath)
value = fallback;
if isempty(rawValue)
    return;
end

if isnumeric(rawValue)
    value = double(rawValue);
    return;
end

textValue = string(rawValue);
direct = str2double(textValue);
if isfinite(direct)
    value = direct;
    return;
end

try
    evaluated = slResolve(char(textValue), char(blockPath));
    if isnumeric(evaluated) && isscalar(evaluated) && isfinite(evaluated)
        value = double(evaluated);
        return;
    end
catch
end

try
    evaluated = evalin("base", textValue);
    if isnumeric(evaluated) && isscalar(evaluated) && isfinite(evaluated)
        value = double(evaluated);
    end
catch
end
end

