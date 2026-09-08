---
scope: Hermes CN Desktop 0.20.0-cn.5
status: workaround
last_verified: '2026-08-14'
---

# Hermes CN Desktop 版本差异调查（"新版提升了什么"）

触发场景：用户问"0.20 比上个版本提升了什么 / 新版改了什么 / 升级值不值"。
**原则：给实据，不凭印象编**——每个结论都要有 manifest、commit 或文件 diff 支撑。

## 权威数据源（按优先级）

### 1. manifest.json —— 版本对比锚点（必读）
`<HERMES_CN_DESKTOP>\data\versions\<ver>\manifest.json`，关键字段：
- `kernelVersion`（0.19.0 → 0.20.0）、`runtimeFlavor`（cn）、`runtimeRevision`
- **`sourceRepo` + `sourceCommit`**：构建来源的 GitHub 仓库和源码提交哈希——这是两个版本做代码级对比的权威锚点
- `createdAt`：构建时间

### 2. GitHub compare API —— 提交与文件变更清单（核心手段）
```bash
curl -sS "https://api.github.com/repos/<sourceRepo>/compare/<old_sourceCommit>...<new_sourceCommit>" -o cmp.json
# 解析：status/ahead_by/commits[].commit.message/files[]（status=added|modified|removed, additions, deletions）
```
- 用 `uv run --no-project python` 解析 JSON（脚本写 `E:/...` 路径文件再跑，避免 heredoc）
- `commits[]` 看提交标题即可；`files[]` 按 `additions+deletions` 排序找大改动，按 `status=='added'` 找新模块
- **大版本合并陷阱**：大版本合并时 compare 视图可能只显示少量提交，需查 `pulls/<n>` API 的 body 才知道真实规模（如 "ahead by N commits"；0.19→0.20 即隔着 dev-020 分支大合并）。
- GitHub releases API 的 body 在 CN 版仓库**常为空**（不发 release notes），别指望它

### 3. 依赖快照 diff —— 快速发现新增能力（1 分钟出结论）
```bash
ls <ver>/_internal | grep dist-info | sort > d.txt   # 两个版本各一份
comm -23 d20.txt d19.txt    # 新增依赖
comm -13 d20.txt d19.txt    # 移除依赖
```
0.19→0.20 新增：`mem0ai-2.0.10` + `qdrant_client` + `supermemory`（= 记忆系统向量化）、`numpy`、`mcp 1.26→1.28`、`starlette 1.0→1.3`、`cryptography 46→48`。**依赖名直接暴露能力方向**，是最高信息密度的一步。

### 4. 新增模块 docstring —— 最快了解功能语义
`versions/_leftovers-<date>/` 是完整源码树（`pyproject.toml` 的 `version =` 确认对应版本）。新增的 `.py` 用 `head -12 <file>` 看 docstring：
- `agent/monitoring/`：OTLP 可观测性（emitter 事件总线、gateway_health、cron_health、redaction 脱敏、install_id 匿名标识）
- `agent/outbound_webhooks.py`：config `hooks.outbound:` 列表，生命周期事件推外部 HTTP 端点（入站 webhook 的反向镜像）
- `agent/backend_identity.py`：统一后端身份/故障跳过判断（修 6 处重复实现 bug）
- `agent/battery.py`：CLI/TUI 状态栏电池电量

### 5. 平台 / 模型提供商目录 diff —— 发现新连接能力
```bash
ls <ver>/_internal/plugins/platforms          # 0.19: 20 个 → 0.20: 22 个
ls <ver>/_internal/plugins/model-providers    # 0.20 新增 ai-gateway
comm -23 <(ls 0.20.../plugins/platforms) <(ls 0.19.../plugins/platforms)
```
平台 adapter 用 `head -15 adapter.py` 看 docstring 即知用途。0.19→0.20 新增：
- **A2A**（`plugins/platforms/a2a/`）：Google Agent2Agent v1.0 协议——暴露 Hermes 为可被其他智能体发现/调用的 agent（Agent Card `/.well-known/agent-card.json` + JSON-RPC message/send、tasks/* + SSE 流式 + HMAC 签名推送通知）
- **Buzz**（`plugins/platforms/buzz/`）：Block 开源、基于 Nostr 的人+agent 协作平台，经 buzz CLI 桥接

## PyInstaller onedir 结构知识（为什么这样查）
- 内核主包 `hermes_agent` 被 **mypyc 编译成单个 `.pyd`**（`_internal/ada92cb5d...__mypyc.cp314-win_amd64.pyd`），源码不可直接读
- 纯 Python 子模块平铺在 `_internal/` 下：`gateway/`、`hermes_cli/`、`tools/`、`plugins/`、`skills/`、`agent/`（后者只有 models_dev_snapshot.json 等配置文件）
- 依赖在 `_internal/*.dist-info/`（METADATA 含 Requires-Dist 全依赖清单）
- `base_library.zip` = Python 标准库

## Pitfalls
- **curl 写临时文件用工作区路径，别用 `/tmp`**：`curl -o /tmp/cmp.json` 可能报 exit_code=23（MSYS /tmp 写入问题），`cd <工作目录> && curl -o cmp.json` 成功。大 JSON（1MB+）落盘再解析，避免管道截断
- compare API 响应可能很大（1.4MB），`-w "HTTP:%{http_code}\n"` 确认 200 再解析

## 0.19.0-cn.7 → 0.20.0-cn.5 已知结论（可直接引用）
1. 记忆大升级：mem0 SDK 2.0.10 内置（0.19 缺 SDK）、新增 qdrant 向量库 + supermemory、numpy 2.5
2. 新增可观测性体系：agent/monitoring/（OTLP 导出、健康检查、事件总线）
3. 新增出站 webhook：hooks.outbound 推事件到外部端点
4. 架构重构：context_compressor (+3370)、conversation_compression (+2278)、auxiliary_client (+2119)、conversation_loop、moa_loop、credential_pool
5. 修复：**"覆盖升级后自定义模型配置失效"**（PR #149，升级丢配置的自愈）
6. 杂项：TUI 电池显示、delegation_context（子 agent 与 Kanban/cron 身份隔离）、MCP 库 1.28
7. 平台 20→22：新增 **A2A**（Agent2Agent v1.0，让 Hermes 成为可被其他智能体标准协议调用的节点）和 **Buzz**（Nostr 生态人+agent 协作）；model-providers 新增 **ai-gateway**（统一 API 网关）
8. 工具/技能：`tools/computer_use/browser_route.py`；内置技能脚本扩充（docx/pptx/xlsx/PDF office 校验器家族——表单填写/结构提取/redlining/soffice 转换、grounded-citations sources.py）
