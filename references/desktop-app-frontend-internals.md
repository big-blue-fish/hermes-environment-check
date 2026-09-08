---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 桌面 app（Tauri）前端内部机制与"后端全正常但桌面端不显示"排查

适用场景：config.yaml / dashboard REST API / WebSocket RPC / 远程 catalog / sqlite / .env 全部验证正常，
但桌面 app（hermes-agent-cn-desktop.exe）聊天界面的模型列表仍缺少某厂商。此时问题必然在**桌面 app
自己的前端层**——它与 dashboard 网页是**两套不同的前端**，排查思路完全不同。

## 1. 架构：两套前端并存（0.19.0-cn.7）

| 界面 | 加载方式 | 前端 JS | 数据源 |
|---|---|---|---|
| dashboard 网页（浏览器开 127.0.0.1:9120） | HTTP 静态资源 | `web_dist/assets/index-<hash>.js`（`_internal\hermes_cli\web_dist` 与 `<HERMES_CN_DESKTOP>\dashboard\web_dist` 同文件） | REST `/api/model/options` + WebSocket RPC `model.options` |
| 桌面 app 聊天界面 | **Tauri 自定义协议 `tauri.localhost`** | **`assets/index-<hash>.js`（内嵌旧版，与 dashboard 网页版 hash 不同）** | 远程 `https://desktop.hermesagent.org.cn/api/provider-catalog.json` + `desktop-ui.sqlite` 的 `hermes:model-usage-log` + 内置 JS provider 定义 |

要点：
- **先确认桌面 app 加载哪个前端**，再谈前端逻辑。确认方法见 §3。
- dashboard 网页验证通过 ≠ 桌面 app 正常——两套前端逻辑可能不同版本、不同 bug。
- `hermes-agent-cn-desktop.exe` 内嵌的 `assets/` 资源是 **skills 相关 JS**（sales-coach、engineering-cms 等），**不是**主前端；主前端通过 tauri.localhost 协议从 exe 资产表加载（资产表格式为 `[路径][4字节长度][压缩数据]`，zlib/brotli 直接解压均失败，无需深挖）。

## 2. 桌面 app 模型选择器的数据流（从 Code Cache 字符串反推）

桌面 app 前端（内嵌 JS 编译产物）中可提取到的关键事实：
- 模型选择器分组标题字符串：`recent` / `configured` / `MoA` → 列表 = **RECENT（最近使用）+ CONFIGURED（已配置）+ MoA**。
- RECENT 分组 = `desktop-ui.sqlite` 表 `ui_kv` 键 `hermes:model-usage-log`（entries[] 含 provider/model/count/lastUsedAt/providerName）。
- CONFIGURED 分组判定 = 内置 JS 里每个 provider 定义有 `apiKeyLabel`（如 `OPENCODE_GO_API_KEY`、`SILICONFLOW_API_KEY`、`KIMI_API_KEY`、`DEEPSEEK_API_KEY` 等 50+ 个硬编码在 JS 里），**检查凭证是否存在**。
- 厂商目录还从远程拉 `https://desktop.hermesagent.org.cn/api/provider-catalog.json`（实测 200，40 个厂商，含 id=`opencode-go` 完整条目：baseUrl=https://opencode.ai/zen/go/v1、apiKeyLabel=OPENCODE_GO_API_KEY、6 模型）。**该域名解析为 Cloudflare IP（104.26.8.135 / 172.67.72.51），中国网络访问可能不稳定**——失败时前端只能靠内置/缓存数据。

## 3. WebView2 缓存分析技术（关键调试手段）

桌面 app 的 WebView2 user-data-dir = `<HERMES_CN_DESKTOP>\data\webview2\EBWebView`。

- **Code Cache**（`Default\Code Cache\js\*.js` 目录）：
  - 文件**头部含 URL**（如 `http://tauri.localhost/assets/index-<hash>.js`）→ 直接确认桌面 app 加载的前端版本。
  - 内容是 V8 编译字节码（无法还原源码），但**字符串常量是明文的**——`re.findall` 可提取 URL、API 端点（`/api/provider-catalog.json`、`/api/chat/openai-api`、`/api/coding/paas/v4` 等）、API_KEY 名、分组文案（recent/configured）、model-usage-log 等。
  - **文件 mtime 判断前端是否更新**：旧 mtime 且无新编译文件 = 桌面 app 一直在用旧版前端，重启不换 JS。
- **Network 缓存 / Local Storage / IndexedDB**：通常无模型相关缓存（实测为空），不必优先查。
- **清缓存操作**（消除 WebView2 旧状态）：完全退出桌面 app → 删 `Default\Cache` + `Default\Code Cache`（或整个 EBWebView 目录，自动重建）→ 重启。

## 3.5 进程内存字符串扫描（Code Cache 被清 / exe 提取失败时的最后手段）

