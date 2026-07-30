const state = {
  activeJobId: null,
  status: null,
  history: [],
  pollHandle: null,
};

const el = (id) => document.getElementById(id);
const fmt = new Intl.NumberFormat('zh-CN', { maximumFractionDigits: 4 });

function value(v, fallback = '-') {
  if (v === null || v === undefined || v === '') return fallback;
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) return fallback;
    return fmt.format(v);
  }
  return String(v);
}

function secondsToClock(seconds) {
  const total = Math.max(0, Math.floor(Number(seconds) || 0));
  const h = String(Math.floor(total / 3600)).padStart(2, '0');
  const m = String(Math.floor((total % 3600) / 60)).padStart(2, '0');
  const s = String(total % 60).padStart(2, '0');
  return `${h}:${m}:${s}`;
}

function recordOrNull(record) {
  if (!record) return null;
  if (Array.isArray(record) && record.length === 0) return null;
  return record;
}

function pickMetrics(record) {
  return recordOrNull(record)?.metrics || {};
}

function metricValue(metrics, key) {
  return value(metrics?.[key]);
}

function metricRows(metrics) {
  const items = [
    ['超调 (%)', 'overshootPct'],
    ['调节时间 (s)', 'settlingTime'],
    ['稳态误差', 'steadyStateError'],
    ['IAE', 'iae'],
    ['ISE', 'ise'],
    ['ITAE', 'itae'],
    ['控制能量', 'controlEnergy'],
    ['最大控制量', 'maxAbsControl'],
  ];
  return items.map(([label, key]) => `
    <div class="metric-row"><span>${label}</span><strong>${metricValue(metrics, key)}</strong></div>
  `).join('');
}

function candidatePids(record) {
  const candidate = record?.candidate || {};
  if (Array.isArray(candidate.pids)) return candidate.pids;
  if (candidate.pids && typeof candidate.pids === 'object') return Object.values(candidate.pids);
  if ('Kp' in candidate || 'Ki' in candidate || 'Kd' in candidate) return [candidate];
  return [];
}

function renderPidRows(targetId, record) {
  const rows = candidatePids(record);
  el(targetId).innerHTML = rows.length ? rows.map((pid, idx) => `
    <tr>
      <td>${value(pid.name, `PID ${idx + 1}`)}</td>
      <td>${value(pid.Kp)}</td>
      <td>${value(pid.Ki)}</td>
      <td>${value(pid.Kd)}</td>
      <td>${value(pid.N)}</td>
    </tr>
  `).join('') : '<tr><td colspan="5">暂无参数</td></tr>';
}

function passText(record) {
  if (!record) return '<span class="warn">暂无</span>';
  return record.passed ? '<span class="pass">通过</span>' : '<span class="fail">未通过</span>';
}

function pidSummary(record) {
  if (!record) return '-';
  if (record.summary) return record.summary;
  return candidatePids(record).map((pid, idx) => {
    const name = value(pid.name, `PID ${idx + 1}`);
    return `${name}: Kp=${value(pid.Kp)}, Ki=${value(pid.Ki)}, Kd=${value(pid.Kd)}, N=${value(pid.N)}`;
  }).join(' | ');
}

function failureText(record) {
  const failures = record?.failures;
  if (Array.isArray(failures)) return failures.join('; ') || '-';
  if (failures && typeof failures === 'object') return Object.values(failures).join('; ') || '-';
  return value(failures);
}

function renderRecent(records) {
  const rows = records || [];
  el('recentRows').innerHTML = rows.length ? rows.map((r, idx) => `
    <tr>
      <td>${value(r.globalIndex, idx + 1)}</td>
      <td>${value(r.iteration)}</td>
      <td>${value(r.candidateIndex)}</td>
      <td>${passText(r)}</td>
      <td>${metricValue(pickMetrics(r), 'overshootPct')}</td>
      <td>${metricValue(pickMetrics(r), 'settlingTime')}</td>
      <td>${metricValue(pickMetrics(r), 'steadyStateError')}</td>
      <td>${value(r.score)}</td>
    </tr>
  `).join('') : '<tr><td colspan="8">暂无候选记录</td></tr>';
}

