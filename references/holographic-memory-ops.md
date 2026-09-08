---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Holographic 记忆库运维（memory_store.db 诊断与实体网络建设）

触发场景：用户问"记忆功能怎样/能否更可靠更像人类"、`memory.provider: holographic` 时的诊断、实体关联缺失排查、事实库手工补全。

**用户核心偏好**：记忆要**持久可靠，不要自动遗忘/清理机制**，事实长期保留、越久越可信。整理记忆时只合并/压缩，**不删除有效信息**。写 fact 时带 entity + category + tags 保持网络完整。

## 库位置与 schema

`$HERMES_HOME/memory_store.db`（SQLite），表：

| 表 | 用途 | 关键列 |
|---|---|---|
| `facts` | 事实本体 | `fact_id, content, category, tags, trust_score(默认0.5), retrieval_count, helpful_count, created_at, updated_at, hrr_vector` |
| `entities` | 实体 | `entity_id, name(UNIQUE), entity_type, aliases` |
| `fact_entities` | 事实↔实体多对多 | `(fact_id, entity_id)` 复合主键 |
| `facts_fts` | FTS5 全文索引 | 文本检索 |
| `memory_banks` | 记忆分区 | 3 行（默认分区） |

`hrr_vector` = 1024 维 HRR（Holographic Reduced Representations）相位向量 BLOB（`plugins/memory/holographic/holographic.py`，纯 numpy 零依赖）：`encode_atom/bind/unbind/bundle/similarity`，`snr_estimate(dim, n_items)` 估算叠加容量。语义相似检索 = 向量点积，快；文本检索走 FTS5。

## 诊断模式（快速健康检查）

```sql
SELECT COUNT(*) FROM facts;                              -- 事实总数
SELECT COUNT(*) FROM entities;                           -- 实体数（远小于 facts 数 = 实体网络没建）
SELECT COUNT(*) FROM fact_entities;                      -- 关联数（≈facts 数才健康）
SELECT fact_id, content, trust_score, retrieval_count FROM facts ORDER BY trust_score LIMIT 5;  -- 信任评分全是 0.5/0 = 反馈没喂
```

auto_extract 抽事实时**不带 entity**，实体网络需手工补。信任评分系统（fact_feedback 喂 helpful_count/trust_score）若从未使用则全是默认值，属正常但未激活。

## 实体网络补全 SQL 模式（已验证）

```python
import sqlite3
db = sqlite3.connect(r'<HERMES_HOME>\memory_store.db')
cur = db.cursor()
entities = {'用户': ('person', [9,10,11,...]), '搜索路由': ('config', [1,2]), ...}
for name, (etype, fids) in entities.items():
    cur.execute('INSERT OR IGNORE INTO entities(name, entity_type) VALUES (?,?)', (name, etype))
    eid = cur.execute('SELECT entity_id FROM entities WHERE name=?', (name,)).fetchone()[0]
    for fid in fids:
        cur.execute('INSERT OR IGNORE INTO fact_entities(fact_id, entity_id) VALUES (?,?)', (fid, eid))
db.commit()
```

实体粒度建议：`用户(person)` / 工具类（ddg-search、tavily、Kimi、<your-vision-script>.py）/ 配置类（搜索路由、视觉辅助、MCP）/ `Hermes(software)` / `工作区(project)`。脚本要写 `E:/...` 路径文件再 `uv run --no-project python` 跑（MSYS /tmp 给 Windows Python 会 FileNotFoundError）。

## 配置位置（易错）

- `memory.provider: holographic` 在 config.yaml `memory:` 段
- **`auto_extract` 在 `agent.hermes-memory-store:` 段**（不在 memory 段！）：`auto_extract: true` = 会话结束自动抽事实到 memory_store.db。诊断 auto_extract 是否开启看这里，别在 memory 段找
- 容量：`memory.memory_char_limit`（MEMORY.md 上限）/ `memory.user_char_limit`（USER.md 上限）。**服务端硬上限 8000**（config.yaml 设更高值会被 HTTP 400 拒绝；修复=改回 8000，用 `uv run --no-project --with pyyaml python` 脚本做行替换 + yaml.safe_load 验证顶层键）
- 插件实现：runtime `_internal/plugins/memory/holographic/`（纯 numpy，无配置读取——插件本身无参数）

## memory 工具批量整理档案的模式

USER.md/MEMORY.md 接近上限时的压缩手法（只压缩不删）：
1. **先 `read_file` 实际文件**（`$HERMES_HOME/memories/MEMORY.md`、`USER.md`），别依赖系统提示注入的 MEMORY 快照——快照是精简版（注入条数可能少于磁盘条数），按快照规划会漏条目。条目以 `§` 行分隔，read_file 对 MEMORY.md 实测正常（USER.md 才报 Binary）
2. memory 工具 **operations 批量**：旧条目 `remove`（old_text=段落独特开头子串）+ 新条目 `add`，一次调用原子完成，有 char 上限检查（压缩后验证字符数与占比下降，无信息丢失）
3. 压缩对象：同主题条目合并（终端/Python 执行、config 编辑、runtime 结构、视觉 OCR、cron、记忆配置等分组）、删重复表述（同一条信息分散多条时只留一处）、删过期数字（实体计数、job id 等会变的值，需要时现查）、细节指针化到技能 references；**保留全部有效信息**
4. 压缩完给用户看合并映射表（表格形式），并明确"未删除任何有效信息"
5. 用户偏好变更（如"记忆持久可靠"）立即用 `add` 写入，别等 daily-review

## 相关工具

- `fact_store`（search/probe/reason/contradict）与 `fact_feedback`（训练信任分）——fact_store 需新会话加载
- 会话内直接查库比等 auto_extract/daily-review 快，诊断用 SQL 直查

## 已知环境事实

- runtime 内置 SQLite 3.50.4 有 WAL-reset 损坏漏洞警告（访问 db 时弹），`hermes update` 升 3.51.3+ 可修（CN Desktop 禁止 hermes update！需重装或等新版 runtime）
