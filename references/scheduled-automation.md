---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Windows 定时自动化：任务计划程序 + 静默脚本

Verified on Hermes CN Desktop 0.19.0-cn.7. Use case: run maintenance
scripts on a schedule with zero LLM-token cost and OS-native reliability.

## When to use

- Hermes cron `--script` mode fails on CN Desktop (see SKILL.md pitfalls).
- You want zero LLM-token cost and OS-native reliability.
- You need to run a PowerShell script at fixed intervals (hourly, daily, etc.).

## 1. Windows Task Scheduler (schtasks)

```powershell
# create: hourly, runs as current user in interactive session
schtasks /create /tn "<TASK_NAME>" /tr "powershell -NoProfile -ExecutionPolicy Bypass -File <path-to>\your-script.ps1" /sc HOURLY /f

# verify + check last result
schtasks /query /tn "<TASK_NAME>" /fo LIST          # status, next run
schtasks /query /tn "<TASK_NAME>" /v /fo LIST       # + Last Run Time / Last Result (0 = success)

# manage
schtasks /run /tn "<TASK_NAME>"        # trigger immediately (end-to-end test)
schtasks /end /tn "<TASK_NAME>"
schtasks /delete /tn "<TASK_NAME>" /f
```

Schedules: `/sc HOURLY` (top of hour), `/sc MINUTE /mo 30`, `/sc DAILY /st 09:00`, `/sc ONLOGON`.

### Quoting pitfalls

1. **`schtasks` 直接调用在 Hermes terminal 兼容层下输出不可靠，用 `Start-Process ... -RedirectStandardOutput` 包装。**
2. **`Start-Process -ArgumentList` splits values containing spaces**: `/tr "powershell.exe -NoProfile ..."` arrives as separate args and schtasks errors `Invalid argument/option - '-NoProfile'`. Wrap the whole value in embedded quotes: `@('/create','/tn','<TASK_NAME>','/tr','"powershell.exe -NoProfile -ExecutionPolicy Bypass -File <path-to>\your-script.ps1"','/sc','HOURLY','/f')`. Same trick for any argument with spaces (`'every 1h'` → `'"every 1h"'` for `hermes cron create`).

### End-to-end verification pattern

```
schtasks /run /tn <TASK_NAME> → SUCCESS
sleep 30 → script's log gains a new "OK" line
schtasks /query /tn <TASK_NAME> /v → Last Result: 0
```

## 2. 计划任务 + PowerShell `-WindowStyle Hidden` 仍会闪黑窗

计划任务以 **Interactive 登录类型**启动 `powershell.exe -NoProfile -WindowStyle Hidden -File xxx.ps1` 时，黑窗口仍可能在隐藏样式生效前闪现（conhost 先建窗口、PowerShell 后应用样式）——用户看到的就是"cmd 闪了一下"。`-WindowStyle Hidden` 在计划任务场景**不可靠**（尤其任务 Settings.Hidden=False 时）。

**排查"窗口闪现"的取证链**：
1. `Get-ScheduledTask | ForEach-Object { try { $i = $_ | Get-ScheduledTaskInfo -ErrorAction Stop } catch {}; if ($i -and $i.LastRunTime -gt (Get-Date).AddHours(-2)) { ... } }` 列出最近 2h 运行过的任务（LastRunTime + LastTaskResult=0x0 = 成功）
2. 对可疑任务看动作：`$t.Actions | % { $_.Execute + " " + $_.Arguments }`
3. 用 PowerShell Operational 日志交叉确认：`Get-WinEvent -LogName Microsoft-Windows-PowerShell/Operational` 在任务运行时刻出现 **40962（启动）/53504（引擎就绪）/40961（provider 启动）** 三连事件 = 该任务确实拉起了 powershell（Security 4688 进程创建审计默认关闭，查不到 cmd.exe 启动；TaskScheduler/Operational 日志默认也禁用）

**根治（真正无窗口）**：VBS 包装 —— 任务动作改为 `wscript.exe "C:\...\run-hidden.vbs"`，vbs 内 `WScript.Shell.Run "powershell -NoProfile -WindowStyle Hidden -File xxx.ps1", 0, True`（0 = 隐藏窗口，True = 等待完成；vbs 必须纯 ASCII，UTF-8 中文注释报 0x800A01A8）。不需要的任务直接 `schtasks /delete /tn <name> /f`。