function renderHistory(rows) {
  const data = rows || [];
  el('historyCount').textContent = `${data.length} 条`;
  el('historyRows').innerHTML = data.length ? data.map((r, idx) => `
    <tr>
      <td>${value(r.globalIndex, idx + 1)}</td>
      <td>${value(r.timestamp)}</td>
      <td>${value(r.iteration)}</td>
      <td>${value(r.candidateIndex)}</td>
      <td title="${pidSummary(r).replaceAll('"', '&quot;')}">${pidSummary(r)}</td>
      <td>${passText(r)}</td>
      <td>${failureText(r)}</td>
      <td>${metricValue(pickMetrics(r), 'overshootPct')}</td>
      <td>${metricValue(pickMetrics(r), 'settlingTime')}</td>
      <td>${metricValue(pickMetrics(r), 'steadyStateError')}</td>
      <td>${metricValue(pickMetrics(r), 'iae')}</td>
      <td>${value(r.score)}</td>
    </tr>
  `).join('') : '<tr><td colspan="12">暂无历史记录</td></tr>';
}

function renderStatus(payload) {
  state.status = payload;
  state.activeJobId = payload.jobId || state.activeJobId;

  el('jobTitle').textContent = payload.jobId ? `任务 ${payload.jobId}` : '等待任务';
  el('jobSubtitle').textContent = payload.modelName ? `${payload.modelName} · ${value(payload.runDir)}` : '本地 MATLAB / Simulink';
  el('elapsedTime').textContent = secondsToClock(payload.elapsedSeconds);
  el('iterationText').textContent = `${value(payload.currentIteration, 0)} / ${value(payload.maxIterations, 0)}`;
  el('testedText').textContent = value(payload.testedCount, 0);
  el('passedText').textContent = value(payload.passedCount, 0);

  const status = value(payload.status, 'idle').toLowerCase();
  el('statusPill').textContent = status;
  el('statusPill').className = `status-pill ${status}`;

  const current = recordOrNull(payload.current);
  el('currentSummary').textContent = current ? `候选 ${value(current.candidateIndex)} / 分数 ${value(current.score)}` : '暂无';
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
  const res = await fetch(path, options);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

async function refreshHealth() {
  try {
    const payload = await api('/api/health');
    el('connectionState').textContent = payload.ok ? '本地网关已连接' : '网关异常';
  } catch (err) {
    el('connectionState').textContent = '本地网关未连接';
  }
}

async function chooseLatestJob() {
  const payload = await api('/api/pid/jobs');
  const jobs = payload.jobs || [];
  if (!state.activeJobId && jobs.length) state.activeJobId = jobs[0].jobId;
  return jobs;
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
  } catch (err) {
    el('connectionState').textContent = `读取失败：${err.message}`;
  }
}

function bindNavigation() {
  document.querySelectorAll('.nav-item').forEach((button) => {
    button.addEventListener('click', () => {
      document.querySelectorAll('.nav-item').forEach((b) => b.classList.remove('active'));
      document.querySelectorAll('.view').forEach((v) => v.classList.remove('active'));
      button.classList.add('active');
      el(`view-${button.dataset.view}`).classList.add('active');
    });
  });
}

function init() {
  bindNavigation();
  el('refreshButton').addEventListener('click', refreshJob);
  renderHistory([]);
  renderRecent([]);
  renderPidRows('currentPidRows', null);
  renderPidRows('bestPidRows', null);
  el('currentMetrics').innerHTML = metricRows({});
  el('bestMetrics').innerHTML = metricRows({});
  refreshJob();
  state.pollHandle = window.setInterval(refreshJob, 1200);
}

window.addEventListener('DOMContentLoaded', init);



