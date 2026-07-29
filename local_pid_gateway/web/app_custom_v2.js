/* PID Agent UI v2: per-loop tuning, staged progress, history and model actions. */

function normalizeList(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === 'object') return [value];
  return [];
}

function roleLabel(role) {
  return ({ single: '单环', inner: '内环', outer: '外环', coupled: '耦合环' })[String(role || '').toLowerCase()] || '未指定';
}

function stageLabel(stage) {
  const key = String(stage || '').toLowerCase();
  return ({
    baseline: '基线仿真', joint: '联合调节', 'inner-loop': '内环调节',
    'outer-loop': '外环调节', 'joint-refine': '联合微调', completed: '已完成',
  })[key] || String(stage || '-');
}

function stageRoleLabel(role) {
  const key = String(role || '').toLowerCase();
  return ({ inner: '内环 PID', outer: '外环 PID', joint: '全部 PID' })[key] || roleLabel(role);
}

function statusLabel(status) {
  const key = String(status || '').toLowerCase();
  return ({ idle: '空闲', queued: '排队', running: '运行中', completed: '已完成', failed: '失败' })[key] || String(status || '-');
}

function pidSystem(block) {
  const parts = String(block?.path || '').split('/').filter(Boolean);
  const parentParts = parts.slice(0, -1);
  return {
    name: parentParts.length ? parentParts[parentParts.length - 1] : '模型根级',
    path: parentParts.join('/'),
  };
}

function loopRelationshipMarkup(blocks, selected) {
  if (selected.length !== 2) return '';
  const first = blocks[selected[0]] || {};
  const second = blocks[selected[1]] || {};
  const paired = String(first.cascadePartnerPath || '') === String(second.path || '')
    && String(second.cascadePartnerPath || '') === String(first.path || '');
  const sameSystem = pidSystem(first).path && pidSystem(first).path === pidSystem(second).path;
  const kind = paired ? 'confirmed' : (sameSystem ? 'review' : 'warning');
  const text = paired ? '拓扑连接已确认' : (sameSystem ? '同一子系统，需核对内外环信号' : '跨子系统选择，必须人工确认属于同一控制系统');
  return `<div class="loop-relationship ${kind}"><strong>双环关系</strong><span>${escapeHtml(text)}</span></div>`;
}

function suggestedRole(block, total) {
  if (total === 1) return 'single';
  const role = String(block?.suggestedRole || '').toLowerCase();
  if (role === 'inner' || role === 'outer') return role;
  return 'coupled';
}

function loopValue(card, selector, fallback = '') {
  const node = card?.querySelector(selector);
  return node ? String(node.value ?? '').trim() : fallback;
}

function captureLoopConfigurations() {
  const saved = {};
  document.querySelectorAll('#loopConfigRows .loop-config').forEach((card) => {
    const path = String(card.dataset.pidPath || '');
    saved[path] = {
      role: loopValue(card, '.loop-role'),
      primary: Boolean(card.querySelector('.loop-primary')?.checked),
      reference: loopValue(card, '.loop-reference'),
      output: loopValue(card, '.loop-output'),
      control: loopValue(card, '.loop-control'),
      current: loopValue(card, '.loop-current'),
      weight: loopValue(card, '.loop-weight', '1'),
      overshoot: loopValue(card, '.loop-overshoot'),
      settling: loopValue(card, '.loop-settling'),
      error: loopValue(card, '.loop-error'),
      rmse: loopValue(card, '.loop-rmse'),
      currentMax: loopValue(card, '.loop-current-max'),
      ripple: loopValue(card, '.loop-ripple'),
      saturation: loopValue(card, '.loop-saturation'),
      controlLower: loopValue(card, '.loop-control-lower'),
      controlUpper: loopValue(card, '.loop-control-upper'),
    };
  });
  return saved;
}

function validSuggestedSignal(name) {
  const normalized = String(name || '').trim();
  return loggedSignalNames().includes(normalized) ? normalized : '';
}

function optionMarkup(values, selected) {
  return values.map(([valueText, label]) => `<option value="${escapeHtml(valueText)}"${valueText === selected ? ' selected' : ''}>${escapeHtml(label)}</option>`).join('');
}

function signalOptionsForBlock(block, selectedValue = '', optional = false) {
  const catalog = normalizeList(state.modelInfo?.loggedSignalCatalog);
  const duplicateNames = new Set(normalizeList(state.modelInfo?.duplicateLoggedSignalNames).map(String));
  const systemPath = pidSystem(block).path;
  const scoped = catalog.filter((item) => {
    const source = String(item?.sourcePath || '');
    return systemPath && (source === systemPath || source.startsWith(`${systemPath}/`));
  });
  const entries = scoped.length >= 3 ? scoped : catalog;
  if (!entries.length) return signalOptions(selectedValue, optional);
  const names = Array.from(new Set(entries.map((item) => String(item?.name || '').trim())
    .filter((name) => name && !duplicateNames.has(name))));
  const labelByName = new Map(entries.map((item) => {
    const name = String(item?.name || '').trim();
    const source = String(item?.sourcePath || '').trim();
    return [name, source ? `${name} — ${source}` : name];
  }));
  const placeholder = optional ? '不检查' : '请选择已记录的标量信号';
  return [`<option value="">${placeholder}</option>`, ...names.map((name) => {
    const selected = name === selectedValue ? ' selected' : '';
    return `<option value="${escapeHtml(name)}"${selected}>${escapeHtml(labelByName.get(name) || name)}</option>`;
  })].join('');
}

function loopSignalSelect(className, valueText, optional = false, block = null) {
  const options = block ? signalOptionsForBlock(block, valueText, optional) : signalOptions(valueText, optional);
  return `<select class="${className}">${options}</select>`;
}

