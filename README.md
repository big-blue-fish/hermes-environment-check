# Hermes Agent Environment Check & Repair

Windows-focused diagnostics and repair Skill for Hermes CN Desktop.

**Release:** 1.0.0 — hardened first-run installation, report redaction, network diagnostics, subprocess timeouts, and repair rollback.

Hermes Agent 环境自检与排障手册：健康检查、依赖诊断、配置修复、MCP 排查，覆盖 Windows 专属坑位。

## 这是什么

一套系统化的 Hermes Agent 环境健康检查与修复技能。当你怀疑环境缺失组件、工具不可用、配置被破坏，或需要安装/升级 Hermes 时使用。覆盖 Windows 专属问题：编码、PATH、winget、文件系统、MCP 服务器诊断与故障排查。

内容沉淀自真实排障过程，每个坑都有根因分析和已验证的修复步骤。

## 兼容性

> **Primary target:** Hermes CN Desktop on Windows  
> **Tested primarily with:** Hermes CN Desktop 0.19.0-cn.7, Hermes CN Desktop 0.20.0-cn.5, Windows 10/11  
> Other Hermes distributions may differ.

## 环境依赖（普通用户对照）

**必需**（健康检查本身只需要这些）：

- Windows 10/11 + PowerShell 5.1+（系统自带）
- 已安装的 Hermes CN Desktop。`hermes-doctor.ps1` 会**自动探测**安装位置（扫描 `%LOCALAPPDATA%`、`Program Files` 及各盘符下的 `Hermes Agent CN Desktop\data\hermes-home`），**无需**手动设置 `HERMES_HOME`。

**修复脚本的特定前置条件**：

- **`apply-weixin-cron-fix.py`** — 仅用于 Hermes CN Desktop **0.20.0-cn.5** 的微信定时任务 NameError 修复。需要：
  - Python 3（任意版本）
  - PyYAML：安装命令 `pip install pyyaml` 或 `uv run --no-project --with pyyaml python apply-weixin-cron-fix.py`
  - 脚本内置版本检查：如果你的 Hermes 版本不是 0.20.0-cn.5，脚本会拒绝执行并提示版本号（防止错误应用）
- **`validate-repo.py`** — 仅用于验证 skill 仓库本身的完整性，普通用户不需要运行
- **其他可选增强** — node/npm、ffmpeg、rg、uv 等。doctor 会报告是否安装，缺失不阻塞诊断

## 安装 / 使用

这是一个 **Hermes Agent 环境诊断与排障 Skill**。

### 第一步：安装到正确的 skills 目录

解压本 Release 后，最终目录必须满足：

```text
<HERMES_HOME>\skills\hermes-environment-check\SKILL.md
<HERMES_HOME>\skills\hermes-environment-check\references\
<HERMES_HOME>\skills\hermes-environment-check\scripts\
```

不要把 ZIP 文件名目录、GitHub repository 根目录或另一个 `hermes-environment-check` 目录重复嵌套进去。安装完成后，`SKILL.md` 必须是上面路径的直接子文件。

**典型路径**（实际位置因安装盘符而异）：
- **Hermes CN Desktop 桌面版**：`E:\Hermes Agent CN Desktop\data\hermes-home\skills\`
- **标准 Hermes CLI**：`C:\Users\<你的用户名>\.hermes\skills\`

### 第二步：安装方式

```text
方法 1：GitHub 仓库
1. Clone 仓库。
2. 将克隆下来的整个仓库目录放到 <HERMES_HOME>\skills\ 下，并确保目录名为 hermes-environment-check（仓库根目录就是 SKILL.md，勿再加一层子目录）。
3. 确认 <HERMES_HOME>\skills\hermes-environment-check\SKILL.md 存在。

方法 2：Release ZIP
1. 下载本 Release ZIP。
2. 解压后，将 ZIP 内的 hermes-environment-check/ 目录复制到 <HERMES_HOME>\skills\。
3. 确认 SKILL.md 位于目录第一层，而不是第二层。
```

安装后先验证：

```powershell
Test-Path "<HERMES_HOME>\skills\hermes-environment-check\SKILL.md"
```

输出 `True` 后，重启 Hermes，再告诉 Agent「检查运行环境」或「环境诊断」。

## 目录结构

```
hermes-environment-check/
├── SKILL.md                 # 主技能：检查流程 + 快速修复索引
├── references/              # 36 篇专题排障文档（按问题域拆分）
│   ├── config-provider-editing.md       # 配置/Provider 编辑
│   ├── mcp-troubleshooting.md           # MCP 服务诊断
│   ├── model-options-timeout-offline-cache.md  # 模型列表超时
│   ├── playwright-mcp-browser-install.md      # 浏览器缺失修复
│   ├── weixin-gateway-crash-diagnosis.md      # 消息网关故障
│   └── ...                  # 其余见 references/ 目录
└── scripts/                 # 可复用修复脚本
    ├── hermes-doctor.ps1    # 一键诊断：只读收集环境 JSON 报告
    ├── apply-weixin-cron-fix.py      # 微信定时任务修复（版本保护 + dry-run + rollback）
    ├── validate-repo.ps1             # 仓库发布校验（PowerShell 入口）
    └── validate-repo.py              # 仓库发布校验（断链/僵尸/版本一致性）
