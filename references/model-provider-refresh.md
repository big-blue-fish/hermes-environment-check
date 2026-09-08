---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 刷新模型供应商（Refresh Model Providers）

用户说"刷新模型供应商"时，对应 Hermes 官方的模型选择器缓存刷新。核心命令与机制如下。

## 命令

```bash
"<runtime.exe>" model --refresh --no-browser
```

`--refresh` 的官方语义（`model --help`）：
> **Wipe the model picker disk cache and re-fetch every provider's live /v1/models list.**

即：清空模型选择器的磁盘缓存，然后重新从每个已配置供应商的实时 API 拉取 `/v1/models` 列表。这是桌面 app 模型选择器（SWITCH MODEL / 状态栏 model picker）数据来源之一。

## 缓存文件

- **位置**: `$HERMES_HOME/provider_models_cache.json`
- **结构**: `{"<内部provider名>": {"fp": "...", "at": <unix时间戳>, "models": ["...", ...]}}`
- **注意**: key 是**内置 provider 插件名**（`kimi-coding`、`deepseek`、`opencode-go`），**不是** config.yaml `providers:` 块里的自定义键名（`kimi-for-coding`、`siliconflow`、`custom:opencode-ai`）。用 `grep -o "<名>"` 判断某供应商是否已进缓存。
- 时间戳 `at` 可 `date -d @<ts>` 换算，判断缓存是否新鲜。

## 验证刷新是否生效

```bash
# 运行前/后各执行一次，对比 mtime 和 at 时间戳
ls -la "$HERMES_HOME/provider_models_cache.json"
cat "$HERMES_HOME/provider_models_cache.json"
date +%s   # 当前时间戳，用于对比 at
```

## 关键 Pitfall：`hermes model` 是交互式 picker，非交互环境跑不完整

`model --refresh` 成功后**仍会进入交互式供应商选择器**（列出全部条目，含当前活动标记）。在非交互环境下无法完整走完最后一步：

- **`< /dev/null` 作为 stdin**: 会输出 "Cleared model picker cache." 并列出供应商，然后读到 EOF 直接打印 "No change." 退出（退出码 0）。**能清缓存、能重建部分供应商**（刷新阶段按序拉取的，如 kimi-coding、deepseek），但当前活动的供应商（opencode-go）因还没轮到就 EOF 而**不重建**。
- **`| head -80` 管道**: 提前关闭管道 → SIGPIPE → 进程以 0xC000013A（Ctrl+C/STATUS_CONTROL_C_EXIT）退出，缓存被清但重建不确定。
- **`printf '37\n' | ...`**: 直接报 `Error: 'hermes model' requires an interactive terminal. It cannot be run through a pipe or non-interactive subprocess.`
- **`pty=true` 后台运行**: 交互式 picker 无法在后台 PTY 正常渲染，同样以 0xC000013A 退出。

**结论**: agent 侧能可靠完成的是"清除缓存 + 刷新到当前活动供应商之前的供应商"。若要补全当前活动供应商（如 opencode-go）的缓存，需用户自己在真实终端跑 `hermes model`，选该供应商回车触发实时拉取后选 "Leave unchanged" 退出。

## 影响评估

不补全 opencode-go 缓存**不影响使用**：
- 模型名已在 config.yaml `model.default` / `providers.<name>.models` 手写定义；
- 选择器打开时仍会实时拉取 / 以 snapshot 兜底；
- 只有当缓存缺失 + 网络差时才可能触发离线兜底流程（见 `model-options-timeout-offline-cache.md`）。

## 完整工作流

1. 确认 runtime 可访问：`"<runtime>.exe" model --help` 里能看到 `--refresh`。
2. 记录刷新前缓存 mtime。
3. 执行 `< /dev/null` 版刷新（可加 `timeout 40` 防挂住），确认打印 "Cleared model picker cache."。
4. 对比缓存 mtime/at 已更新，确认 kimi-coding、deepseek 等已重建。
5. 告知用户 opencode-go 等当前活动供应商需自己在真实终端补跑（见上）。