function renderModelInfo() {
  const blocks = state.modelInfo?.pidBlocks || [];
  el('signalMappingConfirmedInput').checked = false;
  el('modelConfigBody').classList.remove('hidden');
  el('discoveredPidRows').innerHTML = blocks.length ? blocks.map((block, index) => {
    const selected = state.selectedPidIndexes.includes(index);
    const current = block.currentPid || {};
    const role = String(block.suggestedRole || '').toLowerCase();
    const roleClass = role === 'inner' || role === 'outer' ? role : '';
    const system = pidSystem(block);
    return `<tr class="${selected ? 'selected' : ''}">
      <td><input class="pid-select" type="checkbox" data-index="${index}" ${selected ? 'checked' : ''}></td>
      <td><span class="role-badge ${roleClass}">${escapeHtml(roleLabel(role))}</span></td>
      <td title="${escapeHtml(system.path)}">${escapeHtml(system.name)}</td>
      <td>${escapeHtml(block.name)}</td><td title="${escapeHtml(block.path)}">${escapeHtml(block.path)}</td>
      <td>${value(current.Kp)}</td><td>${value(current.Ki)}</td><td>${value(current.Kd)}</td><td>${value(current.N)}</td>
      <td>${state.embedded ? `<button class="pid-locate-button" type="button" data-index="${index}" title="在 Simulink 中定位">定位</button>` : '-'}</td></tr>`;
  }).join('') : '<tr><td colspan="10">未发现可调 PID Controller 块</td></tr>';
  document.querySelectorAll('.pid-select').forEach((checkbox) => checkbox.addEventListener('change', togglePidSelection));
  document.querySelectorAll('.pid-locate-button').forEach((button) => button.addEventListener('click', locatePidFromTable));
  renderPidEditors();
  renderSignalMapping();
}

function renderPidEditors() {
  const blocks = state.modelInfo?.pidBlocks || [];
  el('pidEditors').innerHTML = state.selectedPidIndexes.map((index, position) => {
    const block = blocks[index] || {};
    const current = block.currentPid || {};
    const kp = Number(current.Kp) || 0;
    const ki = Number(current.Ki) || 0;
    const kd = Number(current.Kd) || 0;
    const filterN = Number(current.N) || 100;
    const around = (number, zeroUpper = 1) => number > 0
      ? [Math.max(0, number / 4), number * 4]
      : (number < 0 ? [number * 4, Math.min(0, number / 4)] : [0, zeroUpper]);
    const ranges = {
      Kp: around(kp), Ki: around(ki), Kd: kd === 0 ? [0, 0] : around(kd, 0.1),
      N: kd === 0 ? [filterN, filterN] : [Math.max(1, filterN / 4), filterN * 4],
    };
    const controls = Object.entries(ranges).map(([field, pair]) => `
      <span class="bound-label">${field}</span>
      <input id="pid-${index}-${field}-min" type="number" step="any" value="${pair[0]}" aria-label="${field} 最小值">
      <input id="pid-${index}-${field}-max" type="number" step="any" value="${pair[1]}" aria-label="${field} 最大值">`).join('');
    return `<section class="pid-editor"><h4>PID ${position + 1} · ${escapeHtml(block.name || '')}</h4>
      <div class="editor-meta"><label><span>名称</span><input id="pid-${index}-name" value="${escapeHtml(block.name || `pid${position + 1}`)}"></label><span class="block-path" title="${escapeHtml(block.path)}">${escapeHtml(block.path)}</span></div>
      <div class="bounds-head"><span>参数</span><span>最小值</span><span>最大值</span></div><div class="bounds-grid">${controls}</div></section>`;
  }).join('') || '<div class="warn">请至少选择一个 PID。</div>';
}