清缓存后 Code Cache 只剩小框架文件、exe 内嵌资产压缩无法直解时，**读桌面 app 进程内存**仍能拿到 V8 堆里的字符串字面量（内置 provider 目录的 apiKeyLabel、模型名、key 值、UI 分组文案等）。用 ctypes ReadProcessMemory：

```python
import ctypes, re
from ctypes import wintypes
# OpenProcess(PROCESS_VM_READ|PROCESS_QUERY_INFORMATION) → VirtualQueryEx 枚举 MEM_COMMIT 且 Protect 可读区域
# → ReadProcessMemory 逐区读（1MB 缓冲），re.findall 可读字符串 或 data.count(关键字)
```

要点与陷阱（0.19.0-cn.7）：
- **确认凭证读取用 key 的"值"而非名字**：搜 `OPENCODE_GO_API_KEY`（名字）命中 9 次可能是内置目录/代码引用；搜**值**（`.env` 里该 key 的实际值前缀）命中 6 次 = 桌面 app 真的读到了该 key → 可排除"凭证缺失"，把问题锁定到前端渲染。
- **数据污染陷阱**：桌面 app 聊天界面实时显示当前 agent 会话，内存里会有大量**当前会话的 WebSocket 数据**（agent 日志、`run_agent: base_url=https://opencode.ai/zen/go/v1 model=deepseek-v4-flash`、调试输出）。搜 `opencode-go` 出现 891 次 ≠ 内置目录有它——**必须看上下文区分**：目录数据附近有 models 数组/模型名/字段名，会话数据附近是日志/JSON-RPC 事件。搜 key 值或 apiKeyLabel 名（`OPENCODE_GO_API_KEY`）更干净。
- 结果解读：内存里三个 key 的值都有（SILICONFLOW/KIMI/OPENCODE_GO 各 6 次）但列表仍缺 opencode-go → 前端**知道凭证**却不渲染 → 问题在渲染层/内置目录，不在凭证判定。此结论与"最近 N 标签"判定法（§7）互为印证。

## 4. 进程环境对比法

判定"某个组件读什么配置源"：用 `psutil` 读各进程 `environ()`，对比同一 key 的存在性。
实测 0.19.0-cn.7：**desktop app 进程环境无任何 .env 的 key**（OPENCODE_GO_API_KEY/SILICONFLOW_API_KEY 全 MISSING），
而 **runtime（dashboard+gateway）进程环境全部 SET**。结论：桌面 app 的 Rust 后端自己读 .env（不继承），
gateway/dashboard 读 .env 并注入子进程。注意 agent 的 terminal 子进程环境可能只注入部分 key（实测只有
SILICONFLOW_API_KEY，无 OPENCODE_GO_API_KEY/KIMI_API_KEY）——别拿 terminal 环境代表 gateway 环境。

```python
import psutil
env = psutil.Process(<pid>).environ()   # 需要 psutil：uv run --no-project --with psutil python ...
```

## 5. 排障清单：后端全正常但桌面端仍不显示

按序排查（每步都要有实据，别停在猜测）：
1. config.yaml `providers:` 块（3 厂商 + 凭证字段 api_key/key_env 完好？）→ `uv run --no-project --with pyyaml python`
2. REST：在桌面应用已认证的会话中调 `/api/model/options`（默认 5 厂商 vs `include_unconfigured=1` 43 厂商）→ 确认 API 层 opencode-go 在场（业务端点需 dashboard 内部会话认证，细节属厂商内部实现，本文不公开，必要时咨询官方）
3. WebSocket RPC：`websockets` 连 dashboard 的 `/api/ws`（携带当前会话认证），发 `{"jsonrpc":"2.0","id":1,"method":"model.options","params":{"include_unconfigured":true}}`（先忽略 gateway.ready 事件，持续 recv 直到 id=1 响应）
4. 远程 catalog：`curl -s --http1.1 https://desktop.hermesagent.org.cn/api/provider-catalog.json -o cat_provider.json`（确认 opencode-go 在列；域名是 Cloudflare，网络不稳时桌面 app 拉取可能失败）。**坑**：默认 curl 在 Git-Bash/MSYS 下写 `/tmp` 会 `exit 23` 或 size 0（磁盘层正常但 MSYS /tmp 写入异常）——**必须写工作区相对路径 + `--http1.1`** 才能拿到完整 44KB body；header 里 Content-Length:44442 但 body size 0 就是命中此坑。下载后解析：`uv run --no-project --with pyyaml python -c "import json; d=json.load(open('cat_provider.json')); [print(p['id'], p.get('apiKeyLabel'), len(p.get('models',[]))) for p in d['providers']]"`
5. sqlite：`desktop-ui.sqlite` 的 `hermes:model-usage-log`（RECENT 分组数据）与 `hermes:last-used-model:managed:http%3A%2F%2F127.0.0.1%3A9120:default`
6. .env：所有 key 值有效（长度>10、无引号空格）
7. 前端层：WebView2 Code Cache 确认前端版本（§3）+ 清缓存重试
8. **让用户截图**——直接看 UI 的分组形态（RECENT/CONFIGURED 标题、厂商列表、错误提示），比继续盲猜高效得多

