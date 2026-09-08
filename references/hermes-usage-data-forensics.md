---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Hermes token 用量/会话数据取证

用户问"某天的 token 使用数据没了 / 用量图表缺了一天"时的取证地图。

## 两个数据存储位置（必须分清）

| 库 | 表 | 内容 | 时间戳单位 |
|---|---|---|---|
| `$HERMES_HOME/desktop-ui.sqlite` | `turn_stats` | **每轮 token 明细**：tokens_input/output/total、cache_read/write、ttft_ms、duration_ms、model、provider、session_id | **13 位毫秒**（如 1786170141011） |
| `$HERMES_HOME/desktop-ui.sqlite` | `ui_kv` | UI 状态：workspacePath、sessionTitleOverrides、`hermes:model-usage-log`（模型选择器"最近使用"数据源）、gateway-session-map | 毫秒 |
| `$HERMES_HOME/state.db` | `sessions` / `messages` / `session_model_usage` | 会话主库（canonical store）：会话元数据、消息、模型用量聚合（api_call_count、input/output/cache/reasoning tokens、estimated/actual cost） | **浮点秒**（如 1786263405.09） |
| `$HERMES_HOME/sessions/` | `request_dump_<session>_<ts>.json` | 原始请求转储（每轮一个文件），文件名时间戳 = 本地时间 | 文件名本地时间 |

**时间戳单位陷阱（最容易踩）**：turn_stats 是毫秒、session_model_usage 是秒。混用会得出荒谬的日期分组（如 2026-08-08 变成 1786170141）。聚合前先用已知锚点校准（request_dump 文件名的本地时间就是锚点），turn_stats 按天聚合用：
```sql
SELECT date(started_at/1000, 'unixepoch', '+8 hours') d, COUNT(*), SUM(tokens_total)
FROM turn_stats GROUP BY d ORDER BY d;
```

## 会话 ID 格式

`YYYYMMDD_HHMMSS_<hash>`——前缀即本地起始时间（如 `20260810_210725_b21f31` = 8/10 21:07 开始）。按日期过滤会话 = 按前缀过滤。

## reset 备份盲区（根因所在）

`reset-backup-YYYYMMDD-HHMMSS/` 目录（如 `reset-backup-<timestamp>/`）**只备份 4 样**：
- `auth.json`、`config.yaml`、`desktop-ui.sqlite`、`provider_models_cache.json`

**没有 state.db！** reset 会重建 state.db → **旧会话元数据（sessions/messages/session_model_usage）从主库消失**，但 desktop-ui.sqlite 被备份且继续累计，turn_stats 原始数据完好。

**症状签名**：UI 用量图表/会话列表（读 state.db）某天消失，但 turn_stats 里该天数据完整存在（对比 reset-backup 里的 desktop-ui.sqlite 可证明数据从未丢失）。"数据没了"通常是"主库会话元数据没了"，不是"token 数据没了"。

## 取证流程

1. 定位 reset 时间点：`ls $HERMES_HOME | grep reset-backup` → 目录名即时间戳
2. 探查两库表结构/行数（sqlite3 是 Python 内置，无需装包；**写 .py 文件跑 `uv run --no-project python`，禁止 heredoc**）：
   - `desktop-ui.sqlite`：`PRAGMA table_info(turn_stats)`；当前行数 vs reset-backup 里的行数（数据幸存铁证：当前行数 = 备份行数 + 新增）
   - `state.db`：`SELECT id, source, started_at, ended_at FROM sessions` → 对照缺失日期前缀
3. turn_stats 按天聚合（上式）→ 确认目标日数据完好 + 总量
4. 交叉验证：turn_stats 的 session_id 前缀 vs state.db sessions 表 → 定位"在 turn_stats 存在但不在 state.db"的会话
5. 汇报：数据在哪、丢的是什么（通常是 state.db 的会话元数据）、可选恢复方案（只出报表 from turn_stats / 补回 state.db 需谨慎评估关联字段 / 接受现状）

## 用量面板显示机制（dashboard AnalyticsPage）

用户报"某天 token 数据没了"时，先分辨两种完全不同的现象：**面板整块隐藏**（配置缺失）vs **单日缺失**（state.db 会话丢失）。

