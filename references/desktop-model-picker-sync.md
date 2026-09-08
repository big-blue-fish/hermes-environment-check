---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 桌面模型选择器与 CLI 模型列表"同步"（把全部模型灌进桌面 RECENT 分组）

验证于 0.20.0-cn.5。目标：让桌面聊天输入框的模型选择器里能看到
CLI（`/api/model/options`）返回的全部 opencode 模型，而桌面端只显示几个。

## 结论先行

- **桌面聊天框选择器 ≠ CLI 模型列表，是两套完全独立的数据源**：
  - CLI / dashboard 读 `GET /api/model/options`（读 config.yaml + live `provider_models_cache.json`）→ 模型全。
  - 桌面聊天框选择器**不读** `/api/model/options`。它读三样：内置 JS provider 目录（CONFIGURED 分组，
    exe 内嵌，opencode 只精简列 4 个，**改不了**）+ 远程
    `https://desktop.hermesagent.org.cn/api/provider-catalog.json`（Cloudflare，中国网络可能拉不到）
    + `desktop-ui.sqlite` 的 `hermes:model-usage-log`（RECENT/最近使用分组，**完全可写**）。
- **可行修复**：把全部模型注入 `model-usage-log`，让它们出现在桌面的"最近使用"分组，可直接点选、可正常用。
  CONFIGURED 分组那 4 个精简模型是 exe 写死的，配置层面改不了——要彻底同步到 CONFIGURED 需官方更新前端。

## 决定性验证：桌面前端读什么（V8 Code Cache 明文扫描）

WebView2 的 JS 编译缓存是 V8 字节码，但**字符串常量是明文**。扫描它即可判断前端数据源，
避免"改了后端却无效"：

```bash
cd "<HERMES_CN_DESKTOP>\data\webview2\EBWebView\Default\Code Cache\js"
uv run --no-project --with pyyaml python << 'PYEOF'
import re
for f in ['b3b3c8a053b42537_0']:   # 大文件(2.4MB)=主前端；按需换文件名
    data=open(f,'rb').read()
    strs = re.findall(rb'[\x20-\x7e]{6,}', data)
    text = b' '.join(strs)
    for pat in [b'/api/model/options', b'model-usage-log', b'provider-catalog',
                b'RECENT', b'CONFIGURED', b'last-used-model']:
        if text.count(pat):
            print('HIT', pat.decode(), text.count(pat))
PYEOF
```

命中：`model-usage-log`、`provider-catalog`、`last-used-model` 都在；`/api/model/options` **不存在**
→ 证明桌面选择器走内置目录 + usage-log，不读 CLI API。（Code Cache 文件在缓存被清后只剩小框架文件、
无大 index-*.js 时不可用——此时用进程内存 ReadProcessMemory 扫描 V8 堆字符串，见 desktop-app-frontend-internals.md。）

## 注入脚本（已验证有效）

`model-usage-log` 的 `value_json` 是 `{"entries":[{"key","count","lastUsedAt","model","provider","providerName"}]}`。
把 provider→模型清单写进 entries 即可让 RECENT 分组显示它们：

```bash
cd "<HERMES_HOME>"
cp desktop-ui.sqlite "desktop-ui.sqlite.bak-$(date +%Y%m%d%H%M%S)"   # 先备份
uv run --no-project --with pysqlite3 python << 'PYEOF'
import sqlite3, json, time
models = {
  'opencode-go': [ <全部模型id，从 /api/model/options 或 provider_models_cache.json 拿> ],
  'deepseek': [...], 'kimi-for-coding': [...], 'siliconflow': [...],
}
names = {'opencode-go':'OpenCode Go', 'deepseek':'DeepSeek',
         'kimi-for-coding':'Kimi / Moonshot', 'siliconflow':'硅基流动 SiliconFlow'}
con = sqlite3.connect('desktop-ui.sqlite'); cur = con.cursor()
row = cur.execute("SELECT value_json FROM ui_kv WHERE key='hermes:model-usage-log'").fetchone()
d = json.loads(row[0]); entries = d.get('entries', [])
existing = {e.get('key') for e in entries}
now = int(time.time()*1000); ts = now; added = 0
for prov, mlist in models.items():
    for m in mlist:
        k = f"{prov}:{m}"
        if k in existing: continue
        entries.append({'count':1,'key':k,'lastUsedAt':ts,'model':m,
                        'provider':prov,'providerName':names.get(prov,prov)})
        ts -= 1; added += 1     # 时间戳递减 → 新注入模型排最前
d['entries'] = entries
con.execute("UPDATE ui_kv SET value_json=?, updated_at=? WHERE key='hermes:model-usage-log'",
            (json.dumps(d, ensure_ascii=False), now//1000))
con.commit(); print(f"injected {added}, total {len(entries)}"); con.close()
PYEOF
```

坑：
- **注入后需重启桌面 app**（彻底退出进程，不是最小化）才会重新读 sqlite；`ui_events` 表为空，
  没有可用的即时刷新触发机制。
- 若重启后"最近使用"仍只显示几个 → 可能桌面端对 usage-log 也有过滤（如只显示 count 高者），
  此时调大这些模型的 `count` 值再试。
- 注入的模型能点选、能正常调用（opencode-go 是统一 base_url，模型 ID 直接可用），与 CLI 行为一致。

## 相关文件

- 桌面选择器分组架构 / WebView2 Code Cache / 进程环境对比法 / 截图判定：`desktop-app-frontend-internals.md`
- CLI/API 侧模型管道（explicit_only 过滤、live 缓存）：`model-picker-pipeline.md`
- 接口卡死 / models.dev 联网超时（built-in 厂商消失的症状）：`model-options-timeout-offline-cache.md`
- `provider_models_cache.json` 结构与刷新：`model-provider-refresh.md`
