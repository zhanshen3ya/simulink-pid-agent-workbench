# P0 调研记录

调研日期：2026-07-27

## MathWorks: find_system

- 来源：<https://www.mathworks.com/help/simulink/slref/find_system.html>
- 解决问题：以受支持方式查找模型块、线和对象。
- 采用：扫描标准块时使用 `LookUnderMasks`、`FollowLinks`，并在可用时使用
  `Simulink.match.allVariants`。
- 未直接照搬：文档示例不提供本项目需要的 Block/Port/Signal 稳定 JSON 合同。
- 落地建议：MATLAB 只负责模型事实导出，Python 负责证据、置信度和策略判定。

## MathWorks: programmatic model search

- 来源：<https://www.mathworks.com/help/simulink/ug/find-models-and-model-elements-programmatically.html>
- 解决问题：说明模型元素、句柄和层次搜索的基本方式。
- 采用：使用块句柄/SID 生成稳定块 ID，端口句柄只在当前扫描过程中映射。
- 未直接照搬：不把显示名称当作唯一 ID，因为名称可重复且可包含特殊字符。
- 落地建议：UI 展示 path/name，内部图与历史记录使用稳定 ID。

## MathWorks: model-based PID tuning

- 来源：<https://www.mathworks.com/help/slcontrol/automatic-pid-tuning.html>
- 解决问题：区分基于线性化模型的设计和闭环仿真验证。
- 采用：候选参数必须经过同一模型、同一工况和同一门禁验证。
- 未采用：P0 不调用 PID Tuner，也不假定所有模型都能可靠线性化。
- 落地建议：后续初值生成器可接 PID Tuner 或 `pidtune`，但不得绕过仿真门禁。

## MathWorks: automatic PID tuning introduction

- 来源：<https://www.mathworks.com/help/slcontrol/ug/introduction-to-automatic-pid-tuning.html>
- 解决问题：明确响应速度、鲁棒性、扰动抑制和约束之间存在权衡。
- 采用：评价配置按电压、电流、速度、位置和扰动抑制区分权重。
- 未采用：本轮不把单个加权分数当成安全判定。
- 落地建议：先执行仿真/稳定性/绝对约束门禁，再对可行候选比较归一化分数。

## SciPy: find_peaks

- 来源：<https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.find_peaks.html>
- 解决问题：峰值及峰包络可用于区分衰减、持续和增长振荡。
- 采用：采用峰包络、滚动 RMS 和过零率的组合思想。
- 未直接调用：P0 保持依赖最小，内部实现简单局部峰检测，避免把高频 PWM 纹波
  直接判为低频失稳。
- 落地建议：后续动态探测可增加频率分离和最小峰突出度，并把探测证据单独记录。

## 研究结论

P0 的核心不是“自动猜信号名”，而是把每个判断拆成可审计事实：

1. PID 输入来自哪个信号。
2. 误差 Sum 的正负端分别连接什么。
3. PID 输出经过哪些限幅、PWM 或速率限制后进入执行器。
4. 静态拓扑、语义、单位、采样时间和动态探测分别贡献多少置信度。
5. 调参效果是否先通过硬门禁，再进入可行候选排名。

代码均为本项目独立实现，没有复制外部仓库实现。