```

## 快速开始

### 一键诊断（只读，不改任何东西）

```powershell
# Windows 自带 PowerShell，直接用 powershell 即可
powershell -ExecutionPolicy Bypass -File ./scripts/hermes-doctor.ps1

# 输出：JSON 格式的结构化报告（系统信息、runtime、依赖、配置、网络、进程）
# 脚本会自动发现 Hermes 安装位置；如需手动指定，可加：
powershell -ExecutionPolicy Bypass -File ./scripts/hermes-doctor.ps1 -HermesHome "E:\Hermes Agent CN Desktop\data\hermes-home"

# 将报告保存到文件便于分享或留存（分享前请脱敏用户名和路径）：
powershell -ExecutionPolicy Bypass -File ./scripts/hermes-doctor.ps1 -OutputPath report.json
```

**遇到问题？**
- 脚本报告中若 `python`、`pip` 等显示 `installed: false`，说明它们不在 PATH 中，需要在系统环境变量里添加路径或重装。
- `config.yaml` 和 `.env` 若都不存在或有 BOM 编码错误，脚本会标记为警告（🟡）；参考 `references/` 文档中对应主题的修复步骤。

### 修复微信定时任务（仅 0.20.0-cn.5）

该脚本**仅适用于 Hermes CN Desktop 0.20.0-cn.5**（有 InProcessCronScheduler NameError）。其他版本会被拒绝执行。

```bash
# 必要前置：pip install pyyaml
# 或用 uv（推荐）：
uv run --no-project --with pyyaml python scripts/apply-weixin-cron-fix.py --dry-run

# 先预览改动（--dry-run）：
python scripts/apply-weixin-cron-fix.py --dry-run

# 确认无误后执行（会自动备份 config.yaml 为 .bak）：
python scripts/apply-weixin-cron-fix.py

# 执行后重启 Hermes gateway：
# & "<HERMES_CN_DESKTOP>\data\versions\0.20.0-cn.5\hermes-agent-cn-runtime-win32-x64.exe" gateway run --replace --force
```

## 安全说明

本 Skill 包含诊断指令和修复操作。某些操作可能：

- 修改 Hermes 配置文件
- 安装缺失的依赖
- 创建或修改插件
- 修改 Windows 计划任务
- 与运行中的进程交互

Agent 应该先诊断，只有在用户明确要求修复或确认建议的更改时才进行修改。

`hermes-doctor.ps1` 是只读诊断脚本；它会对常见 credential 字段进行脱敏，但报告仍包含用户名、路径和系统信息，公开分享前必须人工复核。修复脚本只在用户明确要求后执行，并包含版本保护、备份、原子写入、验证和失败回滚。

详见 [SECURITY.md](SECURITY.md)。

## 文档

- `SKILL.md`：从健康检查到修复的完整流程
- `references/`：每个专题的根因分析 + 修复步骤 + 验证方法
- `scripts/`：开箱即用的修复脚本

## 许可证

MIT © 2026 big-blue-fish。详见 [LICENSE](LICENSE)。

## 免责声明

脚本和步骤均在特定环境验证过，但 Hermes 版本差异可能导致行为不同。执行前请先备份配置；涉及删除/修改操作时自行评估风险。

## Repository maintenance

The repository includes automated validation for required files,
SKILL.md frontmatter, PowerShell syntax, and common credential patterns.

Run locally with:

```powershell
# pwsh 指 PowerShell 7（跨平台）；未安装时可改用 Windows 自带的 powershell，
# 两个入口均已在 Windows PowerShell 5.1 下验证可用。
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/validate-repo.ps1
# 或（已安装 PowerShell 7/跨平台环境）：
pwsh ./scripts/validate-repo.ps1
```

Pull requests are validated automatically by GitHub Actions. The repository release package also includes the workflow and issue/PR templates so the manifest matches the published repository.
