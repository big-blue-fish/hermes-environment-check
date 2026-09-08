---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 自建免费搜索 MCP（DuckDuckGo，免 key 无限次）

背景：Hermes 内置 web_search 工具的 ddgs provider 在 PyInstaller 打包里通常不可用（ddgs 是 optional dep，PYZ 未包含 → check_fn 失败 → web_search 工具隐藏）。**绕开方式：自建 MCP 服务器用系统 Python 跑**（MCP 是独立进程，不受 PyInstaller runtime 限制）。

## 步骤

1. **系统 Python 装依赖**（用完整路径，`python` 命令可能是 WindowsApps stub 返回 9009）：
   `C:\Users\<USER>\AppData\Local\Programs\Python\Python311\python.exe -m pip install ddgs mcp`

2. **MCP 服务器** `<your-search-mcp>.py`（FastMCP，2 个工具）：
```python
from mcp.server.fastmcp import FastMCP
mcp = FastMCP("ddg-search")

@mcp.tool()
def web_search(query: str, max_results: int = 8) -> str:
    """DuckDuckGo 免费网页搜索（无需 API key，无限次）。"""
    from ddgs import DDGS
    with DDGS(timeout=10) as client:
        results = list(client.text(query, max_results=min(int(max_results), 15)))
    return "\n\n".join(f"{i+1}. {r.get('title','')}\n   {r.get('href','')}\n   {str(r.get('body',''))[:200]}" for i, r in enumerate(results, 1))

# 同款加 web_search_news(query, max_results) 用 client.news(...)
if __name__ == "__main__":
    mcp.run()
```

3. **注册**（交互确认用管道喂 y）：
   `cmd /c "echo y| ""<runtime.exe>"" mcp add ddg-search --command C:\Users\<USER>\AppData\Local\Programs\Python\Python311\python.exe --args <your-search-mcp>.py"`

4. **验证**：`hermes mcp test ddg-search` → Connected + Tools discovered。新会话生效。

## 国内搜索源连通性

| 源 | 状态 | 备注 |
|---|---|---|
| DuckDuckGo (html/lite) | ✅ 可达 | 偶发超时（curl 一次失败、urllib 成功），ddgs 库可用 |
| Bing | ✅ 可达 | 无免费官方 API |
| Brave API | ✅ 可达 | 需注册 key（免费 2000 次/月）|
| Serper | ✅ 可达 | 需 key（免费 2500 次）|
| Bocha 博查 | ✅ 可达 | 需 key |
| SearXNG 公共实例 (searx.be) | ✅ 可达 | 免 key，公共实例限速 |
| Mojeek | ✅ 可达 | 免 key 小引擎 |
| Google/OpenAI 官方 | ❌ 不通 | 国内网络 |

## 坑

- **`python` 命令 = WindowsApps stub**（Microsoft Store 占位），返回 9009 "command not found"——用完整 Python311 路径。
- **`-c` 代码参数被 Start-Process 拆分**（引号处理不可靠）→ 写脚本文件用 `-File` 跑。
- `hermes mcp add` 交互确认在非交互 shell 取消 → `echo y|` 管道（见 SKILL.md 主文件 MCP 一节）。