function renderSignalMapping() {
  const saved = captureLoopConfigurations();
  const blocks = state.modelInfo?.pidBlocks || [];
  const selected = state.selectedPidIndexes;
  const total = selected.length;
  const globalTargets = {
    overshoot: el('overshootTargetInput')?.value || '10',
    settling: el('settlingTargetInput')?.value || '5',
    error: el('errorTargetInput')?.value || '0.02',
  };
  const primaryPath = selected.map((index) => blocks[index]).find((block) => String(block?.suggestedRole || '').toLowerCase() === 'outer')?.path || blocks[selected[0]]?.path;

  const loopCards = selected.map((index, position) => {
    const block = blocks[index] || {};
    const suggestion = block.signalSuggestion || {};
    const previous = saved[String(block.path)] || {};
    const role = previous.role || suggestedRole(block, total);
    const reference = previous.reference || validSuggestedSignal(suggestion.referenceSignalName);
    const output = previous.output || validSuggestedSignal(suggestion.outputSignalName);
    const control = previous.control || validSuggestedSignal(suggestion.controlSignalName);
    const current = previous.current || validSuggestedSignal(suggestion.currentSignalName);
    const primary = previous.primary !== undefined ? previous.primary : String(block.path) === String(primaryPath);
    const confidence = Number(suggestion.confidence);
    const confidenceText = Number.isFinite(confidence) ? `拓扑建议 ${Math.round(confidence * 100)}%` : '需人工核对拓扑';
    const roleOptions = total === 1
      ? [['single', '单环']]
      : [['inner', '内环'], ['outer', '外环'], ['coupled', '耦合环']];
    return `<section class="loop-config" data-pid-index="${index}" data-pid-path="${escapeHtml(block.path)}">
      <div class="loop-header"><strong>${escapeHtml(block.name || `PID ${position + 1}`)}</strong>
        <label><span>角色</span><select class="loop-role">${optionMarkup(roleOptions, role)}</select></label>
        <label><input class="loop-primary" name="primary-loop" type="radio" ${primary ? 'checked' : ''}>主评价环</label>
        <button class="loop-suggest" type="button">应用拓扑建议</button></div>
      <div class="loop-fields">
        <label><span>参考值</span>${loopSignalSelect('loop-reference', reference, false, block)}</label>
        <label><span>反馈 / 输出</span>${loopSignalSelect('loop-output', output, false, block)}</label>
        <label><span>控制输出</span>${loopSignalSelect('loop-control', control, false, block)}</label>
        <label><span>电流保护信号</span>${loopSignalSelect('loop-current', current, true, block)}</label>
      </div>
      <div class="loop-targets">
        <label><span>权重</span><input class="loop-weight" type="number" min="0.000001" step="any" value="${escapeHtml(previous.weight || '1')}"></label>
        <label><span>超调上限 (%)</span><input class="loop-overshoot" type="number" min="0" step="any" value="${escapeHtml(previous.overshoot || globalTargets.overshoot)}"></label>
        <label><span>调节时间上限 (s)</span><input class="loop-settling" type="number" min="0" step="any" value="${escapeHtml(previous.settling || globalTargets.settling)}"></label>
        <label><span>稳态误差上限</span><input class="loop-error" type="number" min="0" step="any" value="${escapeHtml(previous.error || globalTargets.error)}"></label>
        <label><span>RMSE 上限</span><input class="loop-rmse" type="number" min="0" step="any" value="${escapeHtml(previous.rmse || '')}" placeholder="可选"></label>
        <label><span>电流峰值上限</span><input class="loop-current-max" type="number" min="0" step="any" value="${escapeHtml(previous.currentMax || '')}" placeholder="可选"></label>
        <label><span>输出纹波上限</span><input class="loop-ripple" type="number" min="0" step="any" value="${escapeHtml(previous.ripple || '')}" placeholder="可选"></label>
        <label><span>最大饱和率</span><input class="loop-saturation" type="number" min="0" max="1" step="any" value="${escapeHtml(previous.saturation || '0.02')}"></label>
        <label><span>控制量下限</span><input class="loop-control-lower" type="number" step="any" value="${escapeHtml(previous.controlLower || '')}" placeholder="必须填写"></label>
        <label><span>控制量上限</span><input class="loop-control-upper" type="number" step="any" value="${escapeHtml(previous.controlUpper || '')}" placeholder="必须填写"></label>
      </div>
      <div class="loop-status"><span>${escapeHtml(confidenceText)}</span><span class="loop-validity invalid">待核对</span></div>
    </section>`;
  }).join('');
  el('loopConfigRows').innerHTML = loopRelationshipMarkup(blocks, selected)
    + (loopCards || '<div class="warn">选择 PID 后配置对应评价环路。</div>');
  state.signalMappingModelKey = String(state.modelInfo?.modelPath || state.modelInfo?.modelName || '');
  updateLoopValidity();
}

function updateLoopValidity() {
  const available = new Set(loggedSignalNames());
  document.querySelectorAll('#loopConfigRows .loop-config').forEach((card) => {
    const reference = loopValue(card, '.loop-reference');
    const output = loopValue(card, '.loop-output');
    const control = loopValue(card, '.loop-control');
    const lower = Number(loopValue(card, '.loop-control-lower'));
    const upper = Number(loopValue(card, '.loop-control-upper'));
    const signalsOkay = [reference, output, control].every((name) => available.has(name)) && reference !== output;
    const limitsOkay = Number.isFinite(lower) && Number.isFinite(upper) && lower < upper;
    const status = card.querySelector('.loop-validity');
    const okay = signalsOkay && limitsOkay;
    status.textContent = okay ? '映射与限幅完整' : (!signalsOkay ? '信号映射不完整' : '请填写有效控制限幅');
    status.className = `loop-validity ${okay ? 'valid' : 'invalid'}`;
  });
}

function applyLoopSuggestion(card) {
  const index = Number(card?.dataset.pidIndex);
  const suggestion = state.modelInfo?.pidBlocks?.[index]?.signalSuggestion || {};
  const mapping = [
    ['.loop-reference', suggestion.referenceSignalName],
    ['.loop-output', suggestion.outputSignalName],
    ['.loop-control', suggestion.controlSignalName],
    ['.loop-current', suggestion.currentSignalName],
  ];
  let complete = true;
  mapping.forEach(([selector, name], itemIndex) => {
    const valid = validSuggestedSignal(name);
    if (valid) card.querySelector(selector).value = valid;
    else if (itemIndex < 3) complete = false;
  });
  el('signalMappingConfirmedInput').checked = false;
  updateLoopValidity();
  setScanState(complete ? '已应用拓扑建议，请核对信号和限幅' : '拓扑建议不完整，请人工选择已记录信号', !complete);
}

function applySignalSuggestion() {
  document.querySelectorAll('#loopConfigRows .loop-config').forEach(applyLoopSuggestion);
}

function markSignalMappingChanged() {
  el('signalMappingConfirmedInput').checked = false;
  updateLoopValidity();
}

function renderSignalMappingPreview() {
  updateLoopValidity();
}

function optionalCardNumber(card, selector, label, options = {}) {
  const input = card.querySelector(selector);
  const raw = String(input?.value ?? '').trim();
  if (!raw) return null;
  const result = Number(raw);
  if (!Number.isFinite(result) || (options.min !== undefined && result < options.min) || (options.max !== undefined && result > options.max)) {
    input?.classList.add('input-error');
    input?.focus();
    throw new Error(`${label}填写不正确`);
  }
  input.classList.remove('input-error');
  return result;
}

function requiredCardNumber(card, selector, label, options = {}) {
  const result = optionalCardNumber(card, selector, label, options);
  if (result === null) {
    const input = card.querySelector(selector);
    input?.classList.add('input-error');
    input?.focus();
    throw new Error(`${label}不能为空`);
  }
  return result;
}

