---
scope: Hermes CN Desktop 0.20.0-cn.5
status: workaround
last_verified: '2026-08-14'
---

# Cron 执行器包缺失修复 + SQLite WAL 规避（CN Desktop 0.20，不升级方案）

场景：手动触发 daily-review cron 任务验证管道，发现任务永远不完成。

## 症状签名

- `hermes cron runs <jobid>` 显示 `running` 但 `jobs.json` 里 `last_run_at: None`，任务进程 PID 已死
- `logs/gateway.log`（及 errors.log）反复出现：
  `gateway/run.py:26992 NameError: name 'InProcessCronScheduler' is not defined`
- 打包版行号 ≠ 源码行号（mypyc/PyInstaller 压缩合并），源码里 `gateway/run.py` 的引用在
  `cron.scheduler_provider` 模块（`from cron.scheduler_provider import InProcessCronScheduler`）

## 根因：PyInstaller 打包漏掉整个 cron 包

- `_internal/cron/` 目录**不存在**（`ls _internal/cron` 无输出），`scheduler_provider.py`、
  `scheduler.py`(235KB)、`jobs.py`(139KB) 等 12 个文件全没打进 runtime
- 所有 cron CLI 命令（list/status/runs）仍正常——它们在 `hermes_cli`/`hermes_state` 里，
  只有**执行器**（scheduler_provider）缺失

## 关键认知：磁盘缺 .py ≠ 运行时不可 import

PyInstaller onedir 把纯 Python 模块编译进 mypyc `.pyd` + CArchive（运行时经定制 import 钩子
加载）。检查 `_internal/` 文件系统发现 `hermes_constants.py`、`utils.py` 等全部"缺失"——
但 gateway 能跑，证明它们在 CArchive 里可正常 import。**只有 cron 包是真的漏进 CArchive
模块清单**（import 直接 NameError）。所以磁盘检查不能断言"运行时缺"，判定标准 = 实际进程
的 import 行为（NameError / ModuleNotFoundError）。

## 修复：从源码树复制 cron 包（无需升级）

```bash
cd "<HERMES_CN_DESKTOP>\data\versions"
# _leftovers-YYYYMMDD/ 是完整源码树（升级/安装时保留），cron/ 包完整
cp -r _leftovers-<date>/cron 0.20.0-cn.5/_internal/cron
```

- cron 包依赖（hermes_constants、utils、agent.delegation_context、hermes_cli.config 等）
  全部在 CArchive 里，import 优先命中文件系统 → 成功
- **新进程立即生效**（import 缓存是进程级的）：`cron run`/`cron tick`/`cron tick` 再跑即加载新包，
  无需重启 gateway（gateway 进程内路径要等它自己重启才生效）

## 验证修复

1. `hermes cron run <jobid>`（**前台会阻塞等待任务完成**，spawn 执行子进程；executions.db 里
   `pid` 列是子进程 PID，不是 run 命令自身）
2. `hermes cron runs <jobid>`：出现新 `source=direct` 记录且 PID 活着
3. `logs/agent.log` 出现会话 `cron_<jobid>_<timestamp>` 在跑模型 API 调用 = 执行器正常工作
4. 网络波动（`APIConnectionError` attempt n/3 + `primary_recovery` 重建客户端）是正常容错，
   不是失败；等任务完成看 `last_run_at` 更新

## cron run/tick 行为备忘

- `cron run <id>`：标记 direct 执行 + **阻塞等待**（60s 前台超时是预期，要后台跑）
- `cron tick`：跑到期/被标记任务一次即退出，退出 ≠ 任务完成（gateway 调度器接管）
- 任务进程崩溃会残留 `executions.db` 的 `running` 记录（job 的 last_run_at 仍 None），
  手动清理：`UPDATE executions SET status='failed', finished_at=?, error=? WHERE id='<run_id>'`
- `cron status` 的 "Gateway is running + Ticker heartbeat" 只证明调度器活着，不证明执行器可用

## SQLite WAL-reset 漏洞规避（不升级）

doctor 警告：内置 SQLite 3.50.4 有 WAL-reset 损坏 bug（修 3.51.3+，用户不升级时规避）：

1. 备份全部 db（主文件 + -wal/-shm）到 `hermes-home/backups-<date>/`
2. 对每个 WAL 库：`PRAGMA journal_mode=DELETE`（内部先 checkpoint），再
   `PRAGMA wal_checkpoint(TRUNCATE)` 清残留 wal 文件
3. `database is locked` = 被运行中的 gateway 占用，无法热切换 → 记下，等 gateway 重启后跑
4. 长期脚本：`<your-sqlite-fix>.py`（备份+切换+最终状态检查一体）
5. memory_store.db 可能已是 delete 模式；state.db 若切换失败需重启 gateway 后补做

## TERMINAL_CWD 警告是误报

`cron run` 输出 "⚠ Deprecated .env settings detected: TERMINAL_CWD=... found in .env"——
但 `grep TERMINAL_CWD .env` 为空：它是**桌面应用启动时注入的环境变量**（terminal 工具的 cwd
来源），cron 子命令的检测逻辑误归因到 .env。`hermes doctor` 明确报 "No deprecated config
keys or env vars"。无需处理。
