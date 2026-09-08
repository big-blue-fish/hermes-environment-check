---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 桌面端模型列表（/api/model/options）数据管道 — 验证于 0.19.0-cn.7

> 用户报"对话框下方模型列表里找不到想要的模型"时的完整排查链路。
> 结论先行：**列表不是直接读 `models_dev_snapshot.json`**，而是 dashboard 的
> `GET /api/model/options` 现场组装：先按 `explicit_only` 过滤出"已显式配置凭证"的
> provider，再对每个 provider 取 `provider_models_cache.json`（live /v1/models 发现，
> 1h TTL）→ 缓存失败才回退 curated 静态列表 + snapshot 合并。
> **"找不到模型"最常见的真因：该模型所属 provider 在 `.env` 里没有 API key，被
> explicit_only 过滤掉了**（模型本身存在于远端，只是列表没显示那个 provider）。

## 数据管道（从前到后）

1. **前端** `apps/desktop/src/lib/model-options.ts`：`requestModelOptions({ explicitOnly = true })`
   —— 聊天输入框的模型选择器默认 `explicitOnly=true`（只列显式配置的 provider）。
2. **REST 端点** `hermes_cli/web_server.py` `GET /api/model/options`（**需要认证，401**；
   只有 `/api/status` 免认证）→ 调 `build_models_payload(...)`。
3. **组装** `hermes_cli/inventory.py` `build_models_payload()`：
   - `explicit_only=True` → `_filter_explicit_provider_rows()`：保留 (a) 当前 provider、
     (b) `is_user_defined` 行、(c) `is_provider_explicitly_configured(slug)` 为真的 provider
     （env key 或 auth store/credential_pool 有凭证）；MoA 虚拟行仅在 config 有启用 preset 时显示。
   - `picker_hints/canonical_order/pricing/capabilities` 等只是元数据装饰，不影响模型集合。
4. **provider 行构建** `hermes_cli/model_switch.py` `list_authenticated_providers()`：
   - opencode-go 走 `HERMES_OVERLAYS` 分支 → `cached_provider_model_ids(slug)`；
     若空 → `curated.get(slug)` + `_MODELS_DEV_PREFERRED`（含 opencode-go）时
     `_merge_with_models_dev()` 合并 snapshot。
   - `cached_provider_model_ids()`（`hermes_cli/models.py`）读 **`<HERMES_HOME>/provider_models_cache.json`**：
     keyed by (provider, 凭证指纹 `fp`)，1h TTL；命中直接返回，miss 则 live 拉
     `GET <base_url>/models` 并写回。凭证变了（换 key）指纹不匹配 → 重新拉取。
   - `desktop.models.provider_order`（config.yaml）**只控制 provider 显示顺序**，不裁剪。
5. **config 显式 models 块是"扩展"不是"限制"**：`providers.<name>.models`（如
   opencode-go 下声明的若干模型）经 `_declared_model_ids()` 解析后
 `model_ids = list(dict.fromkeys([*configured_models, *model_ids]))` —— **前置合并**，
 不会把 live 缓存里的其他模型裁掉。

 ### 特例：自定义 provider 的 `/models` 端点不是 JSON → 只显示手写 `models:` 块

 - 症状：模型列表"正常返回但内容少"，opencode 相关行只显示 config `providers.<name>.models`
   里手动写的模型（如 `gpt-5.6-luna`），而 built-in 同名 provider（`opencode-go`）却能列出
   完整清单。
 - 根因：自定义 provider（config `providers:` 块，如 `custom:opencode-ai`）指向的端点对
 `GET <base_url>/models` **返回 HTML 网页（404）而非模型 JSON**（如
   `https://opencode.ai/zen/go/v1//models` 返回 opencode 官网 HTML）。Hermes 无法自动发现模型
   → 只能回退 config 里手写的 `models:` 块。这与 built-in provider 走 live 拉取/缓存
   （`provider_models_cache.json`）行为不同。
 - 判定：先 `curl <base_url>/models` 看返回的是 `{data:[...]}` JSON 还是 HTML/404。JSON 才支持
 自动发现；HTML/404 的自定义 provider 只能靠手写 models 块扩展。
 - 修复选项：
 - 若该端点本就不支持自动发现 → 用同端点但 built-in 的 provider 行（如 `opencode-go`），
   其全部模型经 `provider_models_cache.json` 自动出现在选择器里，**无需改 config**；
 - 或手补 `providers.<name>.models`（逐个列，麻烦）；
 - `desktop.models.provider_order` 同时引用 built-in（`opencode-go`）和自定义
  （`custom:opencode-ai`）两个长得像的条目是常见混淆源 —— 两个 base_url 相同、显示名都带
  "opencode"，模型数却一多一少，先分清用户看的是哪个行。

 ## 诊断步骤（用户报"找不到想要的模型"）

1. **问清模型名**（最省事，通常一句就定位）。
2. 列出 `.env` 中实际存在的 key 名（只看名字，不看值；`[regex]::Matches` 只取键名，不泄露值）→
   确定哪些 provider 有凭证；没有对应 `*_API_KEY` 的 provider（如缺 `DEEPSEEK_API_KEY` →
   deepseek）整行被 explicit_only 过滤。
3. 读 `provider_models_cache.json`（live 真相）：live 缓存可能比 snapshot 多（含 snapshot
   没有的模型）。以缓存为准，snapshot 是离线兜底。
4. 看用户实际用过的模型：`desktop-ui.sqlite` 表 `turn_stats`：
   ```sql
   SELECT model, provider, COUNT(*), MAX(created_at) FROM turn_stats GROUP BY model, provider
   ```
   若用过的模型属于某个 provider 的官方命名空间而该 provider 当前没 key
   → 这就是它在列表里消失的根因。
5. 修复路径：
   - 模型在已配 provider 的 live 缓存里 → UI 应可见，引导滚动/搜索；
   - 模型在其他 provider → 补 `.env` API key（+ 可选 config `providers.<name>` 定义，用
     Python 脚本编辑，见 `config-provider-editing.md`）；或经聚合 provider 用同 ID 直接 `/model <id>`；
   - 缓存过期/凭证指纹变 → `refresh=true` 参数（UI 的 "Refresh Models"）或删
     `provider_models_cache.json` 对应条目。
