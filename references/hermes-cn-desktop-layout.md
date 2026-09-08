---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Hermes CN Desktop — Directory Layout & Quirks

The Hermes CN Desktop (中国版桌面客户端) has a different layout from the standard Hermes Agent install. Reference these paths when diagnosing or configuring a CN Desktop instance.

## Top-Level Structure

```
<HERMES_CN_DESKTOP>/
├── bundled-skills/          # Skills shipped but NOT auto-installed
├── bundled-plugins/         # Plugins shipped but NOT auto-installed
├── bundled-runtime/         # Runtime package (zip + version manifest)
├── dashboard/               # Web dashboard assets
├── data/
│   ├── versions/
│   │   └── <version>/
│   │       ├── hermes-agent-cn-runtime-win32-x64.exe   # The actual runtime
│   │       └── node/
│   └── hermes-home/         # $HERMES_HOME for this session
│       ├── config.yaml
│       ├── .env
│       ├── skills/          # Installed skills
│       ├── plugins/         # Enabled plugins (symlink/copy from bundled)
│       ├── cron/
│       ├── memories/
│       ├── sessions/
│       ├── logs/
│       ├── state.db
│       ├── kanban.db
│       └── SOUL.md
├── hermes-agent-cn-desktop.exe  # Desktop launcher (Electron wrapper)
└── uninstall.exe
```

## Key Differences from Standard Hermes

| Aspect | Standard Hermes | CN Desktop |
|--------|----------------|------------|
| CLI binary | `hermes` on PATH | Embedded in runtime; NOT on PATH by default |
| Skills location | `~/.hermes/skills/` | `$HERMES_HOME/skills/` (under `data/hermes-home/`) |
| Bundled skills | Auto-installed | In `bundled-skills/` — must be installed manually |
| Plugin management | `hermes plugin install` | Same command, but binary is inside runtime directory |
| Config path | `~/.hermes/config.yaml` | `data/hermes-home/config.yaml` |
| Provider config | Via `hermes model` | Same, but providers configured in config.yaml directly |

## Available Bundled Resources

### Bundled Skills Categories
- **autonomous-ai-agents:** claude-code, codex, opencode
- **apple:** apple-notes, apple-reminders, findmy, imessage
- **computer-use:** desktop control
- **creative:** ascii-art, ascii-video, baoyu-infographic, claude-design, manim-video, songwriting-and-ai-music
- **email:** himalaya (CLI email)
- **media:** gif-search, heartmula, songsee, youtube-content
- **mlops:** lm-evaluation-harness, vllm, audiocraft
- **note-taking:** obsidian
- **productivity:** google-workspace, maps, notion
- **research:** research-paper-writing
- **smart-home:** openhue
- **social-media:** xurl
- **software-development:** python-debugpy
- **yuanbao:** 腾讯元宝 integration

### Bundled Plugins Categories
- **browser:** browserbase, browser_use, firecrawl
- **cron_providers:** chronos
- **image_gen:** deepinfra, fal, krea, openai, openai-codex, openrouter, xai
- **memory:** byterover, hindsight, holographic, honcho, mem0, openviking, retaindb, supermemory
- **model-providers:** alibaba, anthropic, bedrock, copilot, deepseek, fireworks, gemini, huggingface, kimi-coding, minimax, nous, openrouter, qwen-oauth, stepfun, xai, zai (20+)
- **observability:** langfuse, nemo_relay
- **platforms:** dingtalk, discord, email, feishu, google_chat, homeassistant, line, matrix, mattermost, slack, teams, telegram, wecom, whatsapp (20+)
- **video_gen:** deepinfra, fal, xai
- **web:** brave_free, ddgs, exa, firecrawl, parallel, searxng, tavily, xai

## PowerShell Exit Code Quirk

On this CN Desktop version, the `terminal` tool runs PowerShell 5.1 where commands that succeed (`$?` is `$true`) still report `exit_code=1` in Hermes tool output. **This is a tool/reporting quirk, not a real failure.** The stdout/stderr content is valid. Ignore exit_code=1 when the output shows the expected result.

## Enabling Skills and Plugins

Since `hermes` is not on PATH, use the runtime executable directly:

```powershell
$runtime = "<HERMES_CN_DESKTOP>\data\versions\<version>\hermes-agent-cn-runtime-win32-x64.exe"
& $runtime skills list
& $runtime plugin list
& $runtime plugin enable platforms/telegram
```

Or enable plugins declaratively by copying from `bundled-plugins/` to `hermes-home/plugins/`.