function collectCustomConfig() {
  if (!state.modelInfo) throw new Error('请先读取 Simulink 模型。');
  if (!state.selectedPidIndexes.length || state.selectedPidIndexes.length > 2) throw new Error('请选择一个或两个 PID。');
  const modelPath = String(state.modelInfo.modelPath || el('modelPathInput').value || '').trim();
  if (!/\.(slx|mdl)$/i.test(modelPath)) throw new Error('当前模型尚未保存为 .slx 或 .mdl 文件，请先保存模型。');
  const blocks = state.modelInfo.pidBlocks;
  const pidBlocks = state.selectedPidIndexes.map((index, position) => {
    const block = blocks[index];
    if (!block?.path) throw new Error(`PID ${position + 1} 缺少 Simulink 块路径。`);
    const bounds = {};
    ['Kp', 'Ki', 'Kd', 'N'].forEach((field) => {
      const low = numberFrom(`pid-${index}-${field}-min`, { label: `PID ${position + 1} ${field} 最小值` });
      const high = numberFrom(`pid-${index}-${field}-max`, { label: `PID ${position + 1} ${field} 最大值` });
      if (low > high) validationError(`pid-${index}-${field}-min`, `PID ${position + 1} 的 ${field} 最小值不能大于最大值`);
      bounds[field] = [low, high];
    });
    return { name: el(`pid-${index}-name`).value.trim() || `pid${position + 1}`, path: block.path, bounds };
  });

  const availableSignalNames = loggedSignalNames();
  if (!availableSignalNames.length) throw new Error('当前模型没有已记录信号，请先在 Simulink 中启用信号记录。');
  const cards = Array.from(document.querySelectorAll('#loopConfigRows .loop-config'));
  if (cards.length !== pidBlocks.length) throw new Error('每个 PID 都必须有一个评价环路。');
  const evaluationLoops = cards.map((card, index) => {
    const referenceSignalName = loopValue(card, '.loop-reference');
    const outputSignalName = loopValue(card, '.loop-output');
    const controlSignalName = loopValue(card, '.loop-control');
    const currentSignalName = loopValue(card, '.loop-current');
    const selectedSignals = [referenceSignalName, outputSignalName, controlSignalName, currentSignalName].filter(Boolean);
    const missing = selectedSignals.filter((name) => !availableSignalNames.includes(name));
    if (!referenceSignalName || !outputSignalName || !controlSignalName) throw new Error(`环路 ${index + 1} 必须选择参考、反馈和控制信号。`);
    if (missing.length) throw new Error(`环路 ${index + 1} 包含未记录信号：${missing.join('、')}`);
    if (referenceSignalName === outputSignalName) throw new Error(`环路 ${index + 1} 的参考信号和反馈信号不能相同。`);
    const lower = requiredCardNumber(card, '.loop-control-lower', `环路 ${index + 1} 控制量下限`);
    const upper = requiredCardNumber(card, '.loop-control-upper', `环路 ${index + 1} 控制量上限`);
    if (lower >= upper) throw new Error(`环路 ${index + 1} 的控制量下限必须小于上限。`);
    const targets = {
      overshootPctMax: requiredCardNumber(card, '.loop-overshoot', `环路 ${index + 1} 超调上限`, { min: 0 }),
      settlingTimeMax: requiredCardNumber(card, '.loop-settling', `环路 ${index + 1} 调节时间上限`, { min: 0 }),
      steadyStateErrorAbsMax: requiredCardNumber(card, '.loop-error', `环路 ${index + 1} 稳态误差上限`, { min: 0 }),
      maxAbsControlMax: Math.max(Math.abs(lower), Math.abs(upper)),
    };
    const optionalTargets = [
      ['.loop-rmse', 'trackingRmseMax', 'RMSE 上限'],
      ['.loop-current-max', 'maxAbsCurrentMax', '电流峰值上限'],
      ['.loop-ripple', 'outputRippleMax', '输出纹波上限'],
      ['.loop-saturation', 'controlSaturationFractionMax', '最大饱和率', { max: 1 }],
    ];
    optionalTargets.forEach(([selector, name, label, extra]) => {
      const target = optionalCardNumber(card, selector, `环路 ${index + 1} ${label}`, { min: 0, ...(extra || {}) });
      if (target !== null) targets[name] = target;
    });
    if (targets.maxAbsCurrentMax !== undefined && !currentSignalName && loopValue(card, '.loop-role') !== 'inner') {
      throw new Error(`环路 ${index + 1} 设置了电流峰值上限，但没有选择电流保护信号。`);
    }
    return {
      name: `${pidBlocks[index].name} loop`,
      role: loopValue(card, '.loop-role', cards.length === 1 ? 'single' : ''),
      pidPath: String(card.dataset.pidPath || ''),
      referenceSignalName, outputSignalName, controlSignalName, currentSignalName,
      weight: requiredCardNumber(card, '.loop-weight', `环路 ${index + 1} 权重`, { min: Number.MIN_VALUE }),
      primary: Boolean(card.querySelector('.loop-primary')?.checked), enabled: true,
      controlLowerLimit: lower, controlUpperLimit: upper, targets,
    };
  });
  if (evaluationLoops.filter((loop) => loop.primary).length !== 1) throw new Error('必须且只能选择一个主评价环路。');
  const searchStrategy = el('searchStrategyInput').value;
  if (evaluationLoops.length === 2 && ['auto', 'cascade'].includes(searchStrategy)) {
    const roles = new Set(evaluationLoops.map((loop) => loop.role));
    if (!(roles.has('inner') && roles.has('outer') && roles.size === 2)) throw new Error('级联双环必须分别指定一个内环和一个外环。');
  }
  if (!el('signalMappingConfirmedInput').checked) validationError('signalMappingConfirmedInput', '请核对并确认全部环路的评价信号与安全限制。');

  const maxIterations = numberFrom('maxIterationsInput', { label: '迭代轮数', integer: true, min: 3 });
  const numCandidates = numberFrom('numCandidatesInput', { label: '每轮候选数', integer: true, min: 2 });
  const primary = evaluationLoops.find((loop) => loop.primary);
  return {
    modelPath, pidBlocks,
    workingDirectory: state.simulinkContext?.workingDirectory || '',
    projectRoot: state.simulinkContext?.projectRoot || '',
    projectPath: state.simulinkContext?.projectPath || '',
    referenceSignalName: primary.referenceSignalName,
    outputSignalName: primary.outputSignalName,
    controlSignalName: primary.controlSignalName,
    currentSignalName: primary.currentSignalName,
    evaluationPidPath: primary.pidPath,
    evaluationLoops, availableSignalNames, signalMappingConfirmed: true,
    searchStrategy,
    stopTime: String(numberFrom('stopTimeInput', { label: '仿真停止时间', min: Number.MIN_VALUE })),
    maxIterations, numCandidates,
    stopOnFirstPass: el('stopOnFirstPassInput').checked,
    ai: collectAiConfig(numCandidates),
    targets: {
      overshootPctMax: numberFrom('overshootTargetInput', { label: '默认最大超调量', min: 0 }),
      settlingTimeMax: numberFrom('settlingTargetInput', { label: '默认最大调节时间', min: 0 }),
      steadyStateErrorAbsMax: numberFrom('errorTargetInput', { label: '默认最大稳态误差', min: 0 }),
    },
  };
}