- token/每日用量图表是**本地调试估算**（页面文案 "local debug estimate"，非 provider 计费数据），**默认隐藏**：前端代码 `f(t.show_token_analytics===!0)` —— 只有 config.yaml 设了 `dashboard.show_token_analytics: true` 才渲染，否则整块显示 "Token analytics hidden" + 提示文案。
- 后端端点：`/api/analytics/usage?days=N`、`/api/analytics/models?days=N`（前端 `getAnalytics`/`getModelsAnalytics` 调用；时间范围 7d/30d/90d）。**这两个端点需要 dashboard 的内部会话认证**（桌面应用自动处理；认证机制属厂商内部实现，本文不公开），`/api/health` 的 `auth_required:false` 不代表业务端点免认证。
- 估算只统计"成功的主 agent 响应且带可用 usage"的轮次；权威计费数字看 provider dashboard（OpenRouter/Anthropic 等）。
- **估算数据源 = `state.db` 的 `sessions` 表本身**（从 PYZ 提取 web_server.pyc 的 co_consts 拿到确切 SQL）：
  - daily：`SELECT date(started_at,'unixepoch') as day, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens), SUM(cache_write_tokens), SUM(reasoning_tokens), COUNT(*) as sessions, SUM(api_call_count) FROM sessions WHERE started_at > ? AND started_at <= ? GROUP BY day ORDER BY day`
  - by_model：同表 `GROUP BY model, billing_provider`；top_sessions：同表 `ORDER BY input+output DESC`；totals：同表 SUM
  - **日期按 UTC 分组**（`date(started_at,'unixepoch')` 无 `+8 hours`）——北京时间 00:00-08:00 的会话归前一天。回填/解释面板数字时务必注意
  - sessions 表完整字段（PRAGMA 有 50+ 列，远超肉眼初看）：`output_tokens/cache_read_tokens/cache_write_tokens/reasoning_tokens/billing_provider/title/api_call_count/estimated_cost_usd/...`；**`title` 列有 UNIQUE 约束**（回填插入时重复标题会 IntegrityError，冲突则置 NULL）
  - → **即使开了开关，reset 后丢失的旧日期仍会是空的**（turn_stats 数据在但 UI 不读它）
