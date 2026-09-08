---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# MCP Stdio Add Syntax (Windows)

Real-world patterns discovered during MCP server repair.

## The Correct `hermes mcp add` Syntax for Stdio Servers

```powershell
hermes mcp add <name> --command "C:\Full\Path\to\exe.cmd" --env "KEY=value" --args "arg1" "arg2"
```

### Key rules (non-obvious)

1. **`--command` requires a full path.** On Windows, `mcp add` does NOT resolve PATH. `--command npx` fails with `WinError 2` (系统找不到指定的文件). Use `--command "C:\Program Files\nodejs\npx.cmd"`.

2. **`--env` goes before `--args`.** The `--args` option must be the LAST option. If you put `--env` after `--args`, parsing breaks.

3. **Arguments are positional.** `--args` consumes everything after it until the end of the command. Each argument is a separate quoted string.

4. **`npx.cmd` not `npx`.** Use the `.cmd` extension explicitly. The bare name may not be recognized as executable by the subprocess launcher.

## Example: Adding Tavily MCP

```powershell
# FIXED — works:
"Y" | hermes mcp add tavily --command "C:\Program Files\nodejs\npx.cmd" --env "TAVILY_API_KEY=tvly-xxx-xxxx" --args "-y" "tavily-mcp"

# BROKEN — stale cache path (Connection closed):
hermes mcp add tavily --command "C:\Program Files\nodejs\node.exe" --args "C:\Users\...\AppData\Local\npm-cache\_npx\<stale-hash>\node_modules\tavily-mcp\build\index.js"
```

## Common Failure: Stale npx Cache

**Symptom:** `hermes mcp test tavily` → `✗ Connection failed (7685ms): Connection closed`

**Root cause:** The previous config used a cached npx path at
`$env:LOCALAPPDATA\npm-cache\_npx\<hash>\node_modules\tavily-mcp\build\index.js`
After npm/npx updates, this cached path becomes invalid.

**Fix:** Remove the broken server and re-add using `npx -y <package>`:
```powershell
hermes mcp remove tavily
"Y" | hermes mcp add tavily --command "C:\Program Files\nodejs\npx.cmd" --env "TAVILY_API_KEY=..." --args "-y" "tavily-mcp"
```

## Interactive Prompts in Non-Interactive Terminals

On adding, `hermes mcp add` prompts:
```
Enable all N tools? [Y/n/select]:
```

Non-interactive terminals can't answer. Pipe input:
```powershell
"Y" | hermes mcp add <name> ...
```

Without piping, the prompt times out and saves with 0 tools enabled (shows "Cancelled.").

## Verification

After adding/removing:
```powershell
hermes mcp list
hermes mcp test <name>
```

Tools only appear after `/reset` or a new session.
