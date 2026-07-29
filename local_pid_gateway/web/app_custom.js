const state = {
  activeJobId: null,
  status: null,
  history: [],
  pollHandle: null,
  modelInfo: null,
  selectedPidIndexes: [],
  embedded: false,
  apiBaseUrl: '',
  simulinkContext: null,
  signalMappingModelKey: '',
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

const EFFECT_METRICS = [
  { label: '超调量 (%)', key: 'overshootPct', target: 'overshootPctMax' },
  { label: '调节时间 (s)', key: 'settlingTime', target: 'settlingTimeMax' },
  { label: '稳态误差', key: 'steadyStateError', target: 'steadyStateErrorAbsMax', absolute: true },
  { label: 'IAE', key: 'iae', target: 'iaeMax' },
  { label: 'ISE', key: 'ise', target: 'iseMax' },
  { label: 'ITAE', key: 'itae', target: 'itaeMax' },
  { label: '最大控制量', key: 'maxAbsControl', target: 'maxAbsControlMax' },
  { label: '控制能量', key: 'controlEnergy', target: 'controlEnergyMax' },
  { label: '电流峰值', key: 'maxAbsCurrent', target: 'maxAbsCurrentMax' },
  { label: '输出纹波', key: 'outputRipple', target: 'outputRippleMax' },
  { label: '控制饱和比例', key: 'controlSaturationFraction', target: 'controlSaturationFractionMax' },
];

const FAILURE_LABELS = {
  simulation_failed: '仿真执行失败',
  non_finite_output: '输出包含无效数值',
  unstable_or_unsettled: '闭环不稳定或未收敛',
  overshoot: '超调量超限',
  settling_time: '调节时间超限',
  steady_state_error: '稳态误差超限',
  iae: 'IAE 超限',
  ise: 'ISE 超限',
  itae: 'ITAE 超限',
  max_abs_control: '控制量峰值超限',
  control_energy: '控制能量超限',
  max_abs_current: '电流峰值超限',
  output_ripple: '输出纹波超限',
  control_saturation: '控制饱和时间超限',
  tracking_rmse: '跟踪 RMSE 超限',
  disturbance_peak: '扰动峰值超限',
};

function failureLabel(failure) {
  const text = String(failure || '');
  const parts = text.split(':');
  const code = parts[parts.length - 1];
  const label = FAILURE_LABELS[code] || code.replaceAll('_', ' ');
  if (parts[0] === 'loop' && parts.length >= 3) return `${parts[1]}：${label}`;
  return FAILURE_LABELS[text] || label || text;
}

function finiteMetric(record, definition) {
  const raw = record?.metrics?.[definition.key];
  if (raw === null || raw === undefined || raw === '') return null;
  const number = Number(raw);
  if (!Number.isFinite(number)) return null;
  return definition.absolute ? Math.abs(number) : number;
}

function targetFor(payload, definition) {
  const raw = payload?.targets?.[definition.target];
  const number = Number(raw);
  if (raw !== null && raw !== undefined && raw !== '' && Number.isFinite(number)) return number;
  const fallbackIds = {
    overshootPctMax: 'overshootTargetInput',
    settlingTimeMax: 'settlingTargetInput',
    steadyStateErrorAbsMax: 'errorTargetInput',
  };
  const input = fallbackIds[definition.target] ? el(fallbackIds[definition.target]) : null;
  const fallback = Number(input?.value);
  return Number.isFinite(fallback) ? fallback : null;
}

function effectNumber(number) {
  return Number.isFinite(number) ? fmt.format(number) : '-';
}

function scoreImprovement(baseline, record) {
  if (!baseline?.passed || !record?.passed) return null;
  const baselineScore = Number(baseline?.score);
  const currentScore = Number(record?.score);
  if (!Number.isFinite(baselineScore) || !Number.isFinite(currentScore) || Math.abs(baselineScore) < 1e-12) return null;
  return ((baselineScore - currentScore) / Math.abs(baselineScore)) * 100;
}

function renderEffectEvaluation(payload) {
  const baseline = recordOrNull(payload?.baseline);
  const current = recordOrNull(payload?.current);
  const bestPassing = recordOrNull(payload?.bestPassing);
  const bestScored = recordOrNull(payload?.best);
  const best = bestPassing || bestScored;
  const completed = String(payload?.status || '').toLowerCase() === 'completed';
  const evaluated = completed ? (bestPassing || bestScored || current) : (current || bestPassing || bestScored);
  const improvement = scoreImprovement(baseline, evaluated);
  const failures = Array.isArray(evaluated?.failures) ? evaluated.failures.map(String) : [];
  const passed = Boolean(evaluated?.passed);
  el('currentPass').innerHTML = passText(evaluated);

  const grade = el('effectGrade');
  const verdict = el('effectVerdict');
  const title = el('effectVerdictTitle');
  const detail = el('effectVerdictDetail');
  if (!evaluated) {
    grade.textContent = '--';
    verdict.className = 'effect-verdict neutral';
    title.textContent = '等待仿真结果';
    detail.textContent = '完成基线和候选仿真后给出结论';
  } else if (!passed) {
    grade.textContent = 'D';
    verdict.className = 'effect-verdict failed';
    title.textContent = `不可用：未通过 ${Math.max(1, failures.length)} 项硬指标`;
    detail.textContent = '该组参数不能作为最终 PID';
  } else if (baseline && !baseline.passed) {
    grade.textContent = 'A';
    verdict.className = 'effect-verdict passed';
    title.textContent = '候选参数已通过，原始 PID 未通过硬指标';
    detail.textContent = '当前结果首次达到可用门槛，仍需完成工况验证';
  } else if (improvement !== null && improvement < 0) {
    grade.textContent = 'C';
    verdict.className = 'effect-verdict warning';
    title.textContent = '指标通过，但不建议替换原参数';
    detail.textContent = `综合分数相对基线退化 ${fmt.format(Math.abs(improvement))}%`;
  } else {
    const letter = improvement === null ? 'PASS' : (improvement >= 20 ? 'A' : (improvement >= 5 ? 'B' : 'C'));
    grade.textContent = letter;
    verdict.className = 'effect-verdict passed';
    title.textContent = '通过全部硬指标，可进入下一步验证';
    detail.textContent = improvement === null ? '缺少基线，暂不计算改善幅度' : `综合分数相对原始 PID 改善 ${fmt.format(improvement)}%`;
  }

  const gateList = el('effectGateList');
  if (!evaluated) {
    gateList.innerHTML = '<span class="gate-chip neutral">尚无硬指标结果</span>';
  } else if (failures.length) {
    gateList.innerHTML = failures.map((failure) => `<span class="gate-chip failed">${escapeHtml(failureLabel(failure))}</span>`).join('');
  } else {
    gateList.innerHTML = ['仿真成功', '数值有效', '闭环稳定', '固定指标全部通过']
      .map((label) => `<span class="gate-chip passed">${label}</span>`).join('');
  }

  el('effectComparisonRows').innerHTML = EFFECT_METRICS.map((definition) => {
    const baselineValue = finiteMetric(baseline, definition);
    const currentValue = finiteMetric(current, definition);
    const bestValue = finiteMetric(best, definition);
    const target = targetFor(payload, definition);
    let judgment = '<span class="metric-judgment neutral">未设置限制</span>';
    if (currentValue === null) judgment = '<span class="metric-judgment neutral">暂无</span>';
    else if (target !== null && currentValue <= target) judgment = '<span class="metric-judgment passed">通过</span>';
    else if (target !== null) judgment = '<span class="metric-judgment failed">超限</span>';
    return `<tr><td>${definition.label}</td><td>${effectNumber(baselineValue)}</td><td>${effectNumber(currentValue)}</td>` +
      `<td>${effectNumber(bestValue)}</td><td>${target === null ? '未设置' : effectNumber(target)}</td><td>${judgment}</td></tr>`;
  }).join('');
  const baselineScore = Number(baseline?.score);
  const bestScoreValue = Number(best?.score);
  el('effectComparisonSummary').textContent = Number.isFinite(baselineScore) && Number.isFinite(bestScoreValue)
    ? `基线分数 ${fmt.format(baselineScore)} · 最佳分数 ${fmt.format(bestScoreValue)}`
    : '原始 PID、当前候选与最佳结果';
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

function sourceLabel(record) {
  const source = candidateSource(record);
  const agentLabels = {
    codex: 'Codex',
    minimax: 'MiniMax',
    claude: 'Claude',
    qwen: 'Qwen',
    kimi: 'Kimi',
    codebuddy: 'CodeBuddy',
  };
  if (source === 'baseline') return '原始基线';
  if (source === 'ai:api') return '远程 API';
  if (source.startsWith('agent:')) return 'Code Agent · ' + (agentLabels[source.split(':')[1]] || source.split(':')[1]);
  if (source.startsWith('ai:')) return 'AI';
  return '程序搜索';
}

function sourceHtml(record) {
  const source = candidateSource(record);
  const aiSource = source.startsWith('ai:') || source.startsWith('agent:');
  return '<span class="' + (aiSource ? 'source-ai' : 'source-program') + '">' + escapeHtml(sourceLabel(record)) + '</span>';
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
  if (Array.isArray(failures)) return failures.map(failureLabel).join('; ') || '-';
  if (failures && typeof failures === 'object') return Object.values(failures).map(failureLabel).join('; ') || '-';
  return failures ? failureLabel(failures) : '-';
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
  el('currentSummary').textContent = current ? `${sourceLabel(current)} · 候选 ${value(current.candidateIndex)} / 分数 ${value(current.score)}` : '暂无';
  renderPidRows('currentPidRows', current);
  renderEffectEvaluation(payload);
  renderRecent(payload.recent || []);

  const bestPassing = recordOrNull(payload.bestPassing);
  const bestScored = recordOrNull(payload.best);
  const best = bestPassing || bestScored;
  el('bestKind').textContent = bestPassing ? '已通过最优' : (bestScored ? '当前最低分' : '暂无');
  el('bestScore').textContent = best ? `score=${value(best.score)}` : '暂无';
  renderPidRows('bestPidRows', best);
  el('bestMetrics').innerHTML = metricRows(pickMetrics(best));
}

function apiUrl(path) {
  if (/^https?:\/\//i.test(path)) return path;
  const base = String(state.apiBaseUrl || '').replace(/\/$/, '');
  return base ? `${base}${path}` : path;
}

const pendingGatewayRequests = new Map();
let gatewayRequestSequence = 0;

function apiViaMatlab(path, options = {}) {
  return new Promise((resolve, reject) => {
    gatewayRequestSequence += 1;
    const id = `gateway-${Date.now()}-${gatewayRequestSequence}`;
    let body = null;
    if (options.body) {
      try { body = JSON.parse(options.body); } catch (_) { body = options.body; }
    }
    const timeout = window.setTimeout(() => {
      pendingGatewayRequests.delete(id);
      reject(new Error('MATLAB 网关代理请求超时'));
    }, 360000);
    pendingGatewayRequests.set(id, { resolve, reject, timeout });
    const sent = sendMatlabEvent('GatewayRequest', {
      id,
      path,
      method: String(options.method || 'GET').toUpperCase(),
      body,
    });
    if (!sent) {
      window.clearTimeout(timeout);
      pendingGatewayRequests.delete(id);
      reject(new Error('MATLAB 通信桥尚未就绪'));
    }
  });
}

function handleMatlabGatewayResponse(event) {
  const data = event?.Data || event?.detail || event || {};
  const pending = pendingGatewayRequests.get(String(data.id || ''));
  if (!pending) return;
  window.clearTimeout(pending.timeout);
  pendingGatewayRequests.delete(String(data.id));
  if (data.ok) {
    pending.resolve(data.payload ?? {});
  } else {
    const payload = data.payload ?? {};
    const error = new Error(String(payload.message || payload.error || data.error || '本地网关请求失败'));
    error.code = payload.code || '';
    error.field = payload.field || '';
    error.requestId = payload.requestId || '';
    error.statusCode = Number(data.statusCode || 0);
    pending.reject(error);
  }
}

async function api(path, options = {}) {
  if (state.embedded && window.pidMatlabComponent) return apiViaMatlab(path, options);
  const response = await fetch(apiUrl(path), options);
  let payload = {};
  try { payload = await response.json(); } catch (_) { payload = {}; }
  if (!response.ok) {
    const error = new Error(payload.message || payload.error || `${response.status} ${response.statusText}`);
    error.code = payload.code || '';
    error.field = payload.field || '';
    error.requestId = payload.requestId || response.headers.get('X-Request-ID') || '';
    error.statusCode = response.status;
    throw error;
  }
  return payload;
}
function apiErrorText(error, action) {
  const message = String(error?.message || error || '未知错误');
  if (/failed to fetch|networkerror|load failed/i.test(message)) {
    return `${action}失败：无法连接本地 PID 网关，请重新打开 PID Agent 后再试`;
  }
  const field = error?.field ? `；字段：${error.field}` : '';
  const requestId = error?.requestId ? `；请求：${error.requestId}` : '';
  return `${action}失败：${message}${field}${requestId}`;
}

function jsonPost(body) {
  return { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

async function refreshHealth() {
  try {
    const payload = await api('/api/health');
    el('connectionState').textContent = payload.matlabAvailable ? 'MATLAB 已连接' : '网关已连接，未找到 MATLAB';
    sendMatlabEvent('GatewayStatus', { ok: true, matlabAvailable: Boolean(payload.matlabAvailable) });
    return true;
  } catch (error) {
    el('connectionState').textContent = '本地网关未连接';
    sendMatlabEvent('GatewayStatus', { ok: false, error: String(error?.message || error) });
    return false;
  }
}

async function chooseLatestJob() {
  const payload = await api('/api/pid/jobs');
  const jobs = payload.jobs || [];
  if (!state.activeJobId && jobs.length) state.activeJobId = jobs[0].jobId;
}

async function refreshJob() {
  const gatewayReady = await refreshHealth();
  if (!gatewayReady) return;
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
  if (state.embedded) {
    setScanState('正在从 Simulink 同步当前模型');
    sendMatlabEvent('SyncCurrentModel', {});
    return;
  }
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
  el('signalMappingConfirmedInput').checked = false;
  el('modelConfigBody').classList.remove('hidden');
  el('discoveredPidRows').innerHTML = blocks.length ? blocks.map((block, index) => {
    const selected = state.selectedPidIndexes.includes(index);
    const current = block.currentPid || {};
    return `<tr class="${selected ? 'selected' : ''}">
      <td><input class="pid-select" type="checkbox" data-index="${index}" ${selected ? 'checked' : ''} /></td>
      <td>${escapeHtml(block.name)}</td><td title="${escapeHtml(block.path)}">${escapeHtml(block.path)}</td>
      <td>${value(current.Kp)}</td><td>${value(current.Ki)}</td><td>${value(current.Kd)}</td><td>${value(current.N)}</td>
      <td>${state.embedded ? `<button class="pid-locate-button" type="button" data-index="${index}" title="在 Simulink 中定位">定位</button>` : '-'}</td></tr>`;
  }).join('') : '<tr><td colspan="8">未发现带 P/I/D 参数的 PID Controller 块</td></tr>';
  document.querySelectorAll('.pid-select').forEach((checkbox) => checkbox.addEventListener('change', togglePidSelection));
  document.querySelectorAll('.pid-locate-button').forEach((button) => button.addEventListener('click', locatePidFromTable));
  renderPidEditors();
  renderSignalMapping();
}

function loggedSignalNames() {
  return stringArray(state.modelInfo?.loggedSignals).filter((name) => name.trim());
}

function signalOptions(selectedValue = '', optional = false) {
  const signals = loggedSignalNames();
  const placeholder = optional ? '不检查' : '请选择已记录信号';
  const options = [`<option value="">${placeholder}</option>`];
  signals.forEach((name) => {
    const selected = name === selectedValue ? ' selected' : '';
    options.push(`<option value="${escapeHtml(name)}"${selected}>${escapeHtml(name)}</option>`);
  });
  return options.join('');
}

function evaluationPidIndex() {
  const index = Number(el('evaluationPidSelect')?.value);
  return Number.isInteger(index) && state.selectedPidIndexes.includes(index) ? index : null;
}

function preferredSignal(previous) {
  return loggedSignalNames().includes(previous) ? previous : '';
}

function renderSignalMapping() {
  const evaluationSelect = el('evaluationPidSelect');
  if (!evaluationSelect) return;
  const previousPid = evaluationPidIndex();
  const modelKey = String(state.modelInfo?.modelPath || state.modelInfo?.modelName || '');
  const sameModel = state.signalMappingModelKey === modelKey;
  const previous = {
    reference: sameModel ? el('referenceSignalInput').value : '',
    output: sameModel ? el('outputSignalInput').value : '',
    control: sameModel ? el('controlSignalInput').value : '',
    current: sameModel ? el('currentSignalInput').value : '',
  };
  state.signalMappingModelKey = modelKey;
  evaluationSelect.innerHTML = state.selectedPidIndexes.map((index, position) => {
    const block = state.modelInfo?.pidBlocks?.[index] || {};
    return `<option value="${index}">PID ${position + 1} · ${escapeHtml(block.name || block.path || index)}</option>`;
  }).join('');
  if (previousPid !== null && state.selectedPidIndexes.includes(previousPid)) {
    evaluationSelect.value = String(previousPid);
  }

  const resolved = {
    reference: preferredSignal(previous.reference),
    output: preferredSignal(previous.output),
    control: preferredSignal(previous.control),
    current: preferredSignal(previous.current),
  };
  el('referenceSignalInput').innerHTML = signalOptions(resolved.reference);
  el('outputSignalInput').innerHTML = signalOptions(resolved.output);
  el('controlSignalInput').innerHTML = signalOptions(resolved.control);
  el('currentSignalInput').innerHTML = signalOptions(resolved.current, true);
  renderSignalMappingPreview();
}

function setSuggestedSignal(id, name) {
  const normalized = String(name || '').trim();
  if (!normalized || !loggedSignalNames().includes(normalized)) return false;
  el(id).value = normalized;
  return true;
}

function applySignalSuggestion() {
  const index = evaluationPidIndex();
  const block = index === null ? null : state.modelInfo?.pidBlocks?.[index];
  const suggestion = block?.signalSuggestion || {};
  const applied = [
    setSuggestedSignal('referenceSignalInput', suggestion.referenceSignalName),
    setSuggestedSignal('outputSignalInput', suggestion.outputSignalName),
    setSuggestedSignal('controlSignalInput', suggestion.controlSignalName),
  ];
  setSuggestedSignal('currentSignalInput', suggestion.currentSignalName);
  el('signalMappingConfirmedInput').checked = false;
  renderSignalMappingPreview();
  if (!applied.every(Boolean)) {
    setScanState('拓扑建议不完整或包含未记录信号，请人工选择并确认', true);
  } else {
    setScanState('已应用拓扑建议，请核对后确认');
  }
}

function markSignalMappingChanged() {
  el('signalMappingConfirmedInput').checked = false;
  renderSignalMappingPreview();
}

function renderSignalMappingPreview() {
  const signals = new Set(loggedSignalNames());
  const roles = [
    ['有效参考值', el('referenceSignalInput').value, true],
    ['反馈 / 输出', el('outputSignalInput').value, true],
    ['控制输出', el('controlSignalInput').value, true],
    ['电流保护', el('currentSignalInput').value, false],
  ];
  const cards = roles.map(([label, name, required]) => {
    const valid = name ? signals.has(name) : !required;
    const detail = name || (required ? '尚未选择' : '未启用');
    return `<div class="signal-role"><span>${label}</span><strong class="${valid ? 'signal-ok' : 'signal-bad'}">${escapeHtml(detail)}</strong></div>`;
  }).join('');
  const index = evaluationPidIndex();
  const suggestion = index === null ? null : state.modelInfo?.pidBlocks?.[index]?.signalSuggestion;
  const confidence = Number(suggestion?.confidence);
  const noteParts = [];
  if (Number.isFinite(confidence)) noteParts.push(`拓扑建议置信度 ${Math.round(confidence * 100)}%`);
  const notes = stringArray(suggestion?.notes);
  if (notes.length) noteParts.push(notes.join('；'));
  if (!loggedSignalNames().length) noteParts.push('模型中没有已记录的命名信号，请先在 Simulink 中启用信号记录');
  el('signalMappingPreview').innerHTML = `${cards}<div class="signal-mapping-note">${escapeHtml(noteParts.join(' · ') || '请选择信号并确认映射')}</div>`;
}
function sendMatlabEvent(name, data) {
  const component = window.pidMatlabComponent;
  if (!component || typeof component.sendEventToMATLAB !== 'function') return false;
  component.sendEventToMATLAB(name, data || {});
  return true;
}

function stringArray(value) {
  if (Array.isArray(value)) return value.map(String);
  if (value === null || value === undefined || value === '') return [];
  return [String(value)];
}

function applyEmbeddedContext(context) {
  if (!context || !context.embedded) return;
  state.embedded = true;
  state.apiBaseUrl = String(context.apiBaseUrl || 'http://127.0.0.1:8788');
  state.simulinkContext = context;
  el('selectModelButton').classList.add('hidden');
  el('syncSimulinkButton').classList.remove('hidden');
  el('modelPathInput').readOnly = true;
  el('modelPathInput').value = context.modelPath || context.modelName || '';
  el('jobSubtitle').textContent = `Simulink 当前模型 · ${context.modelName || ''}`;

  const info = context.modelInfo || null;
  if (info) {
    info.pidBlocks = normalizePidBlocks(info.pidBlocks);
    info.loggedSignals = stringArray(info.loggedSignals);
    state.modelInfo = info;
    const selectedPaths = new Set(stringArray(context.selectedPidPaths));
    state.selectedPidIndexes = info.pidBlocks
      .map((block, index) => selectedPaths.has(String(block.path)) ? index : -1)
      .filter((index) => index >= 0)
      .slice(0, 2);
    if (!state.selectedPidIndexes.length && info.pidBlocks.length === 1) {
      state.selectedPidIndexes = [0];
    }
    renderModelInfo();
    const selectedNote = selectedPaths.size > 2 ? '；仅带入前两个已选 PID' : '';
    setScanState(`来自 Simulink：发现 ${info.pidBlocks.length} 个 PID${selectedNote}`);
  }
  if (context.initialView) activateView(context.initialView);
  refreshJob();
}

function locatePidFromTable(event) {
  const index = Number(event.currentTarget.dataset.index);
  const block = state.modelInfo?.pidBlocks?.[index];
  if (block?.path) sendMatlabEvent('LocatePid', { path: block.path });
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

function validationError(id, message) {
  const input = el(id);
  if (input) {
    input.classList.add('input-error');
    input.focus();
  }
  throw new Error(message);
}

function requiredText(id, label) {
  const input = el(id);
  const result = String(input?.value || '').trim();
  if (!result) validationError(id, `${label}不能为空`);
  return result;
}

function numberFrom(id, options = {}) {
  const input = el(id);
  const raw = String(input?.value ?? '').trim();
  const label = options.label || id;
  if (!raw) validationError(id, `${label}不能为空`);
  const result = Number(raw);
  if (!Number.isFinite(result)) validationError(id, `${label}必须是有限数字`);
  if (options.integer && !Number.isInteger(result)) validationError(id, `${label}必须是整数`);
  if (options.min !== undefined && result < options.min) validationError(id, `${label}不能小于 ${options.min}`);
  if (options.max !== undefined && result > options.max) validationError(id, `${label}不能大于 ${options.max}`);
  input.classList.remove('input-error');
  return result;
}

function isLocalApiUrl(urlText) {
  try {
    const hostname = new URL(urlText).hostname.toLowerCase();
    return ['127.0.0.1', 'localhost', '::1'].includes(hostname);
  } catch (_) {
    return false;
  }
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
    status.textContent = apiErrorText(error, '发现 Code Agent');
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
    status.textContent = apiErrorText(error, '测试 CLI');
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
    const labels = {
      codex: 'Codex CLI',
      minimax: 'MiniMax Code',
      claude: 'Claude Code',
      qwen: 'Qwen Code',
      kimi: 'Kimi Code CLI',
      codebuddy: 'CodeBuddy Code',
    };
    summaryEl.textContent = 'Code Agent · ' + (labels[el('agentTypeInput').value] || el('agentTypeInput').value);
    summaryEl.classList.add('active-ai');
  } else {
    summaryEl.textContent = '未启用 AI';
  }
}

function collectAiConfig(totalCandidates) {
  const mode = el('aiModeSelect').value;
  const candidateCount = mode === 'none' ? 0 : numberFrom('aiCandidateCountInput', {
    label: 'AI 每轮候选数', integer: true, min: 1, max: totalCandidates,
  });
  const config = {
    mode,
    candidatesPerIteration: candidateCount,
    maxHistoryRecords: 12,
    failOnError: el('aiFailOnErrorInput').checked,
  };
  if (mode === 'api') {
    const baseUrl = requiredText('aiBaseUrlInput', 'API Base URL');
    try { new URL(baseUrl); } catch (_) { validationError('aiBaseUrlInput', 'API Base URL 格式不正确'); }
    const apiKey = el('aiApiKeyInput').value.trim();
    if (!apiKey && !isLocalApiUrl(baseUrl)) validationError('aiApiKeyInput', '远程 API 必须填写 API Key');
    config.api = {
      baseUrl,
      model: requiredText('aiModelInput', 'API 模型名'),
      apiKey,
      temperature: numberFrom('aiTemperatureInput', { label: 'Temperature', min: 0, max: 2 }),
      timeoutSeconds: numberFrom('aiApiTimeoutInput', { label: 'API 超时', min: 5, max: 1800 }),
      maxTokens: 2000,
    };
  } else if (mode === 'agent') {
    config.agent = {
      type: el('agentTypeInput').value,
      executable: el('agentExecutableInput').value.trim(),
      model: el('agentModelInput').value.trim(),
      name: el('agentNameInput').value.trim() || 'mavis',
      timeoutSeconds: numberFrom('agentTimeoutInput', { label: 'Code Agent 超时', min: 5, max: 1800 }),
      pythonExe: 'python',
    };
  }
  return config;
}
function collectCustomConfig() {
  if (!state.modelInfo) throw new Error('请先读取 Simulink 模型。');
  if (!state.selectedPidIndexes.length || state.selectedPidIndexes.length > 2) {
    throw new Error('请选择一个或两个 PID。');
  }
  const modelPath = String(state.modelInfo.modelPath || el('modelPathInput').value || '').trim();
  if (!/\.(slx|mdl)$/i.test(modelPath)) {
    throw new Error('当前模型尚未保存为 .slx 或 .mdl 文件，请先保存模型。');
  }
  const blocks = state.modelInfo.pidBlocks;
  const pidBlocks = state.selectedPidIndexes.map((index, position) => {
    if (!blocks[index]?.path) throw new Error(`PID ${position + 1} 缺少 Simulink 块路径。`);
    const bounds = {};
    ['Kp', 'Ki', 'Kd', 'N'].forEach((field) => {
      const lowId = `pid-${index}-${field}-min`;
      const highId = `pid-${index}-${field}-max`;
      const low = numberFrom(lowId, { label: `PID ${position + 1} ${field} 最小值` });
      const high = numberFrom(highId, { label: `PID ${position + 1} ${field} 最大值` });
      if (low > high) validationError(lowId, `PID ${position + 1} 的 ${field} 最小值不能大于最大值`);
      bounds[field] = [low, high];
    });
    return { name: el(`pid-${index}-name`).value.trim() || `pid${position + 1}`, path: blocks[index].path, bounds };
  });
  const maxIterations = numberFrom('maxIterationsInput', { label: '迭代轮数', integer: true, min: 1 });
  const numCandidates = numberFrom('numCandidatesInput', { label: '每轮候选数', integer: true, min: 1 });
  const stopTime = numberFrom('stopTimeInput', { label: '仿真停止时间', min: Number.MIN_VALUE });
  const availableSignalNames = loggedSignalNames();
  const referenceSignalName = requiredText('referenceSignalInput', '有效参考值');
  const outputSignalName = requiredText('outputSignalInput', '反馈 / 被控输出');
  const controlSignalName = requiredText('controlSignalInput', 'PID 控制输出');
  const currentSignalName = String(el('currentSignalInput').value || '').trim();
  const selectedSignals = [referenceSignalName, outputSignalName, controlSignalName, currentSignalName].filter(Boolean);
  const missingSignals = selectedSignals.filter((name) => !availableSignalNames.includes(name));
  if (missingSignals.length) throw new Error(`以下信号尚未启用记录：${missingSignals.join('、')}`);
  if (referenceSignalName === outputSignalName) {
    validationError('outputSignalInput', '有效参考值和反馈输出不能选择同一信号');
  }
  if (!el('signalMappingConfirmedInput').checked) {
    validationError('signalMappingConfirmedInput', '请核对并确认效果评估信号映射');
  }
  const evaluationIndex = evaluationPidIndex();
  if (evaluationIndex === null || !blocks[evaluationIndex]?.path) {
    validationError('evaluationPidSelect', '请选择用于效果评价的主 PID');
  }
  return {
    modelPath,
    pidBlocks,
    workingDirectory: state.simulinkContext?.workingDirectory || '',
    projectRoot: state.simulinkContext?.projectRoot || '',
    projectPath: state.simulinkContext?.projectPath || '',
    referenceSignalName,
    outputSignalName,
    controlSignalName,
    currentSignalName,
    availableSignalNames,
    signalMappingConfirmed: true,
    evaluationPidPath: blocks[evaluationIndex].path,
    stopTime: String(stopTime),
    maxIterations,
    numCandidates,
    stopOnFirstPass: el('stopOnFirstPassInput').checked,
    ai: collectAiConfig(numCandidates),
    targets: {
      overshootPctMax: numberFrom('overshootTargetInput', { label: '最大超调量', min: 0 }),
      settlingTimeMax: numberFrom('settlingTargetInput', { label: '最大调节时间', min: 0 }),
      steadyStateErrorAbsMax: numberFrom('errorTargetInput', { label: '最大稳态误差', min: 0 }),
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
    setScanState(apiErrorText(error, '启动'), true);
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

function activateView(viewName) {
  const view = ['run', 'history', 'result'].includes(String(viewName)) ? String(viewName) : 'run';
  document.querySelectorAll('.nav-item').forEach((item) => item.classList.toggle('active', item.dataset.view === view));
  document.querySelectorAll('.view').forEach((item) => item.classList.toggle('active', item.id === `view-${view}`));
}

function bindNavigation() {
  document.querySelectorAll('.nav-item').forEach((button) => button.addEventListener('click', () => activateView(button.dataset.view)));
}

function init() {
  bindNavigation();
  el('refreshButton').addEventListener('click', refreshJob);
  el('startSingleDemoButton').addEventListener('click', startSingleDemo);
  el('startBuckDemoButton').addEventListener('click', startBuckDemo);
  el('startDemoButton').addEventListener('click', startDemo);
  el('selectModelButton').addEventListener('click', selectModel);
  el('discoverModelButton').addEventListener('click', discoverModel);
  el('syncSimulinkButton').addEventListener('click', () => sendMatlabEvent('SyncCurrentModel', {}));
  el('startCustomButton').addEventListener('click', startCustom);
  el('applySignalSuggestionButton').addEventListener('click', applySignalSuggestion);
  ['evaluationPidSelect', 'referenceSignalInput', 'outputSignalInput', 'controlSignalInput', 'currentSignalInput']
    .forEach((id) => el(id).addEventListener('change', markSignalMappingChanged));
  el('signalMappingConfirmedInput').addEventListener('change', renderSignalMappingPreview);
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

  renderHistory([]);
  renderRecent([]);
  renderPidRows('currentPidRows', null);
  renderPidRows('bestPidRows', null);
  renderEffectEvaluation({});
  el('bestMetrics').innerHTML = metricRows({});
  restoreAiConfigFromStorage();
  updateAiSummary();
  refreshJob();
  state.pollHandle = window.setInterval(refreshJob, 1200);
}

window.applyPidMatlabContext = applyEmbeddedContext;
window.handlePidGatewayResponse = handleMatlabGatewayResponse;
window.navigatePidAgentView = activateView;
window.addEventListener('DOMContentLoaded', init);
