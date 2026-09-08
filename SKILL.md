---
name: hermes-environment-check
description: >
  Diagnose and repair Hermes Agent environments on Windows. Use when Hermes
  has missing dependencies, broken configuration, unavailable tools or MCP
  servers, network problems, or needs a post-install/upgrade health check.
version: 1.0.0
author: big-blue-fish
license: MIT
platforms:
  - windows
metadata:
  hermes:
    tags:
      - hermes
      - diagnostics
      - windows
      - troubleshooting
      - mcp
---

# Hermes Agent Environment Check & Repair

Systematic procedure for verifying a Hermes Agent installation is complete, diagnosing missing dependencies, fixing configuration issues, and installing required components.

> **Primary target:** Hermes CN Desktop on Windows  
> **Tested primarily with:** Hermes CN Desktop 0.19.0-cn.7, Hermes CN Desktop 0.20.0-cn.5, Hermes CN Desktop 0.20.0-cn.8, Windows 10/11  
> Other Hermes distributions may differ.

> **Version applicability note (实测于 0.20.0-cn.8):**
> - 只读诊断脚本 `scripts/hermes-doctor.ps1` 在 0.19.0-cn.7 / 0.20.0-cn.5 / 0.20.0-cn.8 均可用：能自动识别并报告激活的 runtime（含 `0.20.0-cn.8`），全部 CLI 子命令实测 exit 0、无超时。
> - 修复脚本 `scripts/apply-weixin-cron-fix.py` 有意**仅限 0.20.0-cn.5**（内置版本保护，检测到其它版本会拒绝执行并退出码 1）。原因是其修复的 `InProcessCronScheduler` 打包缺陷只在 0.20.0-cn.5 存在；0.20.0-cn.8 的 runtime 已正常打包 cron 模块，**不需要**该 workaround——在 cn.8 上被拒绝是正确行为，不是脚本缺陷。

## When to Use

|| Trigger | Example |
|---------|---------|
| User asks for health check | "检查运行环境" "check if everything works" |
| Tool or feature unavailable | web_search, browser, vision not working |
| Desktop config warnings | "高级设置提醒配置凭证" |
| After install/upgrade | First run after setup |
| Network problems | "连不上 GitHub" |

## Safety Rules

1. **Diagnose before modifying.** Verify the failure with observed output before applying any fix.
2. **Never expose or print API keys, cookies, tokens, or `.env` contents.** Redact credentials in logs and reports.
3. **Explain before destructive or system-level changes.** Tell the user what will change and why.
4. **Prefer reversible backups before editing configuration.** Copy the original file before mutating it.
5. **Do not install software unless the user requests repair/install action.** Ask first; do not auto-install.
6. **Version-specific workarounds must verify the target Hermes version first.** Refuse to apply fixes if the detected version is not supported.
7. **After every modification, run a verification step.** Confirm the fix with a tool call, process status, or config check.

## Modes

- **Health check (`health-check`)**: read-only diagnosis. Use `scripts/hermes-doctor.ps1` to collect a structured JSON report.
- **Deep diagnosis (`deep-diag`)**: load the matching `references/` file for complex symptoms.
- **Repair (`repair`)**: apply a fix only after the user explicitly confirms. Repair scripts support `--dry-run`.

## Prerequisites

- Windows 10/11 with PowerShell 5.1+ or PowerShell 7+
- Git Bash is optional; only install/use it when a specific reference explicitly requires Bash tooling.
- A Hermes CN Desktop installation with its bundled runtime available; the doctor script discovers the actual runtime path automatically
- Write access to `$HERMES_HOME`

## Rollback Checklist

If a repair makes things worse:

1. Stop the gateway: `Stop-Process -Name "*hermes*gateway*" -Force -ErrorAction SilentlyContinue`
2. Restore `config.yaml` from its `.bak` file.
3. Remove the plugin or script that was just added.
4. Restart the gateway and check `logs/gateway.log` for `Gateway running with N platform(s)`.

## Procedure