function loopValidationMap(record) {
  const result = new Map();
  normalizeList(record?.loopValidations).forEach((item, index) => result.set(String(item.name || index), item));
  return result;
}

function loopDefinition(item, index) {
  const loops = normalizeList(state.status?.evaluationLoops);
  return loops.find((loop) => String(loop.name || '') === String(item?.name || '')) || loops[index] || {};
}

function metricWithTarget(item, index, metricName, targetName) {
  const actual = metricValue(item, metricName);
  const definition = loopDefinition(item, index);
  const rawTarget = definition?.targets?.[targetName];
  const target = Number(rawTarget);
  return rawTarget !== null && rawTarget !== undefined && rawTarget !== '' && Number.isFinite(target)
    ? `${actual} / ${fmt.format(target)}` : `${actual} / 未设置`;
}

function loopDiagnostic(item) {
  const message = String(item?.error || '').trim();
  if (!message) return '-';
  const missing = message.match(/Signal '([^']+)' was not found/i);
  if (missing) return `未读取到评价信号：${missing[1]}`;
  return message;
}

function renderLoopMetrics(record, targetId = 'loopMetricRows') {
  const target = el(targetId);
  if (!target) return;
  const metrics = normalizeList(record?.metrics?.loopMetrics);
  const validations = normalizeList(record?.loopValidations);
  target.innerHTML = metrics.length ? metrics.map((item, index) => {
    const validation = validations.find((candidate) => String(candidate.name || '') === String(item.name || '')) || validations[index];
    const passed = validation ? Boolean(validation.passed) : Boolean(item.isStable && item.isFinite && item.simulationSuccess);
    return `<tr><td>${escapeHtml(value(item.name, `环路 ${index + 1}`))}</td><td>${escapeHtml(roleLabel(item.role))}</td>
      <td>${passed ? '<span class="pass">通过</span>' : '<span class="fail">未通过</span>'}</td>
      <td>${metricWithTarget(item, index, 'overshootPct', 'overshootPctMax')}</td>
      <td>${metricWithTarget(item, index, 'settlingTime', 'settlingTimeMax')}</td>
      <td>${metricWithTarget(item, index, 'steadyStateError', 'steadyStateErrorAbsMax')}</td>
      <td>${metricWithTarget(item, index, 'trackingRmse', 'trackingRmseMax')}</td>
      <td>${metricWithTarget(item, index, 'maxAbsControl', 'maxAbsControlMax')}</td>
      <td>${metricWithTarget(item, index, 'maxAbsCurrent', 'maxAbsCurrentMax')}</td>
      <td>${metricWithTarget(item, index, 'outputRipple', 'outputRippleMax')}</td>
      <td>${metricWithTarget(item, index, 'controlSaturationFraction', 'controlSaturationFractionMax')}</td>
      <td title="${escapeHtml(loopDiagnostic(item))}">${escapeHtml(loopDiagnostic(item))}</td></tr>`;
  }).join('') : '<tr><td colspan="12">暂无分环评价结果</td></tr>';
}

