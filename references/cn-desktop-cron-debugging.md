---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# CN Desktop Hermes cron 完整调试记录

记录在 Hermes CN Desktop 0.19.0-cn.7 上配置 cron 定时任务的完整排障路径。
所有错误信息均为实测原文。适用：用户要求"每天自动更新 XX / 每周推送 XX"。

## 正确的最终形态（先看这个）

```bash
# 1. 脚本放 hermes-home\scripts\ 下，用 .sh（bash 执行），内容：
#!/usr/bin/env bash
"/c/Users/<user>/AppData/Local/Programs/Python/Python311/Scripts/uv.exe" run --no-project python "E:/path/to/script.py"

# 2. 用 CLI 创建（不能手写 jobs.json）：
$exe = "E:\...\hermes-agent-cn-runtime-win32-x64.exe"
& $exe cron create "0 9 * * *" "任务说明" --name "job" --script "daily.sh" --no-agent --deliver "weixin" --workdir "<your-workspace-path>"
```

验证：`cron run <jobid>` → 等 60-90s → 看 `hermes-home\logs\agent.log` 中
`cron.scheduler: Job '<id>': delivered to <target>` 行。

## 排障路径

### 错误 1：script 用了绝对路径
```
Failed to create job: Script path must be relative to ~/.hermes/scripts/.
Got absolute or home-relative path: 'E:\...'
```
→ script 字段只填 `~/.hermes/scripts/` 下的文件名（如 `daily_report.sh`）。

### 错误 2：script 用了 .py，运行时被当 hermes 子命令
```
hermes: error: argument command: invalid choice: 'E:\...\<script>.py'
(choose from 'chat', 'model', ...)
```
根因：CN Desktop 是 PyInstaller 打包，cron 调度器用 `sys.executable`（即 hermes exe）
执行脚本路径，.py 路径被解析成 hermes 子命令。.cmd 文件同样失败（"everything else
via Python" 的规则在 PyInstaller 下失效）。
→ 改用 .sh（.sh/.bash 走 bash），bash 位于 `C:\Program Files\Git\usr\bin\bash.exe`。

### 错误 3：直接手写 jobs.json，schedule 被桌面调度器重写为 {}
手写 `"schedule": "0 9 * * *"` 保存后，桌面调度器会把该字段重写为 `{}`，
任务永不触发（`cron list` 显示 `Schedule: ?`）。
→ 必须用 `cron create` CLI 创建，它会把 schedule 存成
`{"kind":"cron","expr":"0 9 * * *","display":"0 9 * * *"}` 并计算 next_run_at。

### 误报：CLI 说 "Gateway is not running"
`cron status` 报 `✗ Gateway is not running — cron jobs will NOT fire`，
但**桌面 App 内置调度器（builtin provider，60s tick）独立运行**，任务照样执行。
CLI 提示可忽略；GUI 日志 `logs\gui.log` 有 `Desktop cron scheduler started (provider=builtin, interval=60s)`。

### 误报：cron run 报 "Ran now: failed"
CLI 触发 `cron run <jobid>` 报 failed，但实际桌面调度器已在 60s 内执行并投递成功
（agent.log 有 delivered 行）。这是 CLI 与桌面调度器的锁竞争假象。

## 投递目标

| deliver | 说明 |
|---|---|
| `local` | 结果存 `hermes-home\cron\output\<jobid>\<timestamp>.md` |
| `weixin` | 投微信 DM，需 .env 有 `WEIXIN_HOME_CHANNEL`（配了 weixin bot 时自动有） |
| `feishu:oc_<chat_id>` | 投飞书 DM（platform:chat_id 通用格式）。chat_id 从 state.db `sessions` 表 `source='feishu'` 的行取 `chat_id` 列（DM 为 `oc_` 开头），凭证在 .env 的 `FEISHU_APP_ID/SECRET` 等键 |
| `origin` | 回到创建任务的会话 |

no_agent 模式：script stdout 原文投递（可作微信周报）；空 stdout = 静默不投。

## 投递通道验证（不跑 agent，秒级）

`<runtime> send -t "feishu:oc_xxx" "测试消息"` —— 复用平台凭据直接发消息，无 LLM 无 agent 循环，
返回 `sent` 即通道 OK。比跑完整 cron 任务验证快得多（cron agent 任务受主模型跨境链路影响可能
几分钟才完成甚至失败，send 完全绕开模型）。适用所有 bot-token 平台（telegram/discord/slack/feishu/weixin）。

## cron agent 任务的手动触发与孤儿执行清理

- `cron run <jobid>` 是**阻塞式**：agent 类任务跑几分钟，前台 timeout 被中断时**执行子进程往往已 spawn**（孤儿），
  重试会双跑——事后查 `cron/output/<id>/` 的时间戳文件数 + `cron/executions.db` 的 `status` 列。
- 孤儿/僵尸 running 记录清理：`UPDATE executions SET status='failed', finished_at=?, error='...' WHERE id='<run_id>' AND status='running'`，
  否则 `cron list` 一直显示该 job 在 running，可能影响下次调度。
- executions.db 表结构：`id/job_id/source(process|direct|builtin)/process_id/pid/status(claimed|running|completed|failed)/started_at/finished_at/error`；
  正常 completed 的执行 `error` 为 NULL。

## 关键路径速查

| 内容 | 路径 |
|---|---|
| cron 任务定义 | `hermes-home\cron\jobs.json`（被桌面调度器管理） |
| 执行结果 | `hermes-home\cron\output\<jobid>\` |
| 调度日志 | `hermes-home\logs\agent.log`（搜 `cron.scheduler`） |
| 桌面调度器日志 | `hermes-home\logs\gui.log`（搜 `Desktop cron scheduler`） |
| 脚本目录 | `hermes-home\scripts\`（cron script 字段的根） |
| CLI | `hermes-home\..\versions\0.19.0-cn.7\hermes-agent-cn-runtime-win32-x64.exe` |

## 数据源（进化历程类报告可用）

- 技能使用统计：`hermes-home\skills\.usage.json`（use_count/patch_count/created_at/last_used_at/created_by）
- 记忆：`hermes-home\memories\MEMORY.md`（agent 记忆，§ 分隔）、`USER.md`（用户画像）
- 成就：`hermes-home\plugins\hermes-achievements\state.json`
- 会话索引：`hermes-home\sessions\sessions.json`
