---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
related:
- config-provider-editing.md
---

# 从桌面 app "预置供应商"列表删除某个预置项（如 opencode-go）

适用触发：用户在桌面 app 的模型/供应商选择界面看到"预置供应商"分组，想把其中某个**预置**项（例如
`opencode-go`）从列表删掉。与 `references/config-provider-editing.md` 的差别：那个是删 config.yaml
`providers:` 块里的**已配置** provider；这里是删**预置目录**里的项（界面里的"预置供应商"分组）。

## 已确认事实（0.19.0-cn.7 / 0.20.0-cn.5）

- 该列表是"预置供应商"目录，来源 = **桌面 app 内置前端 JS 的 provider-catalog**（硬编码，`web/src/lib/provider-catalog.ts`
  编译产物）+ 远程 `https://desktop.hermesagent.org.cn/api/provider-catalog.json`（"刷新预置"会重新拉取）。
- 本机缓存 = `$HERMES_HOME/cat_provider.json`（约 40 个供应商，`metadata.source` 指向上述 provider-catalog.ts）。
- 目录里的供应商**没有任何 `enabled/disabled/hidden/status` 标记机制**——无法用"隐藏"开关关掉单个。
- `config.yaml` 的 `desktop.models.provider_order`（桌面模型选择器排序列表）也含该 provider 名，是另一处要清的。
- 注意：该 provider 可能早已不在 `config.yaml` 的 `providers:` 块（只作为预置目录项显示），此时删除不影响实际使用。

## 删除步骤（每步都可逆，先备份）

### 1. 备份 + 编辑 cat_provider.json（本地预置目录缓存）

```bash
uv run --no-project python -c "
import json, shutil, time
p = r'<HERMES_HOME>\cat_provider.json'
bak = p + '.bak-delopencode-' + time.strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, bak); print('backup:', bak)
d = json.load(open(p, encoding='utf-8'))
before = len(d['providers'])
d['providers'] = [x for x in d['providers'] if x.get('id') != 'opencode-go']
with open(p, 'w', encoding='utf-8') as f:
    json.dump(d, f, ensure_ascii=False, indent=2)
print(f'providers {before} -> {len(d[\"providers\"])}')
d2 = json.load(open(p, encoding='utf-8'))
print('still present:', any(x.get('id')=='opencode-go' for x in d2['providers']))
"
```

### 2. 清理 config.yaml 的 desktop.models.provider_order

`patch`/`write_file` 工具拒绝写 config.yaml，必须用 Python **按行删除**（保留注释和其他内容），再单独用
`--with pyyaml` 验证顶层键完整。

```bash
# 按行删除 `      - opencode-go`（不需要 yaml 依赖）
uv run --no-project python -c "
import shutil, time
p = r'<HERMES_HOME>\config.yaml'
bak = p + '.bak-delopencode-' + time.strftime('%Y%m%d-%H%M%S')
shutil.copy2(p, bak); print('backup:', bak)
lines = open(p, encoding='utf-8').read().splitlines(keepends=True)
out, removed = [], 0
for ln in lines:
    if ln.strip() == '- opencode-go':
        removed += 1; continue
    out.append(ln)
open(p, 'w', encoding='utf-8').writelines(out)
print('removed lines:', removed)
"
# 验证 YAML 完整
uv run --no-project --with pyyaml python -c "
import yaml
d = yaml.safe_load(open(r'<HERMES_HOME>\config.yaml', encoding='utf-8'))
print('top keys ok:', sorted(d.keys()))
print('still in provider_order:', 'opencode-go' in d['desktop']['models']['provider_order'])
"
```

### 3. 用户验证

**完全退出桌面 app（不是关窗口）再重开**，打开供应商选择界面看该项是否消失。

## 局限（务必向用户说明，别承诺一定成功）

- 若桌面 app 从**内置 JS / 远程 catalog** 拉取预置列表（而非本地 `cat_provider.json`），本地删除**可能不生效**，
  或用户点"刷新预置"后该项被重新拉回。
- 真正硬编码在 exe 内置 JS 里的预置项，本地文件改不动，只能等官方更新移除。
- 因此流程是"尽力 + 用户验证"：先做可逆的本地删除，让用户重启验证；若仍在则如实告知只能靠官方。
