# Simulink PID Agent Workbench

[下载版本](https://github.com/zhanshen3ya/simulink-pid-agent-workbench/releases) · [更新记录](CHANGELOG.md) · [MIT License](LICENSE)

本项目用于读取 Simulink 模型中的 PID 控制器，生成参数，运行仿真，并按设定指标检查结果。

基本流程：

1. 程序或 AI 生成 PID 参数。
2. 程序将参数用于 Simulink 仿真。
3. 程序计算超调量、调节时间、稳态误差等指标。
4. 程序保存每次测试记录和当前最佳结果。

支持单 PID、内外环双 PID，以及一个模型中的多组 PID 顺序调参。AI 仅用于生成参数，所有参数都需要经过 Simulink 仿真。

## 运行环境

已测试环境：

- Windows 11
- MATLAB/Simulink R2024b
- Python 3

其他 MATLAB 版本尚未逐一测试。

本项目不能代替控制系统验证。用于实际设备前，需要完成模型、采样、执行器限制、保护逻辑和硬件测试。

## 安装

1. 从 [GitHub Releases](https://github.com/zhanshen3ya/simulink-pid-agent-workbench/releases) 下载 ZIP 并解压。
2. 在 MATLAB 中切换到解压目录。
3. 执行一次安装命令：

```matlab
install_pid_agent
```

该命令添加所需 MATLAB 路径，并加载 Simulink 的 `PID Agent` 工具栏。如果已打开的模型窗口没有显示新工具栏，请关闭后重新打开该模型。

### PID Agent 标签为空白

如果顶部能看到 `PID Agent`，但标签内容为空白，请在 MATLAB 命令窗口执行：

```matlab
cd('D:\你的路径\simulink-pid-agent-workbench')
install_pid_agent(true)
slUpdateToolstripComponent("pidAgent")
```

安装器会移除来自其他目录的同名 Toolstrip 组件，并确认正式组件从当前项目目录加载。执行后关闭并重新打开模型窗口。

## 在 Simulink 中使用

1. 打开并保存需要调参的 Simulink 模型。
2. 在 Simulink 顶部选择 `PID Agent` 工具栏。
3. 根据需要选择以下入口：

- `调节当前模型`：扫描当前模型并打开内嵌调参界面。
- `调节选中 PID`：优先选择模型中已选中的一个或两个 PID。
- `多 PID 管理器`：为包含多组 PID 的模型设置分组和执行顺序。
- `调参历史`：打开内嵌界面的历史记录页。

内嵌界面固定使用当前模型路径，不需要再次选择文件。模型中只有一个 PID 时会自动选中；选中两个 PID 时可同时调节内外环；选中超过两个 PID 时会打开多 PID 管理器。未保存的模型修改会先提示保存。

本地网关由 MATLAB 自动在后台启动，网页窗口关闭后仍可复用。当前工作目录和 MATLAB Project 路径会传给调参进程，便于模型加载同目录脚本和数据。

## 浏览器单独使用

也可以双击 `启动PID调参控制台.bat`，然后打开 <http://127.0.0.1:8788>。

在页面中：

1. 选择 `.slx` 或 `.mdl` 模型。
2. 点击“读取模型”。
3. 选择一个或两个 PID 控制器。
4. 设置参数范围、信号名称和检查指标。
5. 选择 AI 模式并开始调参。

页面显示运行时间、测试次数、当前参数、仿真指标和历史记录。控制台只监听本机地址。

## 如何判断调参效果

每个任务开始时，程序先使用模型中的原始 PID 参数运行一次仿真，作为基线。之后每个候选参数都按相同信号和指标计算结果。

判定顺序如下：

1. 仿真必须成功，输出不能包含无效数值，闭环必须稳定或在规定时间内收敛。
2. 超调量、调节时间、稳态误差、电流峰值、控制量、纹波和饱和比例等已设置指标必须全部通过。
3. 只有通过硬指标的候选才能作为最终参数。
4. 综合分数用于比较通过硬指标的候选，不用于掩盖任何超限项。
5. 页面同时显示原始基线、当前候选、当前最佳和目标上限，并标出未通过的具体指标。

等级表示与原始 PID 的比较结果：`A` 表示明显改善或原始 PID 不合格而候选已达标，`B` 表示有改善，`C` 表示改善较小或出现退化，`D` 表示未通过硬指标。没有基线的旧任务只显示 `PASS` 或未通过。

当前判定对应一次设定工况。用于电力电子或其他复杂系统时，应分别运行额定工况、负载扰动和参数变化工况，全部通过后再用于实际设备。

## MATLAB 直接运行

单 PID 示例：

```matlab
addpath(genpath(pwd))
examples.create_second_order_pid_demo
result = examples.demo_pid_ai_tuning
```

双 PID 示例：

```matlab
addpath(genpath(pwd))
examples.create_cascade_two_pid_demo
result = examples.demo_two_pid_ai_tuning
```

## 使用自定义模型

最小配置：

```matlab
addpath(genpath(pwd))

cfg = pid_tuning_core.defaultPidTuningConfig();
cfg.modelName = "your_model";
cfg.pidBlockPath = "";           % 留空时选择扫描到的第一个 PID
cfg.referenceSignalName = "r";
cfg.outputSignalName = "y";
cfg.controlSignalName = "u";

result = main_pid_search(cfg);
```

模型需要将信号保存到 `SimulationOutput`。可使用以下任一方式：

- 使用 `To Workspace`，变量名设置为 `r`、`y`、`u`。
- 使用 signal logging，将信号记录到 `logsout`，信号名设置为 `r`、`y`、`u`。

`r` 是参考输入，`y` 是系统输出，`u` 是控制量。信号名称可以在配置中修改。

双 PID 配置示例：

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

两个 PID 的参数会在同一次仿真中一起测试。

## 多 PID 管理器

PID Agent Manager 用于处理模型中的多组 PID。启动方式：

```matlab
addpath(genpath(pwd))
open_system("pid_ai_multi_system_demo")
pid_project_manager.launch("pid_ai_multi_system_demo")
```

也可以在 Simulink Library Browser 中打开 `PID Agent Manager` 库。

管理器提供以下功能：

- 扫描顶层模型、子系统、掩膜块、库链接和引用模型。
- 显示 PID 路径和当前 Kp、Ki、Kd、N。
- 在 Simulink 中定位选中的 PID。
- 设置 PID 的角色、组号和执行顺序。
- 将两个 PID 设置为一组进行调参。
- 设置停止时间、迭代次数、候选数量和信号名称。
- 按顺序运行多组调参任务。

每个调参组最多包含两个 PID。

管理器配置保存在 `.pid-agent/`。运行记录保存在 `pid_tuning_runs/`。这两个目录不会上传到 GitHub。

## AI 接入

AI 为可选功能。支持以下模式：

- 远程 API：支持 OpenAI-compatible `/chat/completions` 接口。
- Code Agent：支持 Codex CLI、MiniMax Code、Claude Code、Qwen Code、Kimi Code CLI 和 CodeBuddy Code。
- 关闭 AI：使用程序生成参数。

远程 API Key 只保存在当前页面内存中，并通过环境变量传给 MATLAB 进程。程序不会将 API Key 写入调参配置或日志。

Code Agent 需要单独安装并登录。发行包不包含这些命令行工具。Qwen Code、Kimi Code CLI 和 CodeBuddy Code 以只读方式接收本次候选参数请求，不修改模型和项目文件。

每个版本的新增功能、修改内容和验证结果记录在 [更新记录](CHANGELOG.md) 和 GitHub Release 中。

自定义参数生成函数：

```matlab
cfg.ai.enabled = true;
cfg.ai.suggestFcn = @yourAiSuggestFcn;
```

函数格式：

```matlab
candidates = yourAiSuggestFcn(state, cfg, count);
```

返回值需要包含 `Kp`、`Ki`、`Kd`，可以包含 `N`。双 PID 模式使用 `candidate.pids(1)` 和 `candidate.pids(2)`。

## 检查指标

程序可计算以下指标：

- `overshootPct`：超调量
- `settlingTime`：调节时间
- `steadyStateError`：稳态误差
- `iae`：绝对误差积分
- `ise`：平方误差积分
- `itae`：时间加权绝对误差积分
- `controlEnergy`：控制能量
- `maxAbsControl`：控制量峰值
- `maxAbsCurrent`：电流峰值
- `outputRipple`：输出纹波
- `controlSaturationFraction`：控制量饱和比例
- `isStable`：稳定性和数值有效性

指标上限在 `cfg.targets` 中设置，评分权重在 `cfg.weights` 中设置。

## 示例模型

发行包包含以下模型：

- `pid_ai_second_order_demo.slx`：单 PID 二阶系统。
- `pid_ai_cascade_two_pid_demo.slx`：内外环双 PID 系统。
- `pid_ai_buck_dual_loop_demo.slx`：Buck 电压环和电流环。
- `pid_ai_multi_system_demo.slx`：3 个系统、5 个 PID。
- `pid_agent_lib.slx`：Simulink 启动库。

Buck 示例使用 24 V 输入、12 V 输出的平均电路模型。运行方式：

```matlab
addpath(genpath(pwd))
report = examples.validate_buck_dual_loop_demo
result = examples.demo_buck_dual_loop_tuning
```

该示例用于仿真测试，不包含完整的开关器件、PWM、损耗和保护电路模型。

## 数据与隐私

公开仓库包含源代码、文档、测试和示例模型。以下内容不上传：

- `pid_tuning_runs/` 中的参数、指标、历史记录和日志
- `.pid-agent/` 中的模型目录和调参计划
- 用户选择的 `.slx` 或 `.mdl` 模型
- `.tools/` 中的本地工具和依赖
- API Key、SSH 密钥、MATLAB 缓存和 Python 缓存

搜索过程中使用 `SimulationInput` 临时设置 PID 参数，不直接保存到原模型。

## 当前限制

- 引用模型中的 PID 可以扫描，但当前不能自动调参。
- Variant 中的 PID 可以扫描；开始调参前仍需确认模型使用了正确的活动配置。
- 最佳参数不会自动写回原模型。
- 自动回滚和跨平台测试尚未完成。
- 使用前需要根据控制对象设置参数范围、信号名称和指标上限。

## 主要目录

```text
.
|-- +pid_agent_ui/
|-- resources/
|-- main_pid_search.m
|-- pid_tuning_core/
|-- pid_project_manager/
|-- local_pid_gateway/
|-- examples/
|-- tests/
|-- pid_ai_second_order_demo.slx
|-- pid_ai_cascade_two_pid_demo.slx
|-- pid_ai_buck_dual_loop_demo.slx
|-- pid_ai_multi_system_demo.slx
`-- pid_agent_lib.slx
```

## 许可证

本项目使用 [MIT License](LICENSE)。
