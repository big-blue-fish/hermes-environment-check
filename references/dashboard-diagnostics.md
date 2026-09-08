---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
related:
- model-picker-pipeline.md
---

# Hermes CN Desktop Dashboard 诊断

> 排查桌面应用健康检查提示（"模型凭证未配置"）、模型切换框只显示少数模型等问题。
> 验证于 0.19.0-cn.7。

## Dashboard 服务架构

- 桌面应用 = WebView2 壳（`hermes-agent-cn-desktop.exe`）+ 网页 UI（`hermes_cli/web_dist`，打包压缩 JS）
- Dashboard server 是独立进程：`hermes dashboard --host 127.0.0.1 --port 9120`（**9120 端口**）
- 进程命令：`Get-CimInstance Win32_Process -Filter "ProcessId=<pid>"`（`Get-NetTCPConnection -LocalPort 9120 -State Listen` 拿 pid）

## API 认证

- `/api/status` **免认证**：版本、gateway 状态、`auth_required`、`auth_providers`、`nous_session_valid`、`profiles` 等
- `/api/health`、`/api/diagnostics`、`/api/models` 等**需要认证**（June 2026 加固后 loopback 也要求 token；`--insecure` 已废弃为 NO-OP）
- 前端 JS（`_internal\hermes_cli\web_dist\assets\index-*.js`）是压缩产物，硬搜端点效率低——优先用免认证端点或直接问用户界面显示内容

## 模型切换框 / 模型列表数据源

> **重要**：切换框模型列表的真实数据源是 dashboard 的
> `GET /api/model/options`（需认证），它按 `explicit_only` 过滤出"已显式配置凭证"的
> provider，模型来自 **live 的 `provider_models_cache.json`**（1h TTL、凭证指纹），
> `models_dev_snapshot.json` 只是离线兜底。
> 完整管道与诊断步骤：`references/model-picker-pipeline.md`。

- 模型列表 = **当前激活 provider 的模型**，来自 `_internal\agent\models_dev_snapshot.json`（models.dev 离线快照，约 3.3MB）
- 结构：`{ "<provider>": { "models": { "<model-id>": {cost, family, ...} } } }` —— **`models` 是 dict 不是 list**（python 脚本解析时 `[:25]` 切片会报 `TypeError: unhashable type: 'slice'`）
- 快照中各 provider 的模型数随版本变化，勿用具体数字做诊断；当前清单以 `models_dev_snapshot.json` 为准。
- **"切换框只有少数模型" = 正常机制**：切换框显示当前 provider 的模型。想看到更多 → 换 provider（`hermes model` 或 `/model provider:model`）。UI 可能只展示前几个推荐项，需滚动/搜索。**若整个 provider 都不出现 → `.env` 缺该 provider 的 API key（explicit_only 过滤）**，不是 bug。

## auth.json（OAuth 凭证存储）

- 路径：`<HERMES_HOME>\auth.json`（旁边可能有 `auth.json.corrupt` 备份 = 曾有损坏记录）
- 结构：`version / providers / credential_pool / updated_at / active_provider`
  - `providers.<name>`：OAuth 登录态（如 `minimax-oauth`：provider、access_token、refresh_token、expires_at、portal_base_url 等）
  - `credential_pool.<name>`：API-key 类凭证池（数组）
  - `active_provider`：最近激活的 OAuth provider
- auth.json 的 `active_provider` 可能指向一个已不再使用的 provider（如曾用 OAuth 登录过的厂商）——dashboard "模型凭证未配置"提示可能与 OAuth token 过期/active_provider 与 config `model.provider`（opencode-go）不一致有关，但**主模型调用不受影响**（config.yaml `model.api_key` 存在 + doctor 报 "OpenCode Go (key configured)"）

## 排查建议流程

1. 先跑 `hermes doctor` + `hermes config get model` 确认主模型凭证实际状态（config `model.api_key` 存在 = 主模型可用）
2. `curl http://127.0.0.1:9120/api/status` 看免认证字段（auth_providers、profiles）
3. 模型切换框问题 → 解释 provider 模型列表机制（见上），对比快照模型数
4. 凭证提示 → 检查 auth.json 结构与 config `model.provider` 是否一致；主功能正常则提示可忽略