### Phase 1: Core System Info

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, OSArchitecture
$PSVersionTable.PSVersion
Get-PSDrive C | Select-Object Name, @{N="Free(GB)";E={[math]::Round($_.Free/1GB,1)}}
whoami
```

### Phase 2: Hermes CLI Health

Hermes CLI is often not in PATH. For first-time users, prefer the doctor script because it discovers both `HERMES_HOME` and the bundled runtime without requiring a guessed path.

```powershell
# Recommended: read-only one-shot diagnosis
& .\scripts\hermes-doctor.ps1
```

If you need manual CLI commands after the doctor reports `runtime.path`, copy that exact path from the report instead of constructing a path from `HERMES_HOME`.

### Phase 3: Dependency Check

```powershell
python --version
pip --version
git --version
node --version
npm --version
rg --version
uv --version
ffmpeg -version
```

### Phase 4: Hermes Home Directory

```powershell
$hh = $env:HERMES_HOME   # do NOT use $home — read-only variable in PowerShell, assignment throws
Get-ChildItem $hh -Directory
Test-Path "$hh\config.yaml"
Test-Path "$hh\.env"
Test-Path "$hh\state.db"
```

### Phase 5: Configuration Audit

Check these common issues:

1. **Encoding**: config.yaml must be UTF-8 WITHOUT BOM
2. **API keys**: Must be in `.env`, not `config.yaml`
3. **Model names**: SiliconFlow uses `org/model` format (safe to ignore doctor warnings)
4. **Gateway**: `hermes gateway status` — optional for CLI/Desktop
5. **Dashboard theme**: Options: default, midnight, ember, mono, cyberpunk, rose

### Phase 6: Network Connectivity

The doctor checks DNS resolution and HTTPS reachability. An ICMP/ping failure alone is not treated as proof that HTTPS is unavailable, because many networks block ICMP while allowing web/API traffic. Review the per-host `dns`, `https`, and `status_code` fields in the JSON report.

### Phase 7: Skills & Processes

```powershell
& $runtime.FullName skills list
Get-Process | Where-Object { $_.ProcessName -match "hermes|gateway|python" } |
    Select-Object ProcessName, Id, @{N="Mem(MB)";E={[math]::Round($_.WorkingSet64/1MB,1)}}
```

### Phase 8: MCP Server Diagnostics

```powershell
# Check MCP stderr log (review for secrets before sharing)
Get-Content -Tail 20 "$env:HERMES_HOME\logs\mcp-stderr.log"

# The doctor safely redacts common credentials when collecting MCP config.
& .\scripts\hermes-doctor.ps1
```

## Reporting

Present the final result as a tiered health report — 🟢 core OK / 🟡 warnings (non-blocking) / ⚪ optional-not-installed — separating real failures from optional enhancements, and back each claim with observed output (doctor line, tool error string, ping result, version string). Close with a clear overall verdict (e.g. "All checks passed") plus a short fix-it list for the 🟡 items.

## Problem Routing

Diagnose first, then load the matching reference for the root cause and verified fix.

### Installation / runtime layout
- Hermes CN Desktop layout, bundled resources, PowerShell exit-code quirks: `references/hermes-cn-desktop-layout.md`
- PyInstaller runtime diagnostics (missing SDK, .env audit, misleading MCP stderr): `references/pyinstaller-runtime-diagnostics.md`
- Runtime deep diagnostics (requires official authorization): `references/pyinstaller-pyc-inspection.md`
- Version diff investigation: `references/version-diff-investigation.md`

### Configuration / providers
- Safe edits to `config.yaml` / `.env` / provider lists: `references/config-provider-editing.md`
- Provider block clobbered by desktop model switcher: `references/providers-block-clobber-restore.md`
- Preset provider removal from desktop UI: `references/preset-provider-removal.md`
- Credential store locations (.env / config.yaml / auth.json): `references/credential-locations-and-cleanup.md`
- Live provider/model verification: `references/provider-model-verification.md`
- Model provider refresh cache: `references/model-provider-refresh.md`

### Models / model picker
- Model picker pipeline and "only a few models" symptoms: `references/model-picker-pipeline.md`
- `/api/model/options` timeout / offline fallback: `references/model-options-timeout-offline-cache.md`
- Switching models inside a single provider: `references/model-switching.md`
- Desktop frontend internals and UI model injection: `references/desktop-app-frontend-internals.md`, `references/desktop-model-picker-sync.md`
- Dashboard API and model data source: `references/dashboard-diagnostics.md`

### MCP
- General MCP troubleshooting: `references/mcp-troubleshooting.md`
- Stdio server add syntax and stale npx cache: `references/mcp-stdio-add-syntax.md`
- Playwright MCP browser install: `references/playwright-mcp-browser-install.md`
- Free search MCP recipe (DDG/Bing/Brave/Serper/Bocha/searx/Mojeek): `references/free-search-mcp.md`

### Messaging / gateway / cron
- WeChat/Feishu gateway lifecycle and platform toggles: `references/messaging-platforms-gateway.md`
- WeChat gateway crash diagnosis (`InProcessCronScheduler` NameError): `references/weixin-gateway-crash-diagnosis.md`
- Weixin integration cleanup (old account files): `references/weixin-integration-cleanup.md`
- Cron package repair (copy missing `cron/` module): `references/cron-runtime-package-repair.md`
- Cron script-mode debugging (`.sh` vs `.py`/`.cmd`): `references/cn-desktop-cron-debugging.md`
- Scheduled automation recipes (schtasks / silent P/Invoke): `references/scheduled-automation.md`
- WeChat cron fix injection notes (version-gated workaround): `references/weixin-cron-fix-injection-notes.md`

### Memory / sessions / data
- Memory provider options and holographic ops: `references/memory-provider-options.md`, `references/holographic-memory-ops.md`
- Session REST API semantics (archive/restore, **DELETE is permanent**): `references/desktop-session-api-and-plugin.md`
- Token usage / session data forensics: `references/hermes-usage-data-forensics.md`

### Vision / automation / tools
- Vision auxiliary model diagnosis: `references/vision-auxiliary-diagnosis.md`
- Agent-browser setup: `references/agent-browser-setup.md`
- Skill pack install workflow: `references/skill-pack-install.md`
- Skill library health check: `references/skill-library-health-check.md`

### Doctor false positives
- Common doctor mis-reads: `references/doctor-false-positives.md`

## Quick Pitfalls

1. **Encoding**: Use `[System.IO.File]` methods, not `Set-Content -Encoding UTF8`, to keep Chinese text intact.

2. **`.env` access**: `read_file` tool may be blocked; use `terminal` + `Get-Content` instead.

3. **config.yaml edits**: `patch`/`write_file` tools may refuse; use `uv run --no-project python` or `[System.IO.File]::WriteAllText()`.

4. **API keys**: Keep them in `.env`, **never** in `config.yaml`. Both are read by Hermes, but only `.env` is safe from accidental exposure in logs or backups.

5. **PATH refresh**: Restart the shell after `winget install` — new tools won't be discoverable until the shell re-reads PATH.

6. **`&` backgrounding pitfall**: Avoid bare `& $runtime skills list` in Hermes terminal (may timeout or hang). Use `Start-Process ... -RedirectStandardOutput` for reliable capture, or `cmd /c <command>` for simple subcommands.

7. **Python heredoc**: Do not pipe `python3 - <<'PY' ... PY` into CN Desktop terminal — CN Desktop's terminal layer doesn't buffer stdin correctly. Write a `.py` file and run it with the full executable path instead.

8. **Phase 3 empty output (WindowsApps stub)**: `python --version` may print nothing through the Hermes terminal layer because `%LOCALAPPDATA%\...\WindowsApps\python.exe` is a compatibility stub that returns exit 9009 without output. Workaround: confirm with `pip --version` or use `py.exe --version` (Windows native launcher), or use the full path to your actual Python interpreter (`C:\Users\<user>\AppData\Local\Programs\Python\Python311\python.exe --version`). `hermes-doctor.ps1` detects this and reports the installed path correctly.

For detailed context on each pitfall and their root causes, see the matching reference section above.
