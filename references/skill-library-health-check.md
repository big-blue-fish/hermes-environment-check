---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# 技能库批量健康检查（"所有技能都能跑通吗"）

用户要求"遍历所有 skills 确保都能跑通"时的检查方法（对已安装技能的扫描）。

## 两层检查

**第一层：文件完整性（脚本批量扫）** — 对 `$HERMES_HOME/skills/**/SKILL.md`：
1. frontmatter：以 `---` 开头且闭合、yaml.safe_load 可解析、name/description 非空
2. 正文长度 >50 字符
3. 引用文件存在性：正则抓正文里的 `references/|scripts/|templates/xxx.ext` 相对路径，逐个 `os.path.exists` 验证

**第二层：运行时依赖（分类判断）** — 技能能否真正跑起来：
- CLI：`shutil.which` 批量查（gh/hf/ffmpeg/agent-browser/manim/yt-dlp…）
- Python 包：**必须用系统 Python 查**（`C:\Users\<USER>\AppData\Local\Programs\Python\Python311\python.exe` + importlib.util.find_spec）——**`uv run --no-project` 是隔离环境，import 检查会 35/35 全缺，是误报**
- MCP/服务：config.yaml 的 mcp_servers 段 + 日志

## 三大误报类别（第一层报"缺失"时先甄别再下结论）

1. **文档示例/占位符**：`scripts/example.py`、`repro_bug.py`、`make_figure2.py` 等是教学文字，非真实依赖；跨技能引用写作 `references/<skill-name>/example-file`。
2. **跨技能引用**：`some-file.md (in skill <other>)`、`${HERMES_HOME}/skills/github/github-auth/scripts/xxx.py` —— 目标文件在**别的技能目录**下，按相对路径解析才报缺失；逐个去目标技能目录验证存在性
3. **模板/外部仓库**：`# 模板` 注释的脚本片段、`git clone github.com/hamelsmu/...` 之类外部依赖

甄别方法：grep 出引用处的上下文（前后 ~70 字符），一眼可判断属于哪类。

## 按需依赖模式（关键认知）

系统 Python 缺 akshare/pandas/manim 等 20+ 包 ≠ 技能不可用：
- `uv run --no-project --with <pkg> python script.py` 自动拉包+传递依赖（akshare 连带 pandas），技能脚本普遍自带 `--with` 写法
- 结论分级：A 类开箱即用（纯提示词/MCP/已装 CLI）/ B 类 uv 按需可用 / C 类需装 CLI（gh、hf、yt-dlp、manim 等，winget/pip 可装）
- 汇报用 A/B/C 分级表 + 明确"缺哪些装哪些"，不要把 B/C 当故障

## 检查脚本要点（Windows）

- 脚本写到 `E:/...` 路径再 `uv run --no-project --with pyyaml python script.py`（MSYS /tmp 读不到）
- 跨技能引用验证单独一步：`ls` 目标技能的 references/scripts 目录
