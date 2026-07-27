# P0 验收记录

日期：2026-07-27

## 需求对照

| P0 要求 | 实现 | 验证 |
| --- | --- | --- |
| 仓库审计 | `docs/current_state.md` | 人工核对现有 MATLAB、网关、UI 和测试入口 |
| 兼容配置 Schema | `autopid/config/schema.py` | 未知字段、旧字段转换、原模型保护测试 |
| 标准 PID 扫描 | MATLAB 扫描器 + Python Adapter | 单 PID、双 PID 和 JSON 桥测试 |
| Block/Port/Signal 图 | `autopid/discovery/block_graph.py` | Mock 与 MATLAB 示例图 |
| r/e/y/u_raw/u | `loop_resolver.py` | Buck、同名错误信号、真实二阶模型 |
| 证据和置信度 | `confidence.py`、typed results | 无动态探测只建议确认 |
| 归一化指标 | `evaluation/metrics.py` | 10 V 与 100 V 尺度一致 |
| 稳定性与硬门禁 | `stability.py`、`constraints.py` | 发散、NaN、饱和、过流和仿真失败 |
| Mock Runner | `autopid/runners/mock_runner.py` | 本地无 MATLAB 验收 |
| MATLAB Runner | `autopid/runners/matlab_runner.py` | 真实扫描和基线仿真 |
| 旧接口兼容 | 未改旧 MATLAB/网关入口 | 原有 Python 回归与 MATLAB UI/管理器测试 |
| README/CHANGELOG | 已更新 | `git diff --check` |

## 已执行结果

- Python：27 项通过，0 项失败。
- MATLAB P0：4 项通过，0 项失败。
- 原有 MATLAB UI：2 项通过；多 PID 管理器脚本通过。
- MATLAB Code Analyzer：6 个新增/测试文件，0 条问题。
- 真实 MATLAB 二阶模型：扫描得到 1 个标准 PID，正确追踪负反馈信号；
  基线返回 311 个样本。
- 该模型原始 PID 未通过示例阈值，失败项为调节时间和稳态误差，综合分数为
  `null`。系统没有伪造“最佳参数”。
- `git diff --check`：通过。
- 新增文件敏感信息模式扫描：未发现 Key、Token、密码或私钥。

## 边界

P0 没有动态探测、候选优化、提前终止、鲁棒多工况、频域验证、参数写回或新 UI。
这些属于 P1-P3。本轮没有保存或覆盖任何原始 `.slx`。