function renderStageSummaries(payload) {
  const target = el('stageSummaryRows');
  if (!target) return;
  const rows = normalizeList(payload?.stageSummaries).filter((item) => String(item?.name || '').trim());
  target.innerHTML = rows.length ? rows.map((item, index) => `<tr>
    <td>${index + 1}</td><td>${escapeHtml(stageLabel(item.name))}</td>
    <td>${escapeHtml(stageRoleLabel(item.role))}</td><td>${item.passed ? '<span class="pass">通过</span>' : '<span class="fail">未通过</span>'}</td>
    <td>${value(item.score)}</td></tr>`).join('') : '<tr><td colspan="5">暂无阶段结果</td></tr>';
}
function drawScoreTrend(history) {
  const canvas = el('scoreTrendCanvas');
  if (!canvas) return;
  const width = Math.max(320, Math.floor(canvas.getBoundingClientRect().width || 800));
  const height = 180;
  const ratio = Math.max(1, window.devicePixelRatio || 1);
  canvas.width = Math.floor(width * ratio);
  canvas.height = Math.floor(height * ratio);
  const context = canvas.getContext('2d');
  context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.clearRect(0, 0, width, height);
  context.fillStyle = '#ffffff'; context.fillRect(0, 0, width, height);
  const points = normalizeList(history).map((record, index) => ({
    x: index, y: Number(record.score), stage: String(record.stage || ''), passed: Boolean(record.passed),
  })).filter((point) => Number.isFinite(point.y));
  context.strokeStyle = '#c7c7c7'; context.lineWidth = 1;
  context.beginPath(); context.moveTo(50, 12); context.lineTo(50, 154); context.lineTo(width - 12, 154); context.stroke();
  if (!points.length) {
    context.fillStyle = '#666'; context.font = '12px Segoe UI'; context.fillText('暂无候选分数', 60, 84); return;
  }
  const rawValues = points.map((point) => point.y);
  const rawMin = Math.min(...rawValues), rawMax = Math.max(...rawValues);
  const smallestPositive = Math.min(...rawValues.filter((number) => number > 0));
  const useLog = rawMin >= 0 && (rawMax > 1e6 || (Number.isFinite(smallestPositive) && rawMax / smallestPositive > 100));
  const plotted = points.map((point) => ({ ...point, plotY: useLog ? Math.log10(1 + point.y) : point.y }));
  const plotValues = plotted.map((point) => point.plotY);
  let plotMin = Math.min(...plotValues), plotMax = Math.max(...plotValues);
  if (plotMax <= plotMin) plotMax = plotMin + 1;
  const xScale = (width - 72) / Math.max(1, plotted.length - 1);
  const yScale = (154 - 14) / (plotMax - plotMin);
  context.fillStyle = '#555'; context.font = '11px Segoe UI';
  context.fillText(fmt.format(rawMax), 3, 17); context.fillText(fmt.format(rawMin), 3, 154);
  if (useLog) context.fillText('对数刻度', 56, 17);
  context.strokeStyle = '#0072bd'; context.lineWidth = 1.6; context.beginPath();
  plotted.forEach((point, index) => {
    const x = 50 + index * xScale, y = 154 - (point.plotY - plotMin) * yScale;
    if (index === 0) context.moveTo(x, y); else context.lineTo(x, y);
  });
  context.stroke();
  plotted.forEach((point, index) => {
    const x = 50 + index * xScale, y = 154 - (point.plotY - plotMin) * yScale;
    context.fillStyle = point.passed ? '#2e7d32' : '#0072bd'; context.beginPath(); context.arc(x, y, point.passed ? 3 : 2, 0, Math.PI * 2); context.fill();
    if (index > 0 && point.stage !== plotted[index - 1].stage) {
      context.strokeStyle = '#888'; context.setLineDash([3, 3]); context.beginPath(); context.moveTo(x, 14); context.lineTo(x, 154); context.stroke(); context.setLineDash([]);
    }
  });
}
function stageText(payload) {
  const name = String(payload.currentStage || payload.current?.stage || '').trim();
  const index = Number(payload.stageIndex || 0), count = Number(payload.stageCount || 0);
  if (!name) return '--';
  return count > 0 ? `${index}/${count} ${stageLabel(name)}` : stageLabel(name);
}

function renderRecent(records) {
  const rows = normalizeList(records);
  el('recentRows').innerHTML = rows.length ? rows.map((record, index) => `
    <tr><td>${value(record.globalIndex, index + 1)}</td><td>${escapeHtml(stageLabel(record.stage))}</td><td>${value(record.iteration)}</td>
    <td>${value(record.candidateIndex)}</td><td>${sourceHtml(record)}</td><td>${passText(record)}</td>
    <td>${metricValue(pickMetrics(record), 'overshootPct')}</td><td>${metricValue(pickMetrics(record), 'settlingTime')}</td>
    <td>${metricValue(pickMetrics(record), 'steadyStateError')}</td><td>${value(record.score)}</td></tr>`).join('') : '<tr><td colspan="10">暂无候选记录</td></tr>';
}

function renderHistory(rows) {
  const data = normalizeList(rows);
  el('historyCount').textContent = `${data.length} 条`;
  el('historyRows').innerHTML = data.length ? data.map((record, index) => {
    const summary = escapeHtml(pidSummary(record));
    return `<tr><td>${value(record.globalIndex, index + 1)}</td><td>${escapeHtml(value(record.timestamp))}</td><td>${escapeHtml(stageLabel(record.stage))}</td>
      <td>${value(record.iteration)}</td><td>${value(record.candidateIndex)}</td><td>${sourceHtml(record)}</td><td title="${summary}">${summary}</td>
      <td>${passText(record)}</td><td>${escapeHtml(failureText(record))}</td><td>${metricValue(pickMetrics(record), 'overshootPct')}</td>
      <td>${metricValue(pickMetrics(record), 'settlingTime')}</td><td>${metricValue(pickMetrics(record), 'steadyStateError')}</td><td>${value(record.score)}</td></tr>`;
  }).join('') : '<tr><td colspan="13">暂无历史记录</td></tr>';
  drawScoreTrend(data);
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
  el('stageText').textContent = stageText(payload);
  const status = value(payload.status, 'idle').toLowerCase();
  el('statusPill').textContent = statusLabel(status);
  el('statusPill').className = `status-pill ${status}`;
  const current = recordOrNull(payload.current);
  el('currentSummary').textContent = current ? `${sourceLabel(current)} · 候选 ${value(current.candidateIndex)} / 分数 ${value(current.score)}` : '暂无';
  renderPidRows('currentPidRows', current);
  renderEffectEvaluation(payload);
  renderRecent(payload.recent || []);
  const bestPassing = recordOrNull(payload.bestPassing);
  const bestScored = recordOrNull(payload.best);
  const best = bestPassing || bestScored;
  renderLoopMetrics(status === 'completed' ? (best || current) : (current || best));
  renderLoopMetrics(best, 'bestLoopMetricRows');
  renderStageSummaries(payload);
  el('bestKind').textContent = bestPassing ? '已通过最优' : (bestScored ? '当前最低分（未通过全部指标）' : '暂无');
  el('bestScore').textContent = best ? `score=${value(best.score)}` : '暂无';
  renderPidRows('bestPidRows', best);
  el('bestMetrics').innerHTML = metricRows(pickMetrics(best));
  const canApply = status === 'completed' && Boolean(bestPassing) && !Boolean(payload.resultApplied);
  el('applyBestButton').disabled = !canApply;
  el('rollbackBestButton').disabled = !Boolean(payload.rollbackAvailable || payload.resultApplied);
  el('applyState').textContent = payload.resultApplied
    ? '参数已写入模型，可回滚'
    : (status !== 'completed' ? '任务完成且最终阶段全部环路通过后才能写入'
      : (bestPassing ? '最终结果已通过全部环路硬指标，可以写入' : '只有通过全部硬指标的最终结果可以写入'));
  drawScoreTrend(state.history);
}