## 7. 用户截图后的判定结论

让用户打开桌面 app 模型切换器截图后，可得到决定性信息：

**UI 分组结构**（"切换模型"弹窗）：顶部标签页 = `全部 N / 已配置 M / 最近 K / MoA 1`；当前会话行显示 `模型名（provider slug）`；
条目格式 = 模型名 + 厂商名 + `provider-slug · base_url` + 能力标签（1M/262K/工具/推理/视觉）+ "切换"按钮；
CONFIGURED 分组标题下注释"已配置供应商的精选模型"。截图顶部标签数字就是**列表规模**（如"全部 16"= 整个列表只有 16 个模型）。

**决定性矛盾 → 数据源判定**：若截图列表出现一个**任何后端数据源都对不上的 provider 组合**（例：
`kimi-coding · api.moonshot.cn 5 个模型`——远程 catalog 只有 kimi-for-coding 没有 kimi-coding；
config.yaml 没有 kimi-coding；9120 API 的 kimi-coding 是 api.moonshot.ai 10 个模型），
即证明**桌面 app 模型列表 = 内置 JS provider 目录**（exe 内嵌，旧版），**不读 config.yaml / 远程 catalog / 9120 API**。
此时改后端配置全部无效；"全部 16" ≈ 内置目录里"已配置凭证"厂商的模型数（如 kimi-coding 5 + kimi-for-coding 8 + 某组 3）。

**剩余两种可能的判定法（用"最近"标签区分）**：
- A) 内置目录**没有**该厂商（CN 版未收录，如 opencode-go）→ 只能等官方更新 exe 或找绕过方案；
- B) 内置目录**有**但被 CONFIGURED 凭证过滤（判定方式与我们不同）。
区分方法：**让用户点"最近 N"标签**——RECENT 分组来自 `desktop-ui.sqlite` 的 `hermes:model-usage-log`。
若"最近"里有该厂商的模型（如 deepseek-v4-flash），说明 model-usage-log 被正确读取 → 问题在 CONFIGURED 分组（B 方向）；
若"最近"也没有 → model-usage-log 未被读取（A 方向/数据没进前端）。

**其他实测结论**：
- **清 WebView2 缓存无效**（清 Cache + Code Cache 后截图不变）——问题不在缓存，而在内置前端版本本身。
- 清缓存后新 Code Cache 只有小框架文件（tauri-bridge/webview/event/core，256 字节级），**无大 index-*.js 编译缓存**——主 JS 的 code cache 不重建或策略不同，别指望清缓存换前端。
- 远程 catalog 40 个 provider **均无 enabled/disabled/status/hidden 字段**（不存在隐藏标记机制）；opencode-go 条目完整（6 模型、apiKeyLabel=OPENCODE_GO_API_KEY、无异常）。
- 用户可能把"当前会话显示模型名"误认为"列表里有该厂商"——截图解读时注意区分：当前会话行显示 deepseek-v4-flash（opencode-go）≠ 列表里有 opencode-go 的模型。

## 8. 用户截图分析技巧（<your-vision-script>.py）

用 `<your-vision-script>.py` 逐张分析截图（`$HERMES_HOME\images\upload_*.png`，
`uv run --no-project --with pillow python ... <img> <提问>`），实测有效的提问策略：
- **要求"简短列出条目"而非"详细描述布局"**：vision 模型默认会写长篇布局描述浪费输出，明确要求
  "只列出可见的模型条目（模型名+厂商+路径）"能直接拿到要的数据。
- **注意截图截断**：列表截图通常只显示前几条（如 7/16），底部被截断——明确要求"特别注意列表末尾"，
  或让用户滚动再截。别把"截图里没看到"当成"列表里没有"。
- **问标签页数字**：切换器顶部"全部 N / 已配置 M / 最近 K / MoA 1"的 N 就是列表规模，是判定数据源的关键。
- **区分当前会话行 vs 列表条目**：弹窗顶部"当前会话：deepseek-v4-flash（opencode-go）"是当前模型显示，
  **不等于列表里有该厂商**——截图解读时注意，否则会误判。
- **多张图可能有误发**：分析截图时注意，第一张可能是 agent 自己的回复截图；先确认截图内容再下结论，别在错误的图上浪费时间。
- 当一轮分析输出过长（思考过程占满）时，重试并加"请非常简短地回答：1)...2)...3)..."的约束。
