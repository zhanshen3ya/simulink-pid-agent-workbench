# P0 架构与效果判定

## 数据流

```text
YAML/JSON
   |
   v
strict config schema
   |
   +--> MockRunner ------+
   |                     |
   +--> MatlabRunner ----+--> scan export --> Block/Port/Signal graph
                                      |             |
                                      |             v
                                      |       loop role resolver
                                      |       r, e, y, u_raw, u
                                      |
                                      +--> baseline signals
                                                |
                                                v
                                      normalized metrics
                                                |
                                                v
                                      hard feasibility gates
                                                |
                                feasible -------+------- infeasible
                                   |                        |
                                   v                        v
                              weighted score             score=null
```

## 为什么不能只看曲线

曲线平滑不等于闭环正确。若选择了显示信号、滤波后信号或不属于该 PID 的输出，
超调和稳态误差都可能“很好看”。因此 P0 先用负反馈拓扑确认 `e = r - y`，
再计算动态指标。

## 效果判定顺序

1. 仿真必须成功，所有样本必须有限。
2. 输出、控制、电流和电压绝对边界必须满足。
3. 发散、增长振荡和持续低频振荡必须拒绝。
4. 饱和、超调、调节时间和稳态误差必须满足配置。
5. 仅在以上条件全部满足时计算归一化综合分数。

这种设计保证“更快但过流”的参数不会战胜“稍慢但安全”的参数。

## P0 置信度

置信度由拓扑、语义、动态响应、误差一致性、单位和采样时间组成。未执行动态
探测时，即使静态拓扑完整，也只输出 `suggested_confirmation`，不会自动确认。
