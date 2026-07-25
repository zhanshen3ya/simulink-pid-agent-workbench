# 更新记录

本文件记录各版本的主要变化。GitHub Release 同步提供对应版本的更新说明。

## [未发布]

暂无。

## [v0.2.1] - 2026-07-25

### 新增

- 支持通过 Qwen Code 生成 PID 候选参数。
- 支持通过 Kimi Code CLI 生成 PID 候选参数。
- 支持通过 CodeBuddy Code 生成 PID 候选参数。
- 前端可以发现、选择和测试上述 Code Agent。

### 修改

- Code Agent 请求直接传递参数数据，不再要求工具读取调参任务文件。
- Qwen Code 和 Kimi Code CLI 使用只读规划模式。
- CodeBuddy Code 使用规划模式，并禁用命令执行、文件修改和网络搜索工具。
- 改进不同 Code Agent 返回格式的 JSON 解析。

### 验证

- 增加三种 Code Agent 的调用参数和返回数据自动测试。
- 检查 Python 代码语法和前端 JavaScript 语法。

## [v0.2.0] - 2026-07-25

### 新增

- 支持扫描模型中的多个 PID 控制器。
- 支持创建调参计划，并按系统或控制环分组。
- 支持在 Simulink 启动库中选择待调 PID。
- 增加多系统、多 PID 示例模型。

### 修改

- 简化 README 说明。
- 公开仓库不上传调参任务数据和用户模型。

## [v0.1.0] - 2026-07-12

### 新增

- 提供 PID 调参控制台、Simulink 仿真验证和历史记录。
- 支持远程 API、Codex CLI、MiniMax Code 和 Claude Code。
- 提供单 PID、双 PID 和 Buck 双环示例。
