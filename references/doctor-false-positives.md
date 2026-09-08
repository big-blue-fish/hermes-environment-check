---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# doctor 误报判定手册（0.20.0-cn.5）

`hermes doctor` 的输出并非全部可信。以下三类已确认的误报及判定证据链，看到对应症状先按此判定，不要盲目按 doctor 提示操作。

## 1. `⚠ TERMINAL_CWD=... found in .env — deprecated` — 必误报，勿按提示操作

**症状**（doctor 输出）：
```
⚠ Deprecated .env settings detected:
  ⚠ TERMINAL_CWD=C:\Users\<USER> found in .env — this is deprecated.
  Move to config.yaml instead:  terminal:
    cwd: /your/project/path
  Then remove the old entries from .../hermes-home/.env
```

**真相**：`.env` 里根本没有该键（grep 全无匹配）。TERMINAL_CWD 是 **Hermes terminal 后端注入的进程环境变量**，与 TERMINAL_DOCKER_IMAGE / TERMINAL_MODAL_IMAGE / TERMINAL_TIMEOUT 等整族 `TERMINAL_*` 变量一起存在，值 = 终端工作目录。doctor 把进程环境变量误判为 .env 残留。

**判定证据链**（三条全中 = 误报）：
```bash
grep -in "terminal\|cwd" .env    # → 无匹配，.env 干净
env | grep -i terminal           # → TERMINAL_* 整族存在（后端注入痕迹）
powershell -NoProfile -Command '[Environment]::GetEnvironmentVariable("TERMINAL_CWD","User"); [Environment]::GetEnvironmentVariable("TERMINAL_CWD","Machine")'   # → 空
```

**不要执行** doctor 建议的 .env 删除/迁移：该变量是 terminal 工具传递工作目录的机制，删掉反而可能破坏终端 cwd 初始化。识别为误报后直接跳过。

## 2. `✗ Kimi / Moonshot (invalid API key)` — 可能是误报

**症状**：doctor API 连通性段报 Kimi/Moonshot key 无效（同段 DeepSeek ✓）。

**真相**：key 实际可能有效。验证命令：
```bash
K=$(grep "^KIMI_API_KEY=" .env | cut -d= -f2- | tr -d '\r')
curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 15 -H "Authorization: Bearer $K" "https://api.moonshot.cn/v1/models"
# → HTTP 200 = key 有效，doctor 误报
```

**教训**：doctor 的 key 检查**两个方向都不可全信**——“✓ key configured” 只证明键存在（见 SKILL.md 主 pitfall），而 “✗ invalid API key” 也可能是假阳性。对任何 doctor key 结论动手前，先用真实 API 探测验证。

## 3. `profile <name>: ⚠ missing config, no alias` — 正常态

**症状**：doctor Profiles 段：`✓ 1 profile(s) found / ✓ <profile>: ⚠ missing config, no alias`。

**真相**：profile 目录有 profile.yaml（description 等）但无独立 config.yaml 时即报此提示。属正常——该 profile 继承主配置运行，profile.yaml 存在即说明 profile 已注册，不是故障，无需修复。

## 历史已确认的相关误报（汇总）
- SiliconFlow 模型名 vendor 前缀警告 = doctor 假阳性
- "OAuth not logged in" = 可选 provider 未登录的正常状态