async function refreshHealth() {
  try {
    const payload = await api('/api/health');
    state.health = payload;
    const ready = payload.matlabReady ?? payload.matlabAvailable;
    el('serverVersion').textContent = payload.serverVersion || '--';
    const connection = el('connectionState');
    connection.textContent = ready ? 'MATLAB 可用'
      : (payload.matlabAvailable ? '网关已连接，MATLAB 检查未通过' : '网关已连接，未找到 MATLAB');
    connection.title = payload.matlabProbeError || '';
    sendMatlabEvent('GatewayStatus', { ok: true, matlabAvailable: Boolean(ready), error: payload.matlabProbeError || '' });
    return true;
  } catch (error) {
    el('connectionState').textContent = '本地网关未连接';
    sendMatlabEvent('GatewayStatus', { ok: false, error: String(error?.message || error) });
    return false;
  }
}

function normalizedModelPath(valueText) {
  return String(valueText || '').trim().replaceAll('/', '\\').toLowerCase();
}

function jobMatchesPreferredModel(job) {
  const preferredPath = normalizedModelPath(state.preferredModelPath);
  const jobPath = normalizedModelPath(job?.modelPath);
  if (preferredPath) return Boolean(jobPath) && jobPath === preferredPath;
  const preferredName = String(state.preferredModelName || '').trim().toLowerCase();
  const jobName = String(job?.modelName || '').trim().toLowerCase();
  return Boolean(preferredName) && jobName === preferredName;
}

async function chooseLatestJob() {
  const payload = await api('/api/pid/jobs');
  const jobs = normalizeList(payload.jobs);
  const selector = el('jobSelectInput');
  const current = state.activeJobId || selector.value;
  selector.innerHTML = jobs.map((job) => `<option value="${escapeHtml(job.jobId)}">${escapeHtml(job.updatedAt || '')} · ${escapeHtml(job.modelName || job.jobId)} · ${escapeHtml(statusLabel(job.status))}</option>`).join('');
  const currentJob = jobs.find((job) => job.jobId === current);
  if (currentJob && (!state.enforceModelMatch || jobMatchesPreferredModel(currentJob))) {
    state.activeJobId = current;
  } else {
    const matching = jobs.find(jobMatchesPreferredModel);
    state.activeJobId = matching?.jobId || (state.enforceModelMatch ? null : (jobs[0]?.jobId || null));
  }
  if (state.activeJobId) selector.value = state.activeJobId;
  else selector.selectedIndex = -1;
  return jobs;
}
async function refreshJob() {
  if (state.refreshing) return;
  state.refreshing = true;
  try {
    if (!(await refreshHealth())) return;
    await chooseLatestJob();
    if (!state.activeJobId) {
      renderStatus({ status: 'idle', modelName: state.preferredModelName || '', current: null, best: null, bestPassing: null });
      state.history = [];
      renderHistory([]);
      return;
    }
    const payload = await api(`/api/pid/jobs/${encodeURIComponent(state.activeJobId)}`);
    renderStatus(payload);
    const historyPayload = await api(`/api/pid/jobs/${encodeURIComponent(state.activeJobId)}/history`);
    state.history = normalizeList(historyPayload.history);
    renderHistory(state.history);
  } catch (error) {
    el('connectionState').textContent = `读取失败：${error.message}`;
  } finally {
    state.refreshing = false;
  }
}

async function applyBestResult() {
  if (!state.activeJobId) return;
  const button = el('applyBestButton');
  button.disabled = true;
  el('applyState').textContent = '正在备份并写入模型参数...';
  try {
    const result = await api(`/api/pid/jobs/${encodeURIComponent(state.activeJobId)}/apply`, { method: 'POST' });
    el('applyState').textContent = `已写入并保存；备份：${value(result.backupPath, '-')}`;
    await refreshJob();
  } catch (error) {
    el('applyState').textContent = apiErrorText(error, '写入模型');
  }
}

async function rollbackBestResult() {
  if (!state.activeJobId) return;
  const button = el('rollbackBestButton');
  button.disabled = true;
  el('applyState').textContent = '正在恢复写入前参数...';
  try {
    await api(`/api/pid/jobs/${encodeURIComponent(state.activeJobId)}/rollback`, { method: 'POST' });
    el('applyState').textContent = '已恢复写入前参数并保存模型';
    await refreshJob();
  } catch (error) {
    el('applyState').textContent = apiErrorText(error, '回滚模型');
  }
}

function bindPidAgentV2() {
  const container = el('loopConfigRows');
  container.addEventListener('click', (event) => {
    const button = event.target.closest('.loop-suggest');
    if (button) applyLoopSuggestion(button.closest('.loop-config'));
  });
  container.addEventListener('change', markSignalMappingChanged);
  el('searchStrategyInput').addEventListener('change', markSignalMappingChanged);
  el('jobSelectInput').addEventListener('change', () => { state.enforceModelMatch = false; state.activeJobId = el('jobSelectInput').value || null; refreshJob(); });
  el('refreshHistoryButton').addEventListener('click', refreshJob);
  el('applyBestButton').addEventListener('click', applyBestResult);
  el('rollbackBestButton').addEventListener('click', rollbackBestResult);
  window.addEventListener('resize', () => drawScoreTrend(state.history));
  renderLoopMetrics(null);
  renderLoopMetrics(null, 'bestLoopMetricRows');
  renderStageSummaries({});
  drawScoreTrend([]);
}