## 3. 修改已存在任务的触发器（UAC 提权坑）

用户改已注册任务（如 <TASK_NAME> 从每 2 小时改每小时整点）时的三个坑：

**坑 1：RunLevel=Highest 的任务，非提权 shell 修改被拒**
任务 Principal.RunLevel = Highest 时（`Get-ScheduledTask` → `$t.Principal.RunLevel` 查看），普通 shell 里 `Set-ScheduledTask -InputObject $t` 报 `PermissionDenied`（CimException，错误文本乱码为"拒绝访问"）。先确认当前权限：`[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)` → False。

**坑 2：UAC 提权必须用 -File 脚本文件，绝不用内联 -Command**
`Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -Command \"...$t...\""` 多层嵌套引号会解析失败（bash 先展开、PS 再解析，报"找不到实际参数$t"）。正确姿势：
```powershell
# 1) write_file 写 <your-fix-trigger>.ps1（纯 ASCII，避免编码坑）
# $t = Get-ScheduledTask -TaskName "<TASK_NAME>"
# $trig = New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 0 -Second 0) -RepetitionInterval (New-TimeSpan -Hours 1)
# $t.Triggers = $trig; Set-ScheduledTask -InputObject $t | Out-Null
# "REP=$($t2.Triggers[0].Repetition.Interval) NEXT=$($info.NextRunTime)" | Out-File result.txt
# 2) 执行（会弹 UAC 框，用户点"是"）：
Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File <your-fix-trigger>.ps1"
# 3) 提权进程的 stdout 拿不到——脚本把结果写文件，父进程读文件验证
```

**坑 3：`[TimeSpan]::MaxValue` 作 -RepetitionDuration 超出任务计划器上限**
报 `Set-ScheduledTask : XML 校验…Duration:P99999999DT23H59M59S`（HRESULT 0x80041318）。**省略 -RepetitionDuration 即无限重复**：`New-ScheduledTaskTrigger -Once -At (Get-Date -Hour 0 -Minute 0 -Second 0) -RepetitionInterval (New-TimeSpan -Hours 1)`（不传 Duration）→ 无限重复，锚点 = StartBoundary。

**"整点运行"的语义**：旧触发器 NextRunTime 在 :49 分 → 触发器是"某时刻起每 N 小时"而非整点。改整点 = StartBoundary 设当天 00:00 + RepetitionInterval PT2H/PT1H → NextRunTime 立即变为 22:00、14:00 等整点（start boundary 是重复锚点）。改完验证：`Get-ScheduledTask -TaskName X | % { $_.Triggers }` 看 StartBoundary/Repetition.Interval/Duration + `Get-ScheduledTaskInfo` 看 NextRunTime。**`schtasks /run /tn X` 可立即触发一次做端到端测试**（返回"成功: 尝试运行"，`/query /v` 的 Last Result 0x0 = 成功）。

**修改触发器保留其余配置**：`$t = Get-ScheduledTask; $t.Triggers = $trig; Set-ScheduledTask -InputObject $t` 只换触发器，Action/Principal/Settings 原样保留（比 schtasks 删除重建干净）。

## 4. Other Windows traps seen on this box

- **`python` on PATH is the WindowsApps stub** (`C:\Users\<USER>\AppData\Local\Microsoft\WindowsApps\python.exe`): running it returns exit 9009 ("command not found") with no output. The real interpreter is `C:\Users\<USER>\AppData\Local\Programs\Python\Python311\python.exe`. Always use the full path (or `py.exe`) when a wrapper script depends on Python. This is also why `hermes` CLI subcommands that shell out to `python` can fail while everything else works.
- **Git-Bash `tar` misparses Windows drive paths**: `tar -xf "E:\path\file.zip"` fails with `Cannot connect to E: resolve failed` — it treats `E:` as a remote host. Use forward slashes (`E:/path/file.zip`) with `--force-local`, or just use PowerShell's `Expand-Archive` (native, slower but reliable).
- **robocopy for bulk restore**: `robocopy <src> <dst> /E /R:1 /W:1 /NFL /NDL` — exit codes 0–7 are success; running processes lock .exe/.dll/.pyd (ERROR 32, listed as FAILED) but plain .py/text files copy fine. For "restore a directory from a zip": `Expand-Archive` to a temp dir, then robocopy over.