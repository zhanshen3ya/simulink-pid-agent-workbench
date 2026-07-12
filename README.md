# Simulink PID Agent Workbench
[下载最新版本](https://github.com/zhanshen3ya/simulink-pid-agent-workbench/releases/latest) · [MIT License](LICENSE)
> [!WARNING]
> **WIP / 半成品项目**：当前版本是可运行的研究与工程原型，并非成熟产品。接口、配置格式和调参策略仍可能调整。请勿未经独立验证直接用于生产设备、安全关键系统或实际控制器部署。

当前已完成模型扫描、单/双 PID 候选注入、Simulink 强制验证、指标记录、远程 API 与 Code Agent 接入。尚未完成跨平台验证、故障恢复、批量模型兼容性、正式安装器和完整自动化测试。


AI 负责生成 PID 候选，Simulink 负责逐组仿真，固定指标负责最终验收。支持单 PID 和内外环双 PID 联合调参。

## 下载与要求

1. 从 GitHub Releases 下载 Source code (zip) 并解压。
2. 安装 MATLAB、Simulink 和 Python 3。
3. Windows 双击“启动PID调参控制台.bat”。
4. 浏览器访问 http://127.0.0.1:8788。

当前版本在 Windows 11、MATLAB/Simulink R2024b 上完成验证。其他较新版本可运行，但尚未逐版本测试。

AI 接入是可选项：

- 远程 API：任意 OpenAI-compatible /chat/completions 服务。
- Code Agent：用户自行安装并登录 Codex CLI、MiniMax Code 或 Claude Code。
- 关闭 AI：使用程序搜索，不依赖外部服务。

## 隐私与仓库边界

仓库只发布源代码、文档、测试和两个公开 Demo 模型。以下内容不会上传：

- pid_tuning_runs/ 中每次调参的参数、指标、历史和日志。
- 用户导入的任意 .slx / .mdl 模型。
- .tools/ 中的本地 CLI、SSH 密钥和依赖。
- API Key、浏览器本地配置、MATLAB 缓存和 Python 缓存。

仅 pid_ai_second_order_demo.slx 和 pid_ai_cascade_two_pid_demo.slx 作为公开示例纳入发行包。

这个工作区已经搭好一个 MATLAB/Simulink 闭环 PID 调参骨架。核心原则：

- AI 或优化算法只负责生成候选 PID 参数。
- 每一组候选参数都必须经过 Simulink 仿真。
- 每次仿真后用固定指标打分和验收。
- 最终 PID 参数来自多轮闭环迭代，而不是 AI 直接拍板。

## 目录结构

```text
.
|-- main_pid_search.m
|-- pid_tuning_core/
|   `-- +pid_tuning_core/
|       |-- defaultPidTuningConfig.m
|       |-- discoverPidBlocks.m
|       |-- readPidBlockParams.m
|       |-- generatePidCandidates.m
|       |-- runCandidateBatch.m
|       |-- applyPidCandidate.m
|       |-- evaluatePidRun.m
|       |-- extractSignalVector.m
|       |-- setupPidBlocks.m
|       |-- normalizePidCandidate.m
|       |-- formatPidCandidate.m
|       |-- validatePidMetrics.m
|       |-- updatePidSearchState.m
|       `-- saveIterationLog.m
|-- examples/
|   `-- +examples/
|       |-- create_second_order_pid_demo.m
|       |-- demo_pid_ai_tuning.m
|       |-- create_cascade_two_pid_demo.m
|       `-- demo_two_pid_ai_tuning.m
|-- pid_ai_second_order_demo.slx
|-- pid_ai_cascade_two_pid_demo.slx
`-- pid_tuning_runs/
```

`pid_ai_second_order_demo.slx` 和 `pid_tuning_runs/` 是端到端测试时生成的示例模型和调参日志。

## 快速运行示例

在 MATLAB 中进入本目录后执行：

```matlab
addpath(genpath(pwd))
examples.create_second_order_pid_demo
result = examples.demo_pid_ai_tuning
```

示例会创建一个二阶对象 + PID Controller 的 Simulink 模型，然后自动跑多轮候选 PID 仿真和指标验证。

内外环两个 PID 联合调参示例：

```matlab
addpath(genpath(pwd))
examples.create_cascade_two_pid_demo
result = examples.demo_two_pid_ai_tuning
```

## 接入你的 Simulink 模型

最小配置：

```matlab
addpath(genpath(pwd))

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "your_model";
cfg.pidBlockPath = "";          % 留空时自动查找第一个 PID Controller
cfg.referenceSignalName = "r";   % 参考输入信号名
cfg.outputSignalName = "y";      % 系统输出信号名
cfg.controlSignalName = "u";     % 控制量信号名，可选

result = main_pid_search(cfg);
```

如果要一次性调节两个 PID，例如外环 + 内环：

```matlab
cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "your_model";

cfg.pidBlocks(1).name = "outer";
cfg.pidBlocks(1).path = "your_model/Outer PID";
cfg.pidBlocks(1).bounds.Kp = [0, 40];
cfg.pidBlocks(1).bounds.Ki = [0, 30];
cfg.pidBlocks(1).bounds.Kd = [0, 10];
cfg.pidBlocks(1).bounds.N = [10, 500];

cfg.pidBlocks(2).name = "inner";
cfg.pidBlocks(2).path = "your_model/Inner PID";
cfg.pidBlocks(2).bounds.Kp = [0, 60];
cfg.pidBlocks(2).bounds.Ki = [0, 40];
cfg.pidBlocks(2).bounds.Kd = [0, 10];
cfg.pidBlocks(2).bounds.N = [10, 500];

result = main_pid_search(cfg);
```

这时一组候选参数会同时包含两个 PID：

```matlab
candidate.pids(1)  % outer
candidate.pids(2)  % inner
```

程序会把两个 PID 同时注入同一次 Simulink 仿真，再用同一套固定指标判断这组联合参数是否通过。

你的模型需要把输出信号保存到 `SimulationOutput`，推荐二选一：

- 使用 `To Workspace`，变量名分别设为 `r`、`y`、`u`。
- 使用 signal logging，把信号记录到 `logsout`，名称也设为 `r`、`y`、`u`。

如果没有 `r`，程序仍能跑，但稳态误差和跟踪类指标会退化；如果没有 `u`，控制能量和控制量峰值会按 0 处理。

## AI 接入点

默认候选参数由程序随机搜索 + 精英收缩生成。后续可以把 AI 接到候选生成函数：

```matlab
cfg.ai.enabled = true;
cfg.ai.suggestFcn = @yourAiSuggestFcn;
```

函数签名：

```matlab
candidates = yourAiSuggestFcn(state, cfg, count);
```

返回结构体数组，每个元素至少包含：

```matlab
Kp, Ki, Kd
```

可选包含：

```matlab
N
```

两 PID 或多 PID 时，推荐返回：

```matlab
candidates(i).pids(1).name = "outer";
candidates(i).pids(1).Kp = ...;
candidates(i).pids(1).Ki = ...;
candidates(i).pids(1).Kd = ...;
candidates(i).pids(1).N = ...;

candidates(i).pids(2).name = "inner";
candidates(i).pids(2).Kp = ...;
candidates(i).pids(2).Ki = ...;
candidates(i).pids(2).Kd = ...;
candidates(i).pids(2).N = ...;
```

即使启用 AI，候选参数也会先被边界裁剪，然后必须通过 Simulink 仿真和固定指标验证。

## 默认验证指标

每组参数都会计算：

- `overshootPct`: 超调量
- `settlingTime`: 调节时间
- `steadyStateError`: 稳态误差
- `iae`: `integral(abs(e))`
- `ise`: `integral(e^2)`
- `itae`: `integral(t * abs(e))`
- `controlEnergy`: 控制能量
- `maxAbsControl`: 控制量峰值
- `isStable`: 稳定性和数值有效性

验收阈值在 `cfg.targets` 中配置，评分权重在 `cfg.weights` 中配置。

## 本地控制台与 Code Agent

双击 启动PID调参控制台.bat，浏览器打开 http://127.0.0.1:8788。控制台只监听本机地址。

操作流程：

1. 在“Simulink 模型”中选择或填写 .slx / .mdl 的完整路径。
2. 点击“读取模型”，勾选一个或两个 PID 块，并设置每个参数的上下界。
3. 填写模型中已记录的 r、y、u 信号名和固定验收阈值。
4. 打开“配置 AI”，选择远程 API 或 Code Agent。
5. 启动调参。每个 AI 候选都必须经过 Simulink 仿真，页面会记录耗时、轮次、当前参数、指标、来源和完整历史。

远程 API 模式使用 OpenAI-compatible /chat/completions 接口。API Key 只保留在当前浏览器页面内存，并通过环境变量传给 MATLAB 子进程，不写入请求配置、日志或浏览器持久化存储。

Code Agent 模式支持：

- Codex CLI
- MiniMax Code
- Claude Code

点击“重新发现”自动寻找本机 CLI，再点击“测试连接”。发行包不捆绑任何 AI CLI，用户需要自行安装并登录。Code Agent 只生成数值候选，不能绕过参数边界、Simulink 仿真或固定指标验收。

当前 Demo：

- pid_ai_second_order_demo.slx：单 PID。
- pid_ai_cascade_two_pid_demo.slx：内外环两个 PID 联合调参。