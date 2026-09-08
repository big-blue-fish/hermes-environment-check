---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
related:
- config-provider-editing.md
- dashboard-diagnostics.md
---

# Hermes 会话中切换 Model / Provider

> 适用场景：用户在 Hermes Desktop 或 CLI 会话中，想要切换到另一个模型，或报告"无法切换模型"。
> 验证于 0.19.0-cn.7。

## 核心命令：`/model`

在会话中直接输入：

```
/model <model-name>
```

### 同 provider 内切换（最常见场景）

当只配置了一个聚合 provider（如 `opencode-go`），所有模型都在它名下——**无需切换 provider，直接用 `/model <model-name>` 即可**：

```
/model kimi-k2.7-code
/model deepseek-v4-pro
/model glm-5.1
/model qwen3.7-max
/model minimax-m3
```

这是用户最常困惑的点：看到 UI 下拉只有当前 provider 名称，以为"无法切换其他厂商模型"，实际上所有厂商的模型都在同一个聚合 provider 下，直接 `/model` 即可。

### 跨 provider 切换

```
/model <provider>:<model-name>
```

**切换到硅基流动的 DeepSeek-V4-Flash：**
```
/model siliconflow:deepseek-ai/DeepSeek-V4-Flash
```

### 备选语法：`--provider` 标志

```
/model --provider siliconflow deepseek-ai/DeepSeek-V4-Flash
```

### 持久化切换

默认 `/model` 只对当前会话生效。重启后恢复 config.yaml 中配置的默认模型。

要永久保存：
```
/model --global kimi-k2.7-code
```

## 诊断流程：用户报告"无法切换模型"

当用户说"无法切换其他厂商模型"时，按此流程诊断：

### Step 1: 读 config.yaml 确认当前 provider 和已配置 providers

```powershell
# 读 config.yaml 的 model 段和 providers 段
Get-Content "$env:HERMES_HOME\config.yaml" | Select-String -Pattern "model:|provider:|providers:" -Context 0,5
```

关键信息：
- `model.provider` = 当前激活 provider（如 `opencode-go`）
- `model.default` = 默认模型（如 `glm-5.2`）
- `providers` 段 = 已定义的 provider 列表（只有 `opencode-go` 说明只配了一个聚合端点）

### Step 2: 检查 .env 中哪些 API Key 存在

```powershell
Get-Content "$env:HERMES_HOME\.env" | Where-Object { $_ -match "API_KEY" -and $_ -notmatch "^#" } | ForEach-Object { ($_ -split "=")[0] + " (已设置)" }
```

仅配置了部分 provider 凭证时，未配置的 provider 会被 explicit-only 逻辑过滤；其他厂商直连端点（DEEPSEEK_API_KEY、ZAI_API_KEY 等）未配置 → UI 中的其他 provider 选项选中后会失败。

### Step 3: 检查 auth.json 凭证池

```powershell
$auth = Get-Content "$env:HERMES_HOME\auth.json" -Raw | ConvertFrom-Json
$auth.credential_pool.PSObject.Properties.Name   # API-key 类凭证池
$auth.providers.PSObject.Properties.Name           # OAuth 凭证
$auth.active_provider                              # 最近激活的 OAuth provider
```

credential_pool 中的名称就是可用 provider 列表（如 `opencode-go`、`kimi-for-coding`、`siliconflow`、`kimi-coding`）。

### Step 4: 列出当前 provider 的所有可用模型

```powershell
$snap = Get-Content "<HERMES_CN_DESKTOP>\data\versions\0.19.0-cn.7\_internal\agent\models_dev_snapshot.json" -Raw | ConvertFrom-Json
$snap.'opencode-go'.models.PSObject.Properties.Name
```

完整的当前模型清单可从 `provider_models_cache.json` 或安装目录 `_internal\agent\models_dev_snapshot.json` 查询，勿在此复制快照清单（会随版本过时）。

### Step 5: 向用户解释

1. 如果用户只有一个聚合 provider（opencode-go）：**直接用 `/model <model-name>` 切换即可**，所有模型都在同一 provider 下，无需切换 provider。
2. 如果用户想直连某个厂商端点（不经过聚合）：需要在 `.env` 添加对应 API Key，并在 config.yaml `providers` 段定义。用 Python 脚本编辑 config.yaml（patch/write_file 工具会被拒绝，详见 `references/config-provider-editing.md`）。
3. 模型切换框只显示当前 provider 的模型 = 正常机制，不是 bug（详见 `references/dashboard-diagnostics.md`）。

## 常见错误

| 错误用法 | 问题 |
|----------|------|
| 只输入模型名不带 provider 前缀 | 当前 provider 下找不到该模型名（聚合 provider 下所有模型均可直接用名称切换） |
| 输入了未配置的 provider 名 | `/model` 只能切换到已配置的 provider；UI 下拉中的 provider 如果没有对应 API Key 会失败 |
| 直接在 config.yaml 修改但不重启会话 | 会话中不会生效，需要 `/reset` 或新会话 |

## 注意事项

1. **Prompt Cache 重置**：更换模型时，缓存键包含模型名，下一次对话会重新读取整个上下文，按全价计费而非缓存价。长会话切换前请知晓。
2. **只能切换已配置的 Provider**：添加新 Provider 需要退出会话，在终端运行 `hermes model` 或编辑 `config.yaml`（用 Python 脚本，不能用 patch/write_file）。
3. **会话内切换不持久**：不加 `--global` 标志，重启后恢复默认配置。
4. **模型名中的斜杠**：硅基流动的模型名包含 `/`（如 `deepseek-ai/DeepSeek-V4-Flash`），在 `/model siliconflow:deepseek-ai/DeepSeek-V4-Flash` 中，冒号后的部分整体作为模型名传入，斜杠不会造成解析冲突。
5. **聚合 provider 的优势**：如 opencode-go，一个 API Key 可访问多个不同厂商的模型，无需分别为每个厂商配置 API Key。用户"无法切换其他厂商模型"的困惑，往往是因为不知道这些厂商的模型都在同一个 provider 名下。

## 常见工作流

### 同 provider 内切换到推理模型做分析
```
/model kimi-k2.7-code
```
做完分析后切回：
```
/model glm-5.2
```

### 查看当前配置的 Provider 列表
在 config.yaml 中查看 `providers` 段，或在终端运行 `hermes config get model`。
