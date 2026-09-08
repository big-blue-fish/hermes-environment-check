---
scope: Hermes CN Desktop 0.20.0-cn.5
status: workaround
last_verified: '2026-08-14'
---

# MCP 服务器故障排查指南

MCP 服务器诊断和修复方法，覆盖常见的启动失败与配置问题。

## 常见 MCP 错误模式

### 1. fetch 服务器版本不兼容
**症状**：
```
ImportError: cannot import name 'McpError' from 'mcp.shared.exceptions'
```

**位置**：
```
C:\Users\<user>\AppData\Local\Programs\Python\Python311\Lib\site-packages\mcp_server_fetch\
```

**根本原因**：
- mcp-server-fetch 包版本过旧
- MCP 客户端库版本不匹配

**修复方案**：
```powershell
# 升级 mcp-server-fetch
pip install --upgrade mcp-server-fetch

# 检查版本兼容性
pip show mcp mcp-server-fetch

# 重新安装最新版
pip uninstall mcp-server-fetch -y
pip install mcp-server-fetch
```

### 2. tavily 服务器 API Key 问题
**症状**：
```
Error: TAVILY_API_KEY environment variable is required
```

**位置**：
```
C:\Users\<user>\AppData\Local\npm-cache\_npx\...\node_modules\tavily-mcp\
```

**根本原因**：
- 配置文件中的 API key 可能不正确或过期
- 环境变量未正确传递

**修复方案**：
```powershell
# 1. 验证现有 key
# 检查 config.yaml 中的配置
# 如果需要新 key，访问 https://tavily.com/

# 2. 临时禁用配置
# 在 config.yaml 中设置：
# mcp_servers:
#   tavily:
#     enabled: false
```

## MCP 服务器状态检查流程

### 诊断步骤
```powershell
# 1. 检查 MCP 日志文件
Get-Content -Tail 20 "<HERMES_HOME>\logs\mcp-stderr.log"

# 2. 查看相关进程
Get-Process | Where-Object {$_.ProcessName -match "(python|node|mcp)"} | 
    Select-Object ProcessName, Id, Path

# 3. 检查配置文件
Get-Content "<HERMES_HOME>\config.yaml" | 
    Select-String "mcp_servers:" -Context 20
```

### 快速健康检查
```powershell
# 测试 MCP 功能是否可用
# 使用任意工具调用，如：
# - mcp__fetch__fetch 工具（测试网络访问）
# - skills_list 命令（测试基础功能）

# 检查 MCP 工具可用性
# 查看系统提供的工具列表中是否有 mcp__fetch__ 前缀的工具
```

## 应急处理方案

### 方案 A：暂时禁用故障服务器
```powershell
# 编辑 config.yaml
$configPath = "<HERMES_HOME>\config.yaml"
$content = Get-Content $configPath -Raw

# 找到 mcp_servers 部分，暂时禁用故障服务器
# 例如，将 fetch 设置为 enabled: false
```

### 方案 B：完全重置 MCP 配置
```powershell
# 备份当前配置
$backupPath = "$env:HERMES_HOME\config.yaml.backup-$(Get-Date -Format 'yyyyMMdd')"
Copy-Item "$env:HERMES_HOME\config.yaml" $backupPath

# 移除故障的 MCP 配置部分
# 重新启动 Hermes Agent 让其重新生成默认配置
```

