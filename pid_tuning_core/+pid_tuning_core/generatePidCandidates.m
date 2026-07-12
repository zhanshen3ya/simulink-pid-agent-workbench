function candidates = generatePidCandidates(state, cfg, count)
%GENERATEPIDCANDIDATES Generate bounded single-PID or multi-PID candidates.

aiCandidates = repmat(pid_tuning_core.normalizePidCandidate(cfg.initialCandidate, cfg), 0, 1);
if cfg.ai.enabled
    try
        if ~isempty(cfg.ai.suggestFcn)
            rawAiCandidates = feval(cfg.ai.suggestFcn, state, cfg, count);
            aiSource = "ai:callback";
        else
            rawAiCandidates = pid_tuning_core.requestAiCandidates(state, cfg, count);
            if isfield(cfg.ai, "sourceLabel") && strlength(string(cfg.ai.sourceLabel)) > 0
                aiSource = string(cfg.ai.sourceLabel);
            else
                aiSource = "ai:" + string(cfg.ai.mode);
            end
        end
        aiCandidates = localNormalizeCandidates(rawAiCandidates, cfg);
        for idx = 1:numel(aiCandidates)
            aiCandidates(idx).source = aiSource;
        end
    catch err
        if cfg.ai.failOnError
            rethrow(err);
        end
        warning("PIDTuning:AIProviderFailed", ...
            "AI provider failed; using program candidates instead: %s", err.message);
    end
end

remaining = max(0, count - numel(aiCandidates));
programCandidates = localProgrammaticCandidates(state, cfg, remaining);

candidates = [aiCandidates(:); programCandidates(:)];
if numel(candidates) > count
    candidates = candidates(1:count);
end

for idx = 1:numel(candidates)
    candidates(idx) = localClipCandidate(candidates(idx), cfg);
end
end

function candidates = localProgrammaticCandidates(state, cfg, count)
template = pid_tuning_core.normalizePidCandidate(cfg.initialCandidate, cfg);
if count <= 0
    candidates = repmat(template, 0, 1);
    return;
end

candidates = repmat(template, count, 1);
center = pid_tuning_core.normalizePidCandidate(state.searchCenter, cfg);
scale = max(state.searchScale, cfg.search.minScale);

for idx = 1:count
    if state.iteration == 1 && idx == 1
        candidate = cfg.initialCandidate;
    else
        if rand() < cfg.search.randomFraction
            candidate = localUniformCandidate(cfg);
        else
            candidate = localPerturbAround(center, cfg, scale);
        end
    end
    candidates(idx) = localClipCandidate(candidate, cfg);
    candidates(idx).source = "program";
end
end

function candidate = localPerturbAround(center, cfg, scale)
candidate = center;
fields = ["Kp", "Ki", "Kd", "N"];

for pidIdx = 1:numel(cfg.pidBlocks)
    bounds = cfg.pidBlocks(pidIdx).bounds;
    for field = fields
        span = bounds.(field)(2) - bounds.(field)(1);
        sigma = max(span * scale, eps);
        candidate.pids(pidIdx).(field) = center.pids(pidIdx).(field) + randn() * sigma;
    end
end
end

function candidate = localUniformCandidate(cfg)
candidate = pid_tuning_core.normalizePidCandidate(cfg.initialCandidate, cfg);
fields = ["Kp", "Ki", "Kd", "N"];

for pidIdx = 1:numel(cfg.pidBlocks)
    bounds = cfg.pidBlocks(pidIdx).bounds;
    for field = fields
        lo = bounds.(field)(1);
        hi = bounds.(field)(2);
        candidate.pids(pidIdx).(field) = lo + rand() * (hi - lo);
    end
end
end

function candidate = localClipCandidate(candidate, cfg)
candidate = pid_tuning_core.normalizePidCandidate(candidate, cfg);
fields = ["Kp", "Ki", "Kd", "N"];

for pidIdx = 1:numel(cfg.pidBlocks)
    bounds = cfg.pidBlocks(pidIdx).bounds;
    for field = fields
        value = candidate.pids(pidIdx).(field);
        if isempty(value) || ~isfinite(value)
            value = mean(bounds.(field));
        end
        candidate.pids(pidIdx).(field) = min(max(value, bounds.(field)(1)), bounds.(field)(2));
    end
end

candidate = pid_tuning_core.normalizePidCandidate(candidate, cfg);
end

function candidates = localNormalizeCandidates(inputCandidates, cfg)
template = pid_tuning_core.normalizePidCandidate(cfg.initialCandidate, cfg);
if isempty(inputCandidates)
    candidates = repmat(template, 0, 1);
    return;
end

inputCandidates = inputCandidates(:);
candidates = repmat(template, numel(inputCandidates), 1);
for idx = 1:numel(inputCandidates)
    candidates(idx) = pid_tuning_core.normalizePidCandidate(inputCandidates(idx), cfg);
end
end

