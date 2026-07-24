const state = {
  activeJobId: null,
  status: null,
  history: [],
  pollHandle: null,
  modelInfo: null,
  selectedPidIndexes: [],
};

const el = (id) => document.getElementById(id);
const fmt = new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 5 });

const AI_PRESETS = {
  remote: [
    { label: 'OpenAI GPT-4o',        baseUrl: 'https://api.openai.com/v1',        model: 'gpt-4o' },
    { label: 'OpenAI GPT-4o-mini',   baseUrl: 'https://api.openai.com/v1',        model: 'gpt-4o-mini' },
    { label: 'OpenAI GPT-4-turbo',   baseUrl: 'https://api.openai.com/v1',        model: 'gpt-4-turbo' },
    { label: 'OpenAI GPT-3.5-turbo', baseUrl: 'https://api.openai.com/v1',        model: 'gpt-3.5-turbo' },
    { label: 'DeepSeek V3',          baseUrl: 'https://api.deepseek.com/v1',       model: 'deepseek-chat' },
    { label: 'DeepSeek R1',          baseUrl: 'https://api.deepseek.com/v1',       model: 'deepseek-reasoner' },
    { label: '通义千问 (Qwen)',       baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus' },
    { label: '智谱 GLM-4',           baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4' },
    { label: 'Moonshot (Kimi)',      baseUrl: 'https://api.moonshot.cn/v1',        model: 'moonshot-v1-8k' },
    { label: '自定义',               baseUrl: '', model: '' },
  ],
  local: [
    { engine: 'ollama',  label: 'Ollama',              baseUrl: 'http://localhost:11434/v1' },
    { engine: 'lmstudio', label: 'LM Studio',           baseUrl: 'http://localhost:1234/v1' },
    { engine: 'vllm',    label: 'vLLM / LocalAI',       baseUrl: 'http://localhost:8000/v1' },
    { engine: 'python',  label: 'Python Provider 脚本', baseUrl: '' },
    { engine: 'custom',  label: '自定义本地端点',       baseUrl: '' },
  ],
};

const modalState = { method: 'none', agents: [] };

function escapeHtml(input) {
  return String(input ?? '').replace(/[&<>"]/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;',
  }[char]));
}

function value(input, fallback = '-') {
  if (input === null || input === undefined || input === '') return fallback;
  if (typeof input === 'number') return Number.isFinite(input) ? fmt.format(input) : fallback;
  return String(input);
}

function secondsToClock(seconds) {
  const total = Math.max(0, Math.floor(Number(seconds) || 0));
  return [Math.floor(total / 3600), Math.floor((total % 3600) / 60), total % 60]
    .map((item) => String(item).padStart(2, '0')).join(':');
}

function recordOrNull(record) {
  return !record || (Array.isArray(record) && !record.length) ? null : record;
}

function pickMetrics(record) { return recordOrNull(record)?.metrics || {}; }
function metricValue(metrics, key) { return value(metrics?.[key]); }

function metricRows(metrics) {
  return [
    ['超调 (%)', 'overshootPct'], ['调节时间 (s)', 'settlingTime'],
    ['稳态误差', 'steadyStateError'], ['IAE', 'iae'], ['ISE', 'ise'],
    ['ITAE', 'itae'], ['控制能量', 'controlEnergy'], ['最大控制量', 'maxAbsControl'],
    ['电感电流峰值 (A)', 'maxAbsCurrent'], ['输出纹波 (V)', 'outputRipple'],
    ['占空比饱和比例', 'controlSaturationFraction'],
  ].map(([label, key]) => `<div class="metric-row"><span>${label}</span><strong>${metricValue(metrics, key)}</strong></div>`).join('');
}

function candidatePids(record) {
  const candidate = record?.candidate || {};
  if (Array.isArray(candidate.pids)) return candidate.pids;
  if (candidate.pids && typeof candidate.pids === 'object') return 'Kp' in candidate.pids ? [candidate.pids] : Object.values(candidate.pids);
  if ('Kp' in candidate || 'Ki' in candidate || 'Kd' in candidate) return [candidate];
  return [];
}

function renderPidRows(targetId, record) {
  const rows = candidatePids(record);
  el(targetId).innerHTML = rows.length ? rows.map((pid, index) => `
    <tr><td>${escapeHtml(value(pid.name, `PID ${index + 1}`))}</td><td>${value(pid.Kp)}</td>
    <td>${value(pid.Ki)}</td><td>${value(pid.Kd)}</td><td>${value(pid.N)}</td></tr>
  `).join('') : '<tr><td colspan="5">暂无参数</td></tr>';
}

function candidateSource(record) {
  return String(record?.candidate?.source || 'program');
}

function sourceHtml(record) {
  const source = candidateSource(record);
  const agentLabels = { codex: 'Codex', minimax: 'MiniMax', claude: 'Claude' };
  let label = '程序';
  if (source === 'ai:api') label = '远程 API';
  else if (source.startsWith('agent:')) label = 'Code Agent · ' + (agentLabels[source.split(':')[1]] || source.split(':')[1]);
  else if (source.startsWith('ai:')) label = 'AI';
  const aiSource = source.startsWith('ai:') || source.startsWith('agent:');
  return '<span class="' + (aiSource ? 'source-ai' : 'source-program') + '">' + escapeHtml(label) + '</span>';
}
function passText(record) {
  if (!record) return '<span class="warn">暂无</span>';
  return record.passed ? '<span class="pass">通过</span>' : '<span class="fail">未通过</span>';
}

function pidSummary(record) {
  if (!record) return '-';
  if (record.summary) return record.summary;
  return candidatePids(record).map((pid, index) => `${value(pid.name, `PID ${index + 1}`)}: Kp=${value(pid.Kp)}, Ki=${value(pid.Ki)}, Kd=${value(pid.Kd)}, N=${value(pid.N)}`).join(' | ');
}

function failureText(record) {
  const failures = record?.failures;
  if (Array.isArray(failures)) return failures.join('; ') || '-';
  if (failures && typeof failures === 'object') return Object.values(failures).join('; ') || '-';
  return value(failures);
}

function renderRecent(records) {
  const rows = Array.isArray(records) ? records : (records ? [records] : []);
  el('recentRows').innerHTML = rows.length ? rows.map((record, index) => `
    <tr><td>${value(record.globalIndex, index + 1)}</td><td>${value(record.iteration)}</td>
    <td>${value(record.candidateIndex)}</td><td>${sourceHtml(record)}</td><td>${passText(record)}</td>
    <td>${metricValue(pickMetrics(record), 'overshootPct')}</td><td>${metricValue(pickMetrics(record), 'settlingTime')}</td>
    <td>${metricValue(pickMetrics(record), 'steadyStateError')}</td><td>${value(record.score)}</td></tr>
  `).join('') : '<tr><td colspan="9">暂无候选记录</td></tr>';
}

function renderHistory(rows) {
  const data = rows || [];
  el('historyCount').textContent = `${data.length} 条`;
  el('historyRows').innerHTML = data.length ? data.map((record, index) => {
    const summary = escapeHtml(pidSummary(record));
    return `<tr><td>${value(record.globalIndex, index + 1)}</td><td>${escapeHtml(value(record.timestamp))}</td>
      <td>${value(record.iteration)}</td><td>${value(record.candidateIndex)}</td><td>${sourceHtml(record)}</td><td title="${summary}">${summary}</td>
      <td>${passText(record)}</td><td>${escapeHtml(failureText(record))}</td>
      <td>${metricValue(pickMetrics(record), 'overshootPct')}</td><td>${metricValue(pickMetrics(record), 'settlingTime')}</td>
      <td>${metricValue(pickMetrics(record), 'steadyStateError')}</td><td>${metricValue(pickMetrics(record), 'iae')}</td><td>${value(record.score)}</td></tr>`;
  }).join('') : '<tr><td colspan="13">暂无历史记录</td></tr>';
}

function renderStatus(payload) {
  state.status = payload;
  state.activeJobId = payload.jobId || state.activeJobId;
  el('jobTitle').textContent = payload.jobId ? `任务 ${payload.jobId}` : '选择模型开始';
  el('jobSubtitle').textContent = payload.error || (payload.modelName ? `${payload.modelName} · AI: ${value(payload.aiMode, 'none')} · ${value(payload.runDir)}` : '本地 MATLAB / Simulink');
  el('elapsedTime').textContent = secondsToClock(payload.elapsedSeconds);
  el('iterationText').textContent = `${value(payload.currentIteration, 0)} / ${value(payload.maxIterations, 0)}`;
  el('testedText').textContent = value(payload.testedCount, 0);
  el('passedText').textContent = value(payload.passedCount, 0);
  const status = value(payload.status, 'idle').toLowerCase();
  el('statusPill').textContent = status;
  el('statusPill').className = `status-pill ${status}`;

  const current = recordOrNull(payload.current);
  el('currentSummary').textContent = current ? `${candidateSource(current)} · 候选 ${value(current.candidateIndex)} / 分数 ${value(current.score)}` : '暂无';
  el('currentPass').innerHTML = passText(current);
  renderPidRows('currentPidRows', current);
  el('currentMetrics').innerHTML = metricRows(pickMetrics(current));
  renderRecent(payload.recent || []);

  const bestPassing = recordOrNull(payload.bestPassing);
  const bestScored = recordOrNull(payload.best);
  const best = bestPassing || bestScored;
  el('bestKind').textContent = bestPassing ? '已通过最优' : (bestScored ? '当前最低分' : '暂无');
  el('bestScore').textContent = best ? `score=${value(best.score)}` : '暂无';
  renderPidRows('bestPidRows', best);
  el('bestMetrics').innerHTML = metricRows(pickMetrics(best));
}

async function api(path, options = {}) {
  const response = await fetch(path, options);
  let payload = {};
  try { payload = await response.json(); } catch (_) { payload = {}; }
  if (!response.ok) throw new Error(payload.error || `${response.status} ${response.statusText}`);
  return payload;
}

function jsonPost(body) {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

async function refreshHealth() {
  try {
    const payload = await api('/api/health');
    el('connectionState').textContent = payload.matlabAvailable ? 'MATLAB 已连接' : '网关已连接，未找到 MATLAB';
  } catch (_) {
    el('connectionState').textContent = '本地网关未连接';
  }
}

async function chooseLatestJob() {
  const payload = await api('/api/pid/jobs');
  const jobs = payload.jobs || [];
  if (!state.activeJobId && jobs.length) state.activeJobId = jobs[0].jobId;
}

async function refreshJob() {
  await refreshHealth();
  await chooseLatestJob();
  if (!state.activeJobId) return;
  try {
    const payload = await api(`/api/pid/jobs/${encodeURIComponent(state.activeJobId)}`);
    renderStatus(payload);
    const historyPayload = await api(`/api/pid/jobs/${encodeURIComponent(state.activeJobId)}/history`);
    state.history = historyPayload.history || [];
    renderHistory(state.history);
  } catch (error) {
    el('connectionState').textContent = `读取失败：${error.message}`;
  }
}

async function selectModel() {
  const button = el('selectModelButton');
  button.disabled = true;
  try {
    const payload = await api('/api/pid/models/select', { method: 'POST' });
    if (!payload.cancelled && payload.modelPath) {
      el('modelPathInput').value = payload.modelPath;
      await discoverModel();
    }
  } catch (error) {
    setScanState(error.message, true);
  } finally { button.disabled = false; }
}

function setScanState(message, isError = false) {
  el('modelScanState').textContent = message;
  el('modelScanState').className = isError ? 'scan-error' : 'scan-ok';
}

function normalizePidBlocks(blocks) {
  if (Array.isArray(blocks)) return blocks;
  if (blocks && typeof blocks === 'object' && Object.keys(blocks).length) return [blocks];
  return [];
}

async function discoverModel() {
  const modelPath = el('modelPathInput').value.trim();
  const button = el('discoverModelButton');
  button.disabled = true;
  button.textContent = 'MATLAB 读取中...';
  setScanState('正在启动 MATLAB 并读取模型');
  try {
    const payload = await api('/api/pid/models/discover', jsonPost({ modelPath }));
    payload.pidBlocks = normalizePidBlocks(payload.pidBlocks);
    payload.loggedSignals = Array.isArray(payload.loggedSignals) ? payload.loggedSignals : (payload.loggedSignals ? [payload.loggedSignals] : []);
    state.modelInfo = payload;
    state.selectedPidIndexes = payload.pidBlocks.slice(0, 2).map((_, index) => index);
    renderModelInfo();
    setScanState(`已读取 ${payload.modelName}：发现 ${payload.pidBlocks.length} 个 PID`);
  } catch (error) {
    state.modelInfo = null;
    state.selectedPidIndexes = [];
    el('modelConfigBody').classList.add('hidden');
    setScanState(error.message, true);
  } finally {
    button.disabled = false;
    button.textContent = '读取模型';
  }
}

function renderModelInfo() {
  const blocks = state.modelInfo?.pidBlocks || [];
  el('modelConfigBody').classList.remove('hidden');
  el('discoveredPidRows').innerHTML = blocks.length ? blocks.map((block, index) => {
    const selected = state.selectedPidIndexes.includes(index);
    const current = block.currentPid || {};
    return `<tr class="${selected ? 'selected' : ''}">
      <td><input class="pid-select" type="checkbox" data-index="${index}" ${selected ? 'checked' : ''} /></td>
      <td>${escapeHtml(block.name)}</td><td title="${escapeHtml(block.path)}">${escapeHtml(block.path)}</td>
      <td>${value(current.Kp)}</td><td>${value(current.Ki)}</td><td>${value(current.Kd)}</td><td>${value(current.N)}</td></tr>`;
  }).join('') : '<tr><td colspan="7">未发现带 P/I/D 参数的 PID Controller 块</td></tr>';
  document.querySelectorAll('.pid-select').forEach((checkbox) => checkbox.addEventListener('change', togglePidSelection));
  el('loggedSignalsList').innerHTML = (state.modelInfo.loggedSignals || []).map((name) => `<option value="${escapeHtml(name)}"></option>`).join('');
  renderPidEditors();
}

function togglePidSelection(event) {
  const index = Number(event.target.dataset.index);
  if (event.target.checked) {
    if (state.selectedPidIndexes.length >= 2) {
      event.target.checked = false;
      setScanState('一次最多选择两个 PID', true);
      return;
    }
    state.selectedPidIndexes.push(index);
  } else {
    state.selectedPidIndexes = state.selectedPidIndexes.filter((item) => item !== index);
  }
  renderModelInfo();
}

function defaultUpper(valueNow, floor, multiplier = 4) {
  const numeric = Math.abs(Number(valueNow) || 0);
  return Math.max(floor, numeric * multiplier);
}

function renderPidEditors() {
  const blocks = state.modelInfo?.pidBlocks || [];
  el('pidEditors').innerHTML = state.selectedPidIndexes.map((index, position) => {
    const block = blocks[index];
    const current = block.currentPid || {};
    const ranges = {
      Kp: [0, defaultUpper(current.Kp, 10)], Ki: [0, defaultUpper(current.Ki, 10)],
      Kd: [0, defaultUpper(current.Kd, 2)], N: [1, defaultUpper(current.N, 500, 5)],
    };
    const controls = Object.entries(ranges).map(([field, pair]) => `
      <div class="bound-control"><span>${field}</span><div class="range-inputs">
      <input id="pid-${index}-${field}-min" type="number" step="any" value="${pair[0]}" aria-label="${field} 最小值" />
      <input id="pid-${index}-${field}-max" type="number" step="any" value="${pair[1]}" aria-label="${field} 最大值" />
      </div></div>`).join('');
    return `<section class="pid-editor"><h5>PID ${position + 1}</h5>
      <input id="pid-${index}-name" value="${escapeHtml(block.name || `pid${position + 1}`)}" aria-label="PID 名称" />
      <div class="block-path">${escapeHtml(block.path)}</div><div class="bounds-grid">${controls}</div></section>`;
  }).join('') || '<div class="warn">请至少选择一个 PID。</div>';
}

function numberFrom(id) {
  const result = Number(el(id).value);
  if (!Number.isFinite(result)) throw new Error(`${id} 必须是数字`);
  return result;
}

/* =========================================================================
   AI Configuration Modal
   ========================================================================= */

function applyPresetToRemote(presetObj) {
  el('modalApiBaseUrl').value = presetObj.baseUrl || '';
  el('modalApiModel').value = presetObj.model || '';
}

function initApiPresets() {
  const selectEl = el('modalApiPreset');
  selectEl.innerHTML = AI_PRESETS.remote.map((preset, index) =>
    '<option value="' + index + '">' + preset.label + '</option>'
  ).join('');
  const currentBaseUrl = el('modalApiBaseUrl').value;
  const matchIndex = AI_PRESETS.remote.findIndex((preset) => preset.baseUrl === currentBaseUrl);
  selectEl.value = String(matchIndex >= 0 ? matchIndex : AI_PRESETS.remote.length - 1);
}

function updateAgentFields() {
  const type = el('modalAgentType').value;
  el('modalAgentNameField').classList.toggle('hidden', type !== 'minimax');
  const discovered = modalState.agents.find((agent) => agent.id === type);
  if (discovered && discovered.installed && !el('modalAgentExecutable').value.trim()) {
    el('modalAgentExecutable').value = discovered.executable;
  }
  if (discovered) {
    el('modalAgentStatus').textContent = discovered.installed ? '已发现本机 CLI' : '未发现，请填写可执行文件';
    el('modalAgentStatus').classList.toggle('ok', discovered.installed);
    el('modalAgentStatus').classList.toggle('error', !discovered.installed);
  }
}

async function discoverAgents() {
  const status = el('modalAgentStatus');
  status.textContent = '正在发现本机 Code Agent...';
  status.classList.remove('ok', 'error');
  try {
    const payload = await api('/api/ai/agents');
    modalState.agents = payload.agents || [];
    const current = modalState.agents.find((agent) => agent.id === el('modalAgentType').value);
    if (current && current.installed) el('modalAgentExecutable').value = current.executable;
    updateAgentFields();
  } catch (error) {
    status.textContent = '发现失败：' + error.message;
    status.classList.add('error');
  }
}

async function testSelectedAgent() {
  const button = el('agentTestButton');
  const status = el('modalAgentStatus');
  button.disabled = true;
  status.textContent = '正在测试 CLI...';
  status.classList.remove('ok', 'error');
  try {
    const payload = await api('/api/ai/agents/test', jsonPost({
      type: el('modalAgentType').value,
      executable: el('modalAgentExecutable').value.trim(),
    }));
    status.textContent = payload.versionOutput || 'CLI 可用';
    status.classList.add('ok');
  } catch (error) {
    status.textContent = '测试失败：' + error.message;
    status.classList.add('error');
  } finally {
    button.disabled = false;
  }
}

function switchAiTab(method) {
  modalState.method = method;
  document.querySelectorAll('.ai-tab').forEach((tab) => tab.classList.toggle('active', tab.dataset.method === method));
  el('modalNoneSection').classList.toggle('hidden', method !== 'none');
  el('modalApiSection').classList.toggle('hidden', method !== 'api');
  el('modalAgentSection').classList.toggle('hidden', method !== 'agent');
  if (method === 'api') initApiPresets();
  if (method === 'agent' && !modalState.agents.length) discoverAgents();
}

function openAiModal() {
  const method = el('aiModeSelect').value || 'none';
  el('modalAiCandidateCount').value = el('aiCandidateCountInput').value;
  el('modalAiFailOnError').checked = el('aiFailOnErrorInput').checked;
  el('modalApiBaseUrl').value = el('aiBaseUrlInput').value;
  el('modalApiModel').value = el('aiModelInput').value;
  el('modalApiKey').value = el('aiApiKeyInput').value;
  el('modalApiTemperature').value = el('aiTemperatureInput').value;
  el('modalApiMaxTokens').value = '2000';
  el('modalApiTimeout').value = el('aiApiTimeoutInput').value;
  el('modalAgentType').value = el('agentTypeInput').value || 'codex';
  el('modalAgentExecutable').value = el('agentExecutableInput').value;
  el('modalAgentModel').value = el('agentModelInput').value;
  el('modalAgentName').value = el('agentNameInput').value || 'mavis';
  el('modalAgentTimeout').value = el('agentTimeoutInput').value || '180';
  switchAiTab(method);
  updateAgentFields();
  el('aiModalBackdrop').classList.remove('hidden');
}

function closeAiModal() {
  el('aiModalBackdrop').classList.add('hidden');
}

function applyAiConfig() {
  const method = modalState.method;
  el('aiModeSelect').value = method;
  if (method === 'api') {
    el('aiBaseUrlInput').value = el('modalApiBaseUrl').value.trim();
    el('aiModelInput').value = el('modalApiModel').value.trim();
    el('aiApiKeyInput').value = el('modalApiKey').value.trim();
    el('aiTemperatureInput').value = el('modalApiTemperature').value;
    el('aiApiTimeoutInput').value = el('modalApiTimeout').value;
  } else if (method === 'agent') {
    el('agentTypeInput').value = el('modalAgentType').value;
    el('agentExecutableInput').value = el('modalAgentExecutable').value.trim();
    el('agentModelInput').value = el('modalAgentModel').value.trim();
    el('agentNameInput').value = el('modalAgentName').value.trim() || 'mavis';
    el('agentTimeoutInput').value = el('modalAgentTimeout').value;
    el('aiApiKeyInput').value = '';
  } else {
    el('aiApiKeyInput').value = '';
  }
  el('aiCandidateCountInput').value = el('modalAiCandidateCount').value;
  el('aiFailOnErrorInput').checked = el('modalAiFailOnError').checked;
  saveAiConfigToStorage();
  updateAiSummary();
  closeAiModal();
}

function saveAiConfigToStorage() {
  try {
    const cfg = {
      method: el('aiModeSelect').value,
      apiBaseUrl: el('aiBaseUrlInput').value,
      apiModel: el('aiModelInput').value,
      apiTemperature: el('aiTemperatureInput').value,
      apiTimeout: el('aiApiTimeoutInput').value,
      candidateCount: el('aiCandidateCountInput').value,
      failOnError: el('aiFailOnErrorInput').checked,
      agentType: el('agentTypeInput').value,
      agentExecutable: el('agentExecutableInput').value,
      agentModel: el('agentModelInput').value,
      agentName: el('agentNameInput').value,
      agentTimeout: el('agentTimeoutInput').value,
    };
    localStorage.setItem('pidAiConfig', JSON.stringify(cfg));
  } catch (error) { /* localStorage unavailable */ }
}

function restoreAiConfigFromStorage() {
  try {
    const raw = localStorage.getItem('pidAiConfig');
    if (!raw) return false;
    const cfg = JSON.parse(raw);
    if (Object.prototype.hasOwnProperty.call(cfg, 'apiKey')) {
      delete cfg.apiKey;
      localStorage.setItem('pidAiConfig', JSON.stringify(cfg));
    }
    el('aiModeSelect').value = ['none', 'api', 'agent'].includes(cfg.method) ? cfg.method : 'none';
    if (cfg.apiBaseUrl !== undefined) el('aiBaseUrlInput').value = cfg.apiBaseUrl;
    if (cfg.apiModel !== undefined) el('aiModelInput').value = cfg.apiModel;
    if (cfg.apiTemperature !== undefined) el('aiTemperatureInput').value = cfg.apiTemperature;
    if (cfg.apiTimeout !== undefined) el('aiApiTimeoutInput').value = cfg.apiTimeout;
    if (cfg.candidateCount !== undefined) el('aiCandidateCountInput').value = cfg.candidateCount;
    if (cfg.failOnError !== undefined) el('aiFailOnErrorInput').checked = cfg.failOnError;
    if (cfg.agentType !== undefined) el('agentTypeInput').value = cfg.agentType;
    if (cfg.agentExecutable !== undefined) el('agentExecutableInput').value = cfg.agentExecutable;
    if (cfg.agentModel !== undefined) el('agentModelInput').value = cfg.agentModel;
    if (cfg.agentName !== undefined) el('agentNameInput').value = cfg.agentName;
    if (cfg.agentTimeout !== undefined) el('agentTimeoutInput').value = cfg.agentTimeout;
    el('aiApiKeyInput').value = '';
    return true;
  } catch (error) {
    return false;
  }
}

function updateAiSummary() {
  const method = el('aiModeSelect').value;
  const summaryEl = el('aiSummaryText');
  summaryEl.classList.remove('active-ai');
  if (method === 'api') {
    summaryEl.textContent = '远程 API · ' + (el('aiModelInput').value || '未指定模型');
    summaryEl.classList.add('active-ai');
  } else if (method === 'agent') {
    const labels = { codex: 'Codex CLI', minimax: 'MiniMax Code', claude: 'Claude Code' };
    summaryEl.textContent = 'Code Agent · ' + (labels[el('agentTypeInput').value] || el('agentTypeInput').value);
    summaryEl.classList.add('active-ai');
  } else {
    summaryEl.textContent = '未启用 AI';
  }
}

function collectAiConfig() {
  const mode = el('aiModeSelect').value;
  const config = {
    mode,
    candidatesPerIteration: mode === 'none' ? 0 : numberFrom('aiCandidateCountInput'),
    maxHistoryRecords: 12,
    failOnError: el('aiFailOnErrorInput').checked,
  };
  if (mode === 'api') {
    config.api = {
      baseUrl: el('aiBaseUrlInput').value.trim(),
      model: el('aiModelInput').value.trim(),
      apiKey: el('aiApiKeyInput').value.trim(),
      temperature: numberFrom('aiTemperatureInput'),
      timeoutSeconds: numberFrom('aiApiTimeoutInput'),
      maxTokens: 2000,
    };
  } else if (mode === 'agent') {
    config.agent = {
      type: el('agentTypeInput').value,
      executable: el('agentExecutableInput').value.trim(),
      model: el('agentModelInput').value.trim(),
      name: el('agentNameInput').value.trim() || 'mavis',
      timeoutSeconds: numberFrom('agentTimeoutInput'),
      pythonExe: 'python',
    };
  }
  return config;
}
function collectCustomConfig() {
  if (!state.modelInfo) throw new Error('请先读取 Simulink 模型。');
  if (!state.selectedPidIndexes.length) throw new Error('请至少选择一个 PID。');
  const blocks = state.modelInfo.pidBlocks;
  const pidBlocks = state.selectedPidIndexes.map((index) => {
    const bounds = {};
    ['Kp', 'Ki', 'Kd', 'N'].forEach((field) => {
      bounds[field] = [numberFrom(`pid-${index}-${field}-min`), numberFrom(`pid-${index}-${field}-max`)];
    });
    return { name: el(`pid-${index}-name`).value.trim(), path: blocks[index].path, bounds };
  });
  return {
    modelPath: state.modelInfo.modelPath || el('modelPathInput').value.trim(), pidBlocks,
    referenceSignalName: el('referenceSignalInput').value.trim(), outputSignalName: el('outputSignalInput').value.trim(),
    controlSignalName: el('controlSignalInput').value.trim(), stopTime: el('stopTimeInput').value,
    maxIterations: numberFrom('maxIterationsInput'), numCandidates: numberFrom('numCandidatesInput'),
    stopOnFirstPass: el('stopOnFirstPassInput').checked,
    ai: collectAiConfig(),
    targets: {
      overshootPctMax: numberFrom('overshootTargetInput'), settlingTimeMax: numberFrom('settlingTargetInput'),
      steadyStateErrorAbsMax: numberFrom('errorTargetInput'),
    },
  };
}

async function startCustom() {
  const button = el('startCustomButton');
  button.disabled = true;
  button.textContent = '启动 MATLAB 中...';
  try {
    const payload = await api('/api/pid/jobs/custom', jsonPost(collectCustomConfig()));
    state.activeJobId = payload.jobId;
    await refreshJob();
  } catch (error) {
    setScanState(`启动失败：${error.message}`, true);
  } finally {
    button.disabled = false;
    button.textContent = '启动当前模型调参';
  }
}

async function startSingleDemo() {
  const button = el('startSingleDemoButton');
  button.disabled = true;
  button.textContent = '启动中...';
  try {
    const payload = await api('/api/pid/jobs/demo/single', { method: 'POST' });
    state.activeJobId = payload.jobId;
    await refreshJob();
  } catch (error) {
    el('connectionState').textContent = `启动失败：${error.message}`;
  } finally {
    button.disabled = false;
    button.textContent = '运行单 PID Demo';
  }
}
async function startBuckDemo() {
  const button = el('startBuckDemoButton');
  button.disabled = true;
  button.textContent = '启动 Buck 仿真中...';
  try {
    const payload = await api('/api/pid/jobs/demo/buck', { method: 'POST' });
    state.activeJobId = payload.jobId;
    await refreshJob();
  } catch (error) {
    el('connectionState').textContent = `Buck Demo 启动失败：${error.message}`;
  } finally {
    button.disabled = false;
    button.textContent = 'Buck 双环电路 Demo';
  }
}

async function startDemo() {
  const button = el('startDemoButton');
  button.disabled = true;
  button.textContent = '启动中...';
  try {
    const payload = await api('/api/pid/jobs/demo', { method: 'POST' });
    state.activeJobId = payload.jobId;
    await refreshJob();
  } catch (error) {
    el('connectionState').textContent = `启动失败：${error.message}`;
  } finally {
    button.disabled = false;
    button.textContent = '运行双 PID Demo';
  }
}

function bindNavigation() {
  document.querySelectorAll('.nav-item').forEach((button) => button.addEventListener('click', () => {
    document.querySelectorAll('.nav-item').forEach((item) => item.classList.remove('active'));
    document.querySelectorAll('.view').forEach((view) => view.classList.remove('active'));
    button.classList.add('active');
    el(`view-${button.dataset.view}`).classList.add('active');
  }));
}

function init() {
  bindNavigation();
  el('refreshButton').addEventListener('click', refreshJob);
  el('startSingleDemoButton').addEventListener('click', startSingleDemo);
  el('startBuckDemoButton').addEventListener('click', startBuckDemo);
  el('startDemoButton').addEventListener('click', startDemo);
  el('selectModelButton').addEventListener('click', selectModel);
  el('discoverModelButton').addEventListener('click', discoverModel);
  el('startCustomButton').addEventListener('click', startCustom);
  el('modelPathInput').addEventListener('keydown', (event) => { if (event.key === 'Enter') discoverModel(); });

  /* -- AI modal bindings -- */
  el('openAiConfigButton').addEventListener('click', openAiModal);
  el('aiFabButton').addEventListener('click', openAiModal);
  el('aiModalClose').addEventListener('click', closeAiModal);
  el('aiModalCancel').addEventListener('click', closeAiModal);
  el('aiModalApply').addEventListener('click', applyAiConfig);
  el('aiModalBackdrop').addEventListener('click', (e) => { if (e.target === el('aiModalBackdrop')) closeAiModal(); });

  document.querySelectorAll('.ai-tab').forEach((tab) => {
    tab.addEventListener('click', () => switchAiTab(tab.dataset.method));
  });
  el('modalApiPreset').addEventListener('change', () => {
    const idx = Number(el('modalApiPreset').value);
    if (AI_PRESETS.remote[idx]) applyPresetToRemote(AI_PRESETS.remote[idx]);
  });
  el('modalAgentType').addEventListener('change', () => {
    el('modalAgentExecutable').value = '';
    updateAgentFields();
  });
  el('agentDiscoverButton').addEventListener('click', discoverAgents);
  el('agentTestButton').addEventListener('click', testSelectedAgent);

  renderHistory([]); renderRecent([]); renderPidRows('currentPidRows', null); renderPidRows('bestPidRows', null);
  el('currentMetrics').innerHTML = metricRows({}); el('bestMetrics').innerHTML = metricRows({});
  restoreAiConfigFromStorage();
  updateAiSummary();
  refreshJob();
  state.pollHandle = window.setInterval(refreshJob, 1200);
}

window.addEventListener('DOMContentLoaded', init);
