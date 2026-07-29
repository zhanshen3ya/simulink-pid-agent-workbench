function candidates = requestAiCandidates(state, cfg, requestedCount)
%REQUESTAICANDIDATES Request PID candidates from an API or local-code provider.

mode = lower(string(cfg.ai.mode));
count = min(requestedCount, max(0, floor(double(cfg.ai.candidatesPerIteration))));
if mode == "none" || count == 0
    candidates = struct([]);
    return;
end

request = localBuildRequest(state, cfg, count);
requestFile = localAiFile(cfg, state.iteration, "request.json");
responseFile = localAiFile(cfg, state.iteration, "response.json");
pid_tuning_core.writeJsonFile(requestFile, request);

switch mode
    case "api"
        response = localApiRequest(request, cfg);
        pid_tuning_core.writeJsonFile(responseFile, response);
        candidates = localCandidatesFromApi(response);
    case {"local", "agent"}
        localRunProvider(requestFile, responseFile, cfg);
        response = jsondecode(fileread(responseFile));
        candidates = localCandidateField(response);
    otherwise
        error("Unsupported AI mode: %s", mode);
end

if isempty(candidates)
    error("AI provider returned no PID candidates.");
end
candidates = candidates(:);
if numel(candidates) > count
    candidates = candidates(1:count);
end
end

function request = localBuildRequest(state, cfg, count)
request = struct();
request.schemaVersion = 1;
request.task = "Generate PID candidates for mandatory Simulink validation";
request.requestedCandidates = count;
request.iteration = state.iteration;
request.searchScale = state.searchScale;
request.searchCenter = pid_tuning_core.normalizePidCandidate(state.searchCenter, cfg);
request.targets = cfg.targets;
request.evaluationLoops = pid_tuning_core.jsonSafe( ...
    pid_tuning_core.normalizeEvaluationLoops(cfg));
request.activePidIndices = localField(cfg, "activePidIndices", 1:numel(cfg.pidBlocks));
request.stage = string(localField(state, "currentStage", "joint"));
request.stageIteration = localField(state, "stageIteration", state.iteration);
request.guidance = "Respect loop roles. Tune inner bandwidth before outer response; " + ...
    "do not change inactive PID entries. Use per-loop failures and normalized metrics.";

template = struct("name", "", "path", "", "bounds", struct());
request.pidBlocks = cell(numel(cfg.pidBlocks), 1);
for idx = 1:numel(cfg.pidBlocks)
    item = template;
    item.name = cfg.pidBlocks(idx).name;
    item.path = cfg.pidBlocks(idx).path;
    item.bounds = cfg.pidBlocks(idx).bounds;
    request.pidBlocks{idx} = item;
end

request.history = localHistory(state, cfg.ai.maxHistoryRecords);
request.responseContract = struct( ...
    "description", "Return JSON only. Include every PID; inactive PID values must equal searchCenter. Use per-loop metrics and stage context.", ...
    "example", struct("candidates", struct("pids", struct( ...
        "name", "pid1", "Kp", 1, "Ki", 0, "Kd", 0, "N", 100))));
end

function value = localField(source, name, fallback)
if isstruct(source) && isfield(source, name)
    value = source.(name);
else
    value = fallback;
end
end
function history = localHistory(state, maxRecords)
history = struct([]);
if ~isfield(state, "history") || isempty(state.history) || maxRecords <= 0
    return;
end

first = max(1, numel(state.history) - floor(maxRecords) + 1);
records = state.history(first:end);
template = struct("iteration", 0, "candidate", struct(), "metrics", struct(), ...
    "passed", false, "score", 0);
history = repmat(template, numel(records), 1);
for idx = 1:numel(records)
    history(idx).iteration = records(idx).iteration;
    history(idx).stage = string(localField(records(idx), "stage", ""));
    history(idx).stageIteration = localField(records(idx), "stageIteration", 0);
    history(idx).candidate = records(idx).candidate;
    history(idx).metrics = records(idx).metrics;
    history(idx).passed = records(idx).passed;
    history(idx).score = records(idx).score;
end
history = pid_tuning_core.jsonSafe(history);
end

function response = localApiRequest(request, cfg)
endpoint = string(cfg.ai.api.baseUrl);
if strlength(endpoint) == 0
    error("AI API baseUrl is required.");
end
if ~endsWith(lower(endpoint), "/chat/completions")
    endpoint = strip(endpoint, "right", "/") + "/chat/completions";
end
if strlength(string(cfg.ai.api.model)) == 0
    error("AI API model is required.");
end

apiKey = string(getenv(char(cfg.ai.api.apiKeyEnvVar)));

systemPrompt = [ ...
    "You generate numerical PID candidates for a closed-loop optimizer. ", ...
    "Return valid JSON only, with top-level key candidates. ", ...
    "Do not add markdown. Respect every supplied bound. ", ...
    "Simulation and acceptance checks are performed externally; never claim a candidate passed."];
messages(1) = struct("role", "system", "content", systemPrompt);
messages(2) = struct("role", "user", "content", jsonencode(pid_tuning_core.jsonSafe(request)));

payload = struct();
payload.model = string(cfg.ai.api.model);
payload.messages = messages;
payload.temperature = double(cfg.ai.api.temperature);
payload.max_tokens = floor(double(cfg.ai.api.maxTokens));

headers = {};
if strlength(apiKey) > 0
    headers = [headers, {'Authorization', char("Bearer " + apiKey)}];
end
options = weboptions("MediaType", "application/json", ...
    "HeaderFields", headers, "Timeout", double(cfg.ai.api.timeoutSeconds));
response = webwrite(char(endpoint), payload, options);
end

function candidates = localCandidatesFromApi(response)
if ~isfield(response, "choices") || isempty(response.choices)
    error("AI API response has no choices.");
end
choice = response.choices(1);
if ~isfield(choice, "message") || ~isfield(choice.message, "content")
    error("AI API response has no message content.");
end

content = string(choice.message.content);
jsonText = regexp(char(content), '\{[\s\S]*\}', "match", "once");
if isempty(jsonText)
    error("AI API response did not contain a JSON object.");
end
decoded = jsondecode(jsonText);
candidates = localCandidateField(decoded);
end

function candidates = localCandidateField(response)
if isstruct(response) && isfield(response, "candidates")
    candidates = response.candidates;
elseif isstruct(response) && isfield(response, "pids")
    candidates = response;
else
    error("AI response must contain candidates or a candidate with pids.");
end
end

function localRunProvider(requestFile, responseFile, cfg)
scriptPath = string(cfg.ai.local.scriptPath);
if ~isfile(scriptPath)
    error("Local AI provider script does not exist: %s", scriptPath);
end
runnerPath = string(cfg.ai.local.runnerPath);
if ~isfile(runnerPath)
    error("Local AI runner does not exist: %s", runnerPath);
end

pythonExe = string(cfg.ai.local.pythonExe);
command = sprintf('"%s" "%s" --python "%s" --script "%s" --request "%s" --response "%s" --timeout %g', ...
    pythonExe, runnerPath, pythonExe, scriptPath, requestFile, responseFile, ...
    double(cfg.ai.local.timeoutSeconds));
[status, output] = system(command);
if status ~= 0
    error("Local AI provider failed: %s", strtrim(output));
end
if ~isfile(responseFile)
    error("Local AI provider did not create response JSON: %s", responseFile);
end
end

function path = localAiFile(cfg, iteration, suffix)
folder = fullfile(cfg.logging.runDir, "ai");
if ~isfolder(folder)
    mkdir(folder);
end
path = fullfile(folder, sprintf("iteration_%03d_%s", iteration, suffix));
end
