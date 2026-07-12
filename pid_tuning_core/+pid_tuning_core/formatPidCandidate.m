function text = formatPidCandidate(candidate)
%FORMATPIDCANDIDATE Format one or more PID groups for console output.

candidate = pid_tuning_core.normalizePidCandidate(candidate, []);
parts = strings(1, numel(candidate.pids));

for idx = 1:numel(candidate.pids)
    p = candidate.pids(idx);
    parts(idx) = sprintf("%s[Kp=%g, Ki=%g, Kd=%g, N=%g]", ...
        p.name, p.Kp, p.Ki, p.Kd, p.N);
end

text = strjoin(parts, "; ");
end