- **minified 前端侦查技巧**（分析桌面 app/dashboard 内部机制的高效路径）：`<HERMES_CN_DESKTOP>\dashboard\web_dist\assets\*.js`（及 `_internal\hermes_cli\web_dist\assets\`）是 rolldown 压缩产物，但字符串常量明文可 grep —— `grep -o '.\{0,150\}show_token_analytics.\{0,150\}' AnalyticsPage-*.js` 即可还原配置键、API 端点（如 `usage?days=${e}`）、UI 分支逻辑。0.19.0-cn.7 的 web_dist 也有同款代码（该开关非 0.20 新增）。

## 回填修复：让丢失日期重新出现在面板

目标：把 reset 后从 state.db 消失的某天会话补回 `sessions` 表，使面板 daily 重新显示该日。**数字是估算**（原计费口径已随 reset 丢失），量级可靠、绝对值偏大 2-3 倍，务必向用户说明。

### 数据源：turn_stats.metadata_json 的 usage 字段

`desktop-ui.sqlite` 的 `turn_stats.metadata_json` 是 JSON：`{"model":..., "usage":{"apiCalls":N,"tokensPrompt":P,"tokensCompletion":C,"tokensInput":I,"tokensTotal":T,...}}`。**语义（实测确认）**：
- **每轮（turn）级别的统计，不是会话累计**——apiCalls 每轮重置（同会话两轮 124 → 9 正常）
- `tokensPrompt` 含缓存命中的历史上下文（≈ input+cache），**不能**直接当 sessions.input_tokens（会大 20 倍）
- `tokensInput` ≈ 该轮新增输入；`tokensCompletion` = 该轮输出
- 会话聚合公式（估算口径）：`input_tokens=SUM(tokensInput)`、`output_tokens=SUM(tokensCompletion)`、`cache_read_tokens=SUM(tokensPrompt)-SUM(tokensInput)`、`api_call_count=SUM(apiCalls)`（数学自洽：input+cache=SUM(prompt)）

### 回填步骤

1. **备份**：`cp state.db state.db.bak-before-backfill-<ts>`（35MB，WAL 模式下 cp 主文件即可，写入前做）
2. 从 turn_stats 选目标日区间（**毫秒**）内的会话，剔除已在 sessions 表的（注意：**runtime 运行中会增删 sessions 行**，如 weixin 会话可能被清理——existing 集合要现查，别用旧结果）
3. 每个会话取第一条 turn 的 `started_at/1000` 作 `started_at`（浮点秒）、最后一条作 `ended_at`、非零轮里最后的 model 作 `model`
4. **跨天会话归哪天**：sessions.started_at 决定归组日。跨天会话若想归目标日（而非开始日），把 started_at 设为目标日内第一条 turn 的时间
5. INSERT：`(id, source, started_at, ended_at, model, title, message_count, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens, api_call_count, estimated_cost_usd, actual_cost_usd)`；`source` 按渠道填 desktop/weixin；reasoning/cost 无数据填 0
6. **陷阱**：`title` UNIQUE 冲突（如两会话都叫"工作环境调试"）→ 冲突则置 NULL；全零会话（calls=0/in=0/out=0）跳过；title 可从 `ui_kv` 键 `hermes-cn-ui.sessionTitleOverrides` 的 JSON 查
7. **验证**：在桌面应用内打开数据分析页（或经官方认可的方式调用 `GET /api/analytics/usage?days=90`）→ daily 数组出现目标日即成功（用户刷新桌面数据分析页可见）

### 面板数字解读

- 面板按 UTC 分组：北京 00:00-08:00 回填的数据会显示在前一天的 UTC 日期上——解释给用户
- by_model 的 provider 来自 `billing_provider` 列，回填时未知可留 NULL（显示空串，daily 不受影响）
- 回填日的 input 可能远大于相邻日（估算口径 + 当天可能是峰值日），主动说明估算性质

### 数字太夸张？用已知会话推导校准因子

回填的估算值比真实计费口径系统性偏大 **2-3 倍**（turn_stats 含重试/中断重发请求，UI 统计的 apiCalls 是真实成功调用的 ~3 倍）。用户质疑"数字太夸张"时，用**对账法**校准：

1. 找 2 个**既有准确值**的会话（sessions 表行内 token 字段 = 真实计费口径，来自 reset 后 runtime 正常维护的会话）
2. 对每个会话算 turn_stats 聚合（SUM apiCalls/tokensInput/(tokensPrompt-tokensInput)/tokensCompletion）
3. 因子 = sessions 行真实值 ÷ turn 聚合值（各指标因子不同，**逐项乘**，不要用单一因子）
4. 对回填的每行 `UPDATE sessions SET input_tokens=ROUND(input*f_in), output_tokens=..., cache_read_tokens=..., api_call_count=... WHERE id=?`
5. 验证：调 `/api/analytics/usage?days=90`，目标日量级应回到与相邻日自洽（目标日 vs 相邻日的 input/cache/calls 比值 ≈ turn_stats 总量比值）

校正后仍标注估算（误差 ±30%），但不再"离谱"。

### 回填会话污染列表？归档隐藏

副作用：回填的会话出现在桌面客户端**会话列表**（列表 API 读同一 sessions 表），点进去还是空的（无 messages）。

解法——**归档**（数据保留、列表隐藏）：
- 后端列表 API 过滤 `archived`，而 analytics SQL **不过滤** archived → 标归档两全其美
- `UPDATE state.db.sessions SET archived=1 WHERE id IN (...)`
- 同步 `desktop-ui.sqlite` 的 `session_ui_state`：`INSERT OR REPLACE INTO session_ui_state (session_id, title_override, archived, pinned, tags_json, workspace_path, updated_at) VALUES (?, NULL, 1, 0, NULL, NULL, <ms>)`
- 验证：`/api/sessions` 不再返回这些会话（或 archived=True），`/api/analytics/usage` 目标日仍在；UI 有缓存时重启客户端

### 归档会话的查询与恢复

- 列表 API 支持 `archived` 三态参数：`GET /api/sessions?archived=exclude|only|include`（默认 exclude）——`only` 只列归档会话、`include` 全量
- **桌面客户端与 dashboard 都没有"查看/恢复归档会话"的 UI 入口**（dashboard SessionsPage 只有归档计数和"清理 N 天前的旧归档"功能），先解释数据没删（state.db archived=1），再说明 UI 缺口，恢复 = `UPDATE sessions SET archived=0 WHERE id=...`（顺带清 desktop-ui.sqlite 的 session_ui_state 对应行 archived=0）；或提议写 desktop 插件做\"全部会话\"面板（搜索+归档开关）
- "左侧最近对话太多看不到旧的"：先试鼠标滚轮（Win11 滚动条自动隐藏，列表通常可滚），再提 Ctrl+K 命令面板搜索会话，最后才考虑批量归档旧会话
- **归档/恢复的正确 REST 端点**：`PATCH /api/sessions/{id}` body `{"archived": true|false}` → `{"ok":true,"archived":...}`。**⚠️ `DELETE /api/sessions/{id}` 是真删（物理删除 sessions 行，返回 `{"ok":true}` 后 GET 即 `Session not found`）**——探测未知端点前先想清方法语义，探测用无害对象或 GET/PATCH 先探；误删恢复 = 从 turn_stats 聚合值或删除前已知值 `INSERT INTO sessions` 回填（保持 archived 状态，无 messages 的会话一行即恢复）。POST/DELETE 都不是归档操作（返回 Method Not Allowed 不代表端点不存在，只代表方法不对）。`?archived=true` 会报 `archived must be one of: exclude, only, include`——正确传枚举值
- **桌面插件实现"全部会话"面板的 API 组合**（已用 all-sessions 插件验证）：列表 `GET /api/sessions?archived=include`、归档/恢复 `PATCH /api/sessions/{id}`、跳转会话 `host.request('session.info', {session_id})`（RPC 方法名为 `session.info`，无 `session.list`——列表走 REST）。插件页面与 dashboard 同源，fetch 同源 API 时会话认证自动携带，无需手动处理。插件放 `$HERMES_HOME/desktop-plugins/<id>/plugin.js`，⌘K → Reload desktop plugins 生效；RPC 方法名风格是 `model.options`/`config.set`/`session.info`/`session.create`（点分式，web_dist 可 grep 到）

## 其他要点

- 微信/飞书等渠道会话的 turn_stats 也在同一表（session_id 前缀同格式，provider/model 列可查）
- "测试多模型"的日子 turn_stats 里 model 列能看出模型切换痕迹（qwen3.7-plus、glm-5.2 等），可用于复盘
- turn_stats 有大量 tokens_total=0 的行（tool 调用、空响应轮次），按天聚合时 COUNT 含它们、SUM 不受影响
