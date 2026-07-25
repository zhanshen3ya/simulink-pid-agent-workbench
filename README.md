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

仓库只发布源代码、文档、测试和四个公开 Demo 模型和一个启动库。以下内容不会上传：

- pid_tuning_runs/ 中每次调参的参数、指标、历史和日志。
- 用户导入的任意 .slx / .mdl 模型。
- .tools/ 中的本地 CLI、SSH 密钥和依赖。
- API Key、浏览器本地配置、MATLAB 缓存和 Python 缓存。

仅 pid_ai_second_order_demo.slx、pid_ai_cascade_two_pid_demo.slx、pid_ai_buck_dual_loop_demo.slx、pid_ai_multi_system_demo.slx 和 pid_agent_lib.slx 作为公开示例与启动库纳入发行包。

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
## Buck 双闭环电路 Demo

新增 `pid_ai_buck_dual_loop_demo.slx`，用于比二阶传递函数更接近电力电子控制的联合调参：

- 24 V 输入、12 V 输出的 Buck 平均电路，包含 470 uH 电感、470 uF 电容和 0.08 ohm 线圈电阻。
- 外环电压 PI 生成电流给定，内环电流 PI 生成占空比，两组参数在同一个候选中联合调整。
- 0.08 s 时输入从 24 V 跌落到 20 V，0.12 s 时负载从 6 ohm 跳变为 3 ohm。
- 每个候选固定检查超调、调节时间、稳态误差、IAE、占空比、电感电流峰值、输出纹波和占空比饱和比例。

MATLAB 直接运行：

```matlab
addpath(genpath(pwd))
report = examples.validate_buck_dual_loop_demo
result = examples.demo_buck_dual_loop_tuning
```

也可以启动本地控制台后点击“Buck 双环电路 Demo”。该模型用于快速批量搜索；面向真实硬件部署时，仍需将候选参数放入开关级 Simscape Electrical 模型并进行采样、PWM、器件损耗和保护逻辑验证。
## 多 PID Manager（大型模型）

新增的 PID Agent Manager 面向一个工程中存在多个系统、多个 PID 的场景。它会扫描顶层模型、子系统、库链接、掩膜块和引用模型，然后在 Simulink 内完成选择、分组和执行顺序配置。

```matlab
addpath(genpath(pwd))
examples.create_multi_system_pid_demo
open_system("pid_ai_multi_system_demo")
pid_project_manager.launch("pid_ai_multi_system_demo")
```

也可以在 Simulink Library Browser 中打开 `PID Agent Manager` 库，双击 `PID Agent Manager` 启动块。若同时打开多个模型，启动器会先要求选择目标模型。

管理器支持：

- 扫描并列出 PID 所属系统、完整块路径、当前 Kp/Ki/Kd/N 和参数来源。
- 在模型中定位并高亮选中的 PID。
- 将同一系统的两个 PID 自动组成内外环联合调参单元。
- 手工修改角色、组号、执行顺序和 r/y/u/电流信号名。
- 设置停止时间、迭代轮数和每轮候选数。
- 把大型工程拆成顺序计划；每个执行单元强制最多两个 PID。
- 每个单元调用现有 `main_pid_search`，每组候选都经过 Simulink 仿真和固定指标验证。

目录和计划保存在项目本地 `.pid-agent/`，仿真历史保存在 `pid_tuning_runs/`，两者均被 Git 忽略。搜索阶段通过 `SimulationInput` 临时覆盖参数，不永久写回原模型。

当前限制：引用模型中的 PID 可以被发现、查看和编入目录，但在没有显式仿真映射时会标记为 `blocked-referenced-model`，不会自动修改或误调。后续版本将增加引用模型实例映射、Variant 活动配置和确认后写回/回滚功能。

公开的 `pid_ai_multi_system_demo.slx` 包含 3 个系统、5 个 PID：Buck 电压/电流双环、电机速度/电流双环以及单环热控，用于验证选择、分组和顺序计划。