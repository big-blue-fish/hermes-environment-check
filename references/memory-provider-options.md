---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Hermes 记忆系统诊断与增强（0.20.0-cn.5）

## 诊断入口（CLI 不在 PATH，直接调 runtime exe）

```
"<HERMES_CN_DESKTOP>\data\versions\0.20.0-cn.5\hermes-agent-cn-runtime-win32-x64.exe" memory status
```

`hermes memory` 子命令：`status` / `setup [provider]` / `off`（禁用外部 provider）/ `reset`（清空 MEMORY.md + USER.md，危险）。

`memory status` 输出结构：
- **Built-in (MEMORY.md / USER.md)**：Memory injection / User profile / Memory tool 三项 enabled ✓——文件式记忆，永远生效
- **Provider**：config.yaml `memory.provider` 值（默认 mem0）
- **Plugin**：installed ✓ + **Status: not available ✗ + Missing: 缺哪些 env**（MEM0_API_KEY、MEM0_HOST 等）

## 关键事实：mem0 provider 配置 ≠ 生效

若 `memory.provider: mem0` + `mem0.json`（mode: platform, user_id hermes-user, agent_id hermes, rerank false）已配好，但 `.env` 无 `MEM0_API_KEY`/`MEM0_HOST` → `memory status` 报 "Status: not available"，**实际只有内置文件记忆在工作**。0.19 时代的 "No module named 'mem0'" 错误在 0.20.0-cn.5 已不存在（mem0ai 已随 runtime 内置），**0.20 的失效模式是缺 API key**。判断依据是 `memory status`，不是系统提示横幅（"Mem0 Memory: Active" 可能是假的）。

## 7 个内置记忆插件（_internal\plugins\memory\）

| 插件 | 要求 | 说明 |
|---|---|---|
| **holographic** | **无（纯本地）** | SQLite 事实库 + FTS5 + HRR 向量检索 + 信任评分，零依赖零 key |
| mem0 | API key / local | platform（云，api.mem0.ai 国内网络大概率连不上）/ selfhosted（自跑 Docker server，设 host）/ oss（本地，需 openai 或 ollama 做 LLM+embedder、qdrant 或 pgvector 做向量库） |
| byterover / hindsight / honcho / openviking / retaindb | API key / local | 各有云服务或本地模式 |
| supermemory | 仅 API key | — |

只允许一个外部 provider 同时激活；内置记忆永远叠加生效。

## holographic（推荐的零依赖本地增强）

- README 摘要：Local SQLite fact store with FTS5 search, trust scoring, entity resolution, and HRR-based compositional retrieval. Requirements: None。
- 切换：`hermes config set memory.provider holographic`（或 `hermes memory setup` 选 holographic），新会话生效
- 配置在 config.yaml **`agent.hermes-memory-store`**（`grep -n hermes-memory-store config.yaml` 显示挂载在 `agent:` 段下、缩进 2 格、位于 `auto_compress_messages`/`warn_tokens` 之后——旧文档/CLI 警告里的 `plugins.hermes-memory-store` 路径是**错的**，按它找会找不到）：`db_path`（默认 $HERMES_HOME/memory_store.db）、**`auto_extract`（默认 false，true = 会话结束时自动抽取事实）**、`default_trust`（0.5）、`hrr_dim`（1024）
- 工具：`fact_store`（add/search/probe/related/reason/contradict/update/remove/list）、`fact_feedback`（评分训练信任度）

## mem0 模式速查（README 要点）

- mem0.json 键：`mode`（platform/oss）、`host`（selfhosted 时设）、`user_id`、`agent_id`、`rerank`
- OSS 模式示例：`{"mode":"oss","oss":{"llm":{"provider":"openai","config":{"model":"gpt-5-mini"}},"embedder":{"provider":"openai","config":{"model":"text-embedding-3-small"}},"vector_store":{"provider":"qdrant","config":{"path":"~/.hermes/mem0_qdrant"}}}}`
- 工具：mem0_search / mem0_add（原样存储，不抽取）/ mem0_update / mem0_delete
- Circuit breaker：连续 5 次失败熔断 2 分钟（"Mem0 temporarily unavailable"）
- OSS 模式 LLM 抽取用 `sync_turn`，仅 mem0_add 不会触发抽取

## config set 自定义键的"警告"是噪音（保存正确）

`hermes config set plugins.hermes-memory-store.auto_extract true` 会报：
`⚠ 'plugins.hermes-memory-store.auto_extract' is not a recognized config key — it was saved anyway, but Hermes may not read it. (Custom top-level keys are supported and bridged to the environment...)`
这是 CLI schema 不认识该键的**误导性警告**，实际保存正确。验证姿势：`grep -n "hermes-memory-store" config.yaml`——该键挂载在 **`agent:` 段下**（缩进 2 格，位于 `auto_compress_messages`/`warn_tokens` 之后），**不在 `plugins:` 段**；保存位置可能在文件尾部紧跟上一段之后，别因为"不在 plugins 段落里"误判。同理 `memory.provider` / `memory.memory_char_limit` 是 schema 认识的键，无此警告。另注意 `config set` 修改 config.yaml 不受 patch/write_file 守卫限制，是**唯一推荐的改配置入口**（守护只在 agent 文件工具层）。

## 内置记忆容量

- config.yaml `memory.memory_char_limit`（默认 8000）→ MEMORY.md 上限，可调大（如 16000）
- USER.md 上限约 1375（较小，用户画像接近满时注意整理）；`hermes memory reset` 可清空但慎用

## holographic 内部结构与诊断（memory_store.db）

- 存储：`$HERMES_HOME/memory_store.db`（SQLite）。表：`facts` / `entities` / `fact_entities` / `facts_fts`（FTS5 全文索引）/ `memory_banks`
- `facts` 列：fact_id / content / category / tags / trust_score(默认0.5) / retrieval_count / helpful_count / created_at / updated_at / **hrr_vector（1024 维 HRR 向量 BLOB，`HRR1` 魔数开头）**——每条事实同时有全文索引 + 语义向量，读取毫秒级
- 插件实现：`<runtime>\_internal\plugins\memory\holographic\holographic.py`（290 行纯 numpy，**无配置读取——确定性编码器**）。核心函数：encode_atom / bind / unbind / bundle / similarity / encode_text / encode_fact（内容绑 ROLE_CONTENT、实体绑 ROLE_ENTITY）/ snr_estimate（容量信噪比估计——事实过多时叠加编码退化、检索精度下降的预警，定期清理的依据）
- **实体网络诊断**：`SELECT COUNT(*) FROM entities` / `fact_entities`——事实多而实体/关联少 = auto_extract 只抽事实、没建实体关联，联想式记忆（probe/reason 跨实体推理）等于没启用。优化方向：写 fact 时显式带 entity/tags，把"记事本"变成"关系图谱"
- **信任评分诊断**：trust_score 全为默认 0.5、retrieval/helpful_count 全 0 = fact_feedback 从未喂过。可定期用 fact_feedback 打分 + 清理低信任/零检索事实（HRR 容量有限，这就是"遗忘机制"）
- **daily-review cron 验证**：`cron/jobs.json` 里 job 的 `last_run_at`/`last_status` 字段判断是否真跑过（任务创建当天 last_run_at=null = **从未运行**，需手动触发验证管道或等下一个调度点）；job 结构：id/name/prompt/schedule{kind,expr}/deliver/enabled/next_run_at

## 增强组合建议（本地、免费、自动）

1. `memory.provider: holographic` + `agent.hermes-memory-store.auto_extract: true`（自动记笔记）
2. 调大 `memory.memory_char_limit`（文件记忆扩容）
3. 定期整理 cron：每天/每周让 agent 用 session_search 回顾会话、把重要事实固化进 MEMORY.md（"睡前写日记"）；创建后务必查 `cron/jobs.json` 的 `last_run_at` 确认首次运行（见上"daily-review cron 验证"——新任务创建当天 last_run_at=null）
4. 实体/信任分优化：写 fact 时带 entity + tags；定期 fact_feedback 打分 + 清理低信任/零检索事实（HRR 容量管理）
