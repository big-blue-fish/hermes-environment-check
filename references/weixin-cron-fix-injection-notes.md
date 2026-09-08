---
scope: Hermes CN Desktop 0.20.0-cn.5
status: workaround
last_verified: '2026-08-14'
---

# 0.20.0-cn.5 `InProcessCronScheduler` NameError 临时修复说明

> **Scope:** Hermes CN Desktop 0.20.0-cn.5  
> **Type:** Temporary compatibility workaround  
> **Known issue:** `NameError: InProcessCronScheduler`  
> **Not guaranteed for:** 0.20.0-cn.6+, standard Hermes, future releases.

崩溃诊断与排障流程见 `references/weixin-gateway-crash-diagnosis.md`；本文记录修复机制、验证与清理。

## Root cause

`gateway/run.py` 的 `start_gateway` 中 `isinstance(cron_provider, InProcessCronScheduler)` 引用了未导入的名字（该作用域只 import 了 `resolve_cron_scheduler`）。`cron/scheduler_provider.py` 存在且类可正常导入，因此这是源码级 missing-import bug，不是 PyInstaller 打包缺模块。把该名字注入 `gateway.run` 的模块级 globals 后，错误即消失。

## Workaround mechanism

Create a standalone user plugin that imports `gateway.run` and assigns:
```python
import gateway.run as _gateway_run
from cron.scheduler_provider import InProcessCronScheduler as _in_process
_gateway_run.InProcessCronScheduler = _in_process
```

Load order: user plugins are scanned from `$HERMES_HOME/plugins/` during gateway startup, before `start_gateway` reaches the cron section. Because Python function globals are resolved at call time, the injected attribute is visible when `isinstance(...)` runs.

## Verification markers

After applying the plugin and restarting gateway, `logs/gateway.log` should show:
```
✓ weixin connected
✓ feishu connected
Gateway running with 2 platform(s)
Gateway housekeeping started (interval=60s)
kanban dispatcher: embedded in gateway (interval=60.0s)
```

`Executor shutdown has been called` errors on Feishu and `inbound` without `inbound message:` on WeChat both stop.

## Files

- Plugin source: `$HERMES_HOME/plugins/gateway-cron-name-fix/`
- One-shot installer script: `scripts/apply-weixin-cron-fix.py` in this skill.

## Cleanup

Remove from `plugins.enabled` and delete `$HERMES_HOME/plugins/gateway-cron-name-fix/` once an official fixed runtime (0.20.0-cn.6+) is installed.
