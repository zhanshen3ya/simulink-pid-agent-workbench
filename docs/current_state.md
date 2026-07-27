# P0 当前状态审计

审计日期：2026-07-27

## 1. 原系统如何运行

现有系统以 MATLAB 为核心：

- `main_pid_search(cfg)` 负责候选参数闭环搜索。
- `run_pid_tuning_from_json.m` 为本地网页网关提供 JSON 入口。
- `pid_tuning_core/+pid_tuning_core/inspectPidModel.m` 扫描模型和 PID。
- `pid_tuning_core/+pid_tuning_core/evaluatePidRun.m` 计算原始指标。
- `local_pid_gateway/` 启动本地 HTTP 服务和浏览器 UI。
- `+pid_agent_ui/` 与 `resources/` 提供 Simulink Toolstrip 入口。

现有接口继续保留，本轮没有删除、重命名或改变这些入口。

## 2. 已有 PID 扫描方式

原扫描器使用 `find_system` 遍历普通块，通过块描述中包含 `pid`，且
DialogParameters 同时具有 `P`、`I`、`D` 来识别控制器。它能读取参数和
已记录信号名称，但没有形成 Block/Port/Signal 图，也不能说明某个信号为何
是参考、反馈或执行器输入。

P0 新增只读适配器，仅支持标准 PID Controller 家族，并导出稳定 JSON 合同。
自定义 PID 子系统、未知 Mask、复杂 Variant 和模型引用只报告为未解析，不宣称支持。

## 3. 已有指标与门禁

原系统已有超调、调节时间、稳态误差、IAE/ISE/ITAE、控制能量、电流峰值、
纹波和饱和比例等指标，也能检查阈值。

主要缺口：

- 不同电压、电流和位置量纲之间缺少统一归一化。
- 稳定性、仿真失败和绝对安全约束没有统一成“先门禁、后评分”的合同。
- 错误信号选错时，指标仍可能数值正常。
- 失败原因、证据和置信度缺少结构化输出。

P0 新增 NIAE、NISE、NITAE、NRMSE、归一化稳态误差、归一化超调、
控制代价、控制变化量、饱和比例、原始纹波和保守稳定性分类。任何硬约束失败
时 `score` 必须为 `null`。

## 4. 配置结构

原网页入口主要使用扁平 JSON 字段。P0 新增严格 YAML/JSON schema：

`project`、`model`、`controller`、`signals`、`discovery`、`evaluation`、
`constraints`、`optimization`、`robustness`、`deployment`。

未知字段会被拒绝，旧网关常用字段会被明确转换。P0 强制
`deployment.overwrite_original: false`，不允许覆盖原始模型。

## 5. 扩展边界

本轮新增代码放在 `autopid/` 与 `matlab/`，通过 Runner 和 JSON 合同连接，
避免把新判定逻辑直接塞入旧搜索循环。

P0 明确不做：

- LLM API、Code Agent 或远程服务接入。
- 自动写回 PID 参数。
- 大规模优化、断点续跑和并行仿真实现。
- 鲁棒性批量工况、部署和报告 UI。
- 通用 MIMO、任意自定义 PID 或所有 Simscape 拓扑识别。

这些字段可以出现在配置中作为向后兼容的接口占位，但本轮 CLI 只执行
`scan`、`baseline` 和 `validate`。
