---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Agent-browser 安装与 Chrome 策略

`agent-browser` CLI 用于浏览器自动化。技能 stub 存在但 CLI 未安装时，浏览器自动化会报不可用——以下为安装与验证路径。

## 安装与验证

1. **安装 CLI**：`npm i -g agent-browser`（nodejs 需在 PATH），随后 `agent-browser doctor` 验证。
2. **无需独立 Chrome**：`agent-browser install`（下载独立 Chrome for Testing）在国内网络可能 TLS 失败（googlechromelabs.github.io 可达性波动），**但非必需**——doctor 显示系统 Chrome `pass` 即可直接驱动（CDP 直连，无 Playwright 依赖）。
3. **升级后清理旧 daemon**：升级 CLI 后旧 daemon 报 `version mismatch` → `agent-browser --session default close` 清理。

## 使用要点

- **首次冷启动慢**：首次 `open <url>` 可能超时（daemon + Chrome 首启），重试即正常。
- **权威使用手册**：`agent-browser skills get core` 是版本匹配的使用手册（SKILL.md 只是指路 stub）。
- **端到端验证**：`open https://example.com` + `snapshot` 返回 accessibility 树即通过。