function value = jsonSafe(value)
%JSONSAFE Replace values that jsonencode/frontends handle poorly.

if isstruct(value)
    for idx = 1:numel(value)
        fields = fieldnames(value(idx));
        for f = 1:numel(fields)
            field = fields{f};
            value(idx).(field) = pid_tuning_core.jsonSafe(value(idx).(field));
        end
    end
elseif iscell(value)
    for idx = 1:numel(value)
        value{idx} = pid_tuning_core.jsonSafe(value{idx});
    end
elseif isnumeric(value)
    value(~isfinite(value)) = NaN;
end
end

