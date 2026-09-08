---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 模型列表加载不出来（/api/model/options 超时）— 根因与离线缓存修复

## 症状

用户在桌面对话框下方（或 dashboard 的 SWITCH MODEL 对话框）打开模型列表时**永远 loading**，
看起来"找不到想要的模型"——但模型其实存在（直连 provider API 能列出）。

与 `model-picker-pipeline.md` 的区别：那里讲的是列表"正常返回但内容少"（provider 无 key 被 explicit_only 过滤）；
这里讲的是列表**接口本身挂起**，一个模型都渲染不出来。

## 快速判定（60 秒内确认是不是这个病）

1. `/api/*` 业务端点需要 dashboard 的内部会话认证（由桌面 shell 注入，随 dashboard 进程重启自动轮换）。该认证机制属厂商内部实现，本文档不公开细节；如需脚本化验证请先咨询官方支持。
2. 在桌面应用已认证的会话中（或经官方认可的方式）调用 `GET /api/model/options?explicit_only=true`，观察响应耗时。
3. 若 **30-60s 超时**（`/api/status`、`/api/config/defaults` 却秒回）→ 命中本故障。
   对照：`/api/model/info` 也超时（它虽 allow_network=False，但同进程被卡住的请求阻塞）。

## 根因

`build_models_payload`（hermes_cli/inventory.py）组装模型列表时调用 `fetch_models_dev()`，
它会联网拉 `https://models.dev/api.json`（models.dev 的 CDN，解析到 173.244.217.42 / setaptr.net）。
**该域名在中国网络被防火墙丢包**——`netstat -ano | findstr <dashboard-pid>` 可见一条到
`173.244.217.42:443` 的连接卡在 **SYN_SENT**（TCP 握手永远不完成）。

缓存层级（agent/models_dev.py）：
- 内存缓存 → 磁盘缓存 `$HERMES_HOME\models_dev_cache.json` → 网络 → bundled snapshot `_internal\agent\models_dev_snapshot.json`
- 当 `models_dev_cache.json` **不存在**（从未成功联网写过 / 被删 / mtime 过期 >1h）时，每次 `/api/model/options`
  都走网络分支 → 卡死 → 前端一直 loading。

另一个相关缓存：`$HERMES_HOME\provider_models_cache.json`（provider→model-id 列表，1h TTL）。
用户在 UI 点 "Refresh Models" 会清空它 → 触发 live fetch → 网络差时也加剧卡顿。
注意：这两层缓存可能同时缺失（provider 缓存可能被 dashboard 后台 prewarm 间歇性重建，但重建期间请求仍会卡）。

## 修复（0.19.0-cn.7）

把安装包自带的离线快照写成 dashboard 的磁盘缓存，让 `fetch_models_dev()` 走"磁盘缓存命中"分支，完全不触网：

```python
# uv run --no-project python -c "..."
import json, time, os
src = r'<HERMES_CN_DESKTOP>\data\versions\0.19.0-cn.7\_internal\agent\models_dev_snapshot.json'
dst = r'<HERMES_HOME>\models_dev_cache.json'
data = json.load(open(src, encoding='utf-8'))          # 全部 provider，含 opencode-go/kimi-for-coding…
tmp = dst + '.tmp'
with open(tmp, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
os.replace(tmp, dst)
os.utime(dst, (time.time(), time.time()))              # mtime 必须新鲜（TTL 1h 按 mtime 判定）
```

验证：`/api/model/options` 从 60s 超时 → **0.1s 返回**，各 provider 模型完整。

### 根治三层方案（解决"过期后又卡"的复发问题）

1. **立即**：刷新 mtime（上面脚本，无需重启 dashboard）。
2. **根治**：`.env` 加 `HERMES_MODELS_DEV_TIMEOUT=3`（`agent/models_dev.py` 的 `_env_float` 解析该 env，
   控制对 models.dev 的网络超时；下次 dashboard 重启后，即使缓存过期也是 3 秒快速失败 → fallback
   snapshot，永不挂起）。
3. **兜底**：计划任务每 30 分钟静默刷新 mtime——脚本 `<your-cache-refresher>.ps1`
   （内容只有 `(Get-Item $cache).LastWriteTime = Get-Date`），用 PowerShell `Register-ScheduledTask`
   创建（**schtasks 在 CN Desktop terminal 兼容层下 exit 4294967295 不可用**，`New-ScheduledTaskAction`
   + `-Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30)` + `Register-ScheduledTask -Force`）。

## 注意事项 / 坑

- **过期 ≠ 缺失，行为不同**：mtime 过期后 dashboard 会再次发起网络请求；若 SYN_SENT 被防火墙丢包，
  TCP 永不失败 → 不触发 fallback → 请求整体挂起 90s+（不是"一阵延迟"）。且**症状不同**：
  缓存缺失/卡死时桌面模型选择器显示"只剩 user-config
  厂商（kimi-for-coding、siliconflow），built-in 厂商（opencode-go、kimi-coding）消失"——因为
  built-in 厂商的模型目录依赖 models.dev 数据，user-config 厂商的模型列表在 config.yaml 里。
  看到这个症状先查缓存 mtime，别去改 config。
- **验证修复是否生效**：刷新 mtime 后在已认证会话中调 `/api/model/options`（默认参数应含
  opencode-go/kimi-coding/kimi-for-coding/siliconflow/moa 共 5 厂商），耗时应 <1s。
- **1h TTL**：`models_dev_cache.json` 的 mtime 超过 1h 后会再次尝试联网。三层修复中第 2、3 层
  解决复发；若只做了第 1 层，用户 1h 后可能再报。
- **不要删这个缓存文件**：删了 = 回到触网卡死状态。
- **"Refresh Models" 按钮会清 `provider_models_cache.json`**：清空后 live fetch，网络差时列表又卡。
  可先重建 models_dev_cache.json 再让用户点 Refresh。
- **修复不需要重启 dashboard 进程**：磁盘缓存是每请求读取的（有内存缓存但磁盘命中优先）。
  桌面应用重启后新 dashboard 进程同样读该文件，修复持久。
- **模型"存在但找不到"的双重含义**：先确认列表接口能秒回且目标模型在返回的 JSON 里
  （`deepseek-v4-flash` 在 opencode-go 下，`deepseek-ai/DeepSeek-V4-Flash` 是 SiliconFlow 的命名——
  同一个模型两个名字，跨 provider 属正常）。接口正常但仍缺模型 → 才是 `model-picker-pipeline.md` 的
  explicit_only / 缺 key 问题。