window.addEventListener('DOMContentLoaded', bindPidAgentV2);
function loggedSignalNames() {
  const duplicateNames = new Set(normalizeList(state.modelInfo?.duplicateLoggedSignalNames).map(String));
  const catalog = normalizeList(state.modelInfo?.loggedSignalCatalog);
  if (catalog.length) {
    return Array.from(new Set(catalog.map((item) => String(item.name || '').trim()).filter((name) => name && !duplicateNames.has(name))));
  }
  return stringArray(state.modelInfo?.loggedSignals).filter((name) => name.trim());
}

function signalOptions(selectedValue = '', optional = false) {
  const names = loggedSignalNames();
  const catalog = normalizeList(state.modelInfo?.loggedSignalCatalog);
  const labelByName = new Map();
  catalog.forEach((item) => {
    const name = String(item.name || '').trim();
    const source = String(item.sourcePath || '').trim();
    if (name && source && !labelByName.has(name)) labelByName.set(name, `${name} — ${source}`);
  });
  const placeholder = optional ? '不检查' : '请选择已记录的标量信号';
  return [`<option value="">${placeholder}</option>`, ...names.map((name) => {
    const selected = name === selectedValue ? ' selected' : '';
    return `<option value="${escapeHtml(name)}"${selected}>${escapeHtml(labelByName.get(name) || name)}</option>`;
  })].join('');
}
// Never infer a tuning pair from discovery order. Multi-PID models require an explicit selection.
async function discoverModel() {
  if (state.embedded) {
    setScanState('正在从 Simulink 同步当前模型');
    sendMatlabEvent('SyncCurrentModel', {});
    return;
  }
  const modelPath = el('modelPathInput').value.trim();
  const button = el('discoverModelButton');
  const previousModelPath = String(state.modelInfo?.modelPath || '');
  const previousPaths = new Set(state.selectedPidIndexes.map((index) => String(state.modelInfo?.pidBlocks?.[index]?.path || '')).filter(Boolean));
  button.disabled = true;
  button.textContent = 'MATLAB 读取中...';
  setScanState('正在启动 MATLAB 并读取模型');
  try {
    const payload = await api('/api/pid/models/discover', jsonPost({ modelPath }));
    payload.pidBlocks = normalizePidBlocks(payload.pidBlocks);
    payload.loggedSignals = stringArray(payload.loggedSignals);
    state.modelInfo = payload;
    state.preferredModelPath = String(payload.modelPath || '');
    state.preferredModelName = String(payload.modelName || '');
    state.enforceModelMatch = true;
    state.activeJobId = null;
    const sameModel = previousModelPath && previousModelPath === String(payload.modelPath || '');
    if (payload.pidBlocks.length === 1) {
      state.selectedPidIndexes = [0];
    } else if (sameModel && previousPaths.size) {
      state.selectedPidIndexes = payload.pidBlocks
        .map((block, index) => previousPaths.has(String(block.path)) ? index : -1)
        .filter((index) => index >= 0)
        .slice(0, 2);
    } else {
      state.selectedPidIndexes = [];
    }
    renderModelInfo();
    const action = payload.pidBlocks.length > 1 ? '；请明确选择一个 PID 或一组已确认的内外环' : '';
    setScanState(`已读取 ${payload.modelName}：发现 ${payload.pidBlocks.length} 个 PID${action}`);
    await refreshJob();
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
    state.preferredModelPath = String(info.modelPath || context.modelPath || '');
    state.preferredModelName = String(info.modelName || context.modelName || '');
    state.enforceModelMatch = true;
    state.activeJobId = null;
    const selectedPaths = new Set(stringArray(context.selectedPidPaths));
    const matched = info.pidBlocks
      .map((block, index) => selectedPaths.has(String(block.path)) ? index : -1)
      .filter((index) => index >= 0);
    if (selectedPaths.size > 2) {
      state.selectedPidIndexes = [];
    } else if (matched.length) {
      state.selectedPidIndexes = matched.slice(0, 2);
    } else if (!selectedPaths.size && info.pidBlocks.length === 1) {
      state.selectedPidIndexes = [0];
    } else {
      state.selectedPidIndexes = [];
    }
    renderModelInfo();
    let note = '';
    if (selectedPaths.size > 2) note = '；当前选择超过两个，未自动带入，请重新选择';
    else if (info.pidBlocks.length > 1 && !state.selectedPidIndexes.length) note = '；请明确选择一个 PID 或一组已确认的内外环';
    setScanState(`来自 Simulink：发现 ${info.pidBlocks.length} 个 PID${note}`, selectedPaths.size > 2);
  }
  if (context.initialView) activateView(context.initialView);
  refreshJob();
}
// The Buck button opens the model for verified mapping instead of launching a stale hard-coded task.
async function startBuckDemo() {
  const button = el('startBuckDemoButton');
  button.disabled = true;
  button.textContent = '读取 Buck 模型中...';
  try {
    let modelPath = String(state.health?.buckDualLoopDemo || '');
    if (!modelPath) {
      const health = await api('/api/health');
      state.health = health;
      modelPath = String(health.buckDualLoopDemo || '');
    }
    if (!modelPath) throw new Error('网关没有返回 Buck 示例模型路径。');
    el('modelPathInput').value = modelPath;
    await discoverModel();
  } catch (error) {
    setScanState(`Buck 模型读取失败：${error.message}`, true);
  } finally {
    button.disabled = false;
    button.textContent = '读取 Buck 双环模型';
  }
}