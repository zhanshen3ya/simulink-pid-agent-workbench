function state = updatePidSearchState(state, records, cfg)
%UPDATEPIDSEARCHSTATE Update best candidate and local search center.

[~, order] = sort([records.score], "ascend");
sorted = records(order);

if isempty(state.best) || sorted(1).score < state.best.score
    state.best = sorted(1);
end

passing = sorted([sorted.passed]);
if ~isempty(passing)
    if isempty(state.bestPassing) || passing(1).score < state.bestPassing.score
        state.bestPassing = passing(1);
    end
end

eliteCount = min(cfg.search.eliteCount, numel(sorted));
elite = sorted(1:eliteCount);

state.searchCenter = localMeanCandidate([elite.candidate]);
state.searchScale = max(cfg.search.minScale, state.searchScale * cfg.search.scaleDecay);
state.history = [state.history, records];
end

function candidate = localMeanCandidate(candidates)
candidate = candidates(1);
pidCount = numel(candidate.pids);

for pidIdx = 1:pidCount
    candidate.pids(pidIdx).Kp = mean(arrayfun(@(c) c.pids(pidIdx).Kp, candidates));
    candidate.pids(pidIdx).Ki = mean(arrayfun(@(c) c.pids(pidIdx).Ki, candidates));
    candidate.pids(pidIdx).Kd = mean(arrayfun(@(c) c.pids(pidIdx).Kd, candidates));
    candidate.pids(pidIdx).N = mean(arrayfun(@(c) c.pids(pidIdx).N, candidates));
end

candidate = pid_tuning_core.normalizePidCandidate(candidate, []);
end
