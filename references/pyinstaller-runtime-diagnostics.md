---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# PyInstaller-Packaged Runtime Diagnosis (Hermes CN Desktop)

The CN Desktop runtime (`hermes-agent-cn-runtime-win32-x64.exe`) is a PyInstaller **onedir** bundle, not a normal pip install. This changes how you diagnose "missing module" failures.

## How to tell it's PyInstaller

- Runtime dir contains `_internal/` (frozen site-packages with `*.dist-info` entries and an `agent/` package dir).
- `--version` reports an embedded Python (e.g. 3.14.6) that has nothing to do with system `python` (often 3.11).
- `manifest.json` in the runtime dir lists `runtimeFlavor`, `sourceRepo` (community fork), `artifactUrl`.

## Consequence: pip cannot fix missing modules

System pip installs into `C:\Users\<user>\AppData\Local\Programs\Python\Python3xx\site-packages` — the frozen runtime never sees them. A missing SDK inside the bundle (e.g. `mem0`) cannot be added with `pip install`. Options: wait for a runtime update, or experiment with `PYTHONPATH` (needs an app restart to verify; PyInstaller usually ignores it unless the app opts in).

## Diagnosing a bundled-plugin import failure (mem0 example)

1. `errors.log` shows (repeated per attempt): `ERROR plugins.memory.mem0: Mem0 backend failed to initialize (platform mode): No module named 'mem0'`
2. Tool calls then fail with: `Mem0 backend not initialized: No module named 'mem0'.`
3. Confirm the plugin really requires the SDK: bundled plugin source lives at `<HERMES_CN_DESKTOP>\bundled-plugins\memory\mem0\_backend.py` — `PlatformBackend.__init__` does `from mem0 import MemoryClient` (platform mode still imports the SDK, it is not HTTP-only).
4. Confirm the bundle lacks it: `search_files` for `mem0*` inside `_internal` → 0 hits.
5. `hermes doctor` may still print `✓ Mem0 API key configured` — that is a config-presence check, NOT backend health. Always verify with a real tool call.

## .env audit without leaking secrets

```powershell
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^([A-Z0-9_]+)=(.*)$') {
    $len = $matches[2].Length
    if ($len -gt 0) { "{0} = [SET, len={1}]" -f $matches[1], $len }
    else            { "{0} = [EMPTY]" -f $matches[1] }
  }
} | Select-String -Pattern 'API_KEY|TOKEN'
```

Shows variable names + value lengths only — never the secret itself.

## MCP stderr can mislead

`mcp-stderr.log` may say `TAVILY_API_KEY environment variable is required` while `config.yaml` `mcp_servers.tavily.env` actually sets the key. The real failure can be an **invalid** key: the tool call then returns vendor `401 Unauthorized`. Cross-check (a) actual tool-call results and (b) `errors.log` (`MCP server 'tavily' initial connection failed (attempt n/3) ... parking until a reconnect is requested`) before concluding the key is missing.

## Other CN Desktop quirks seen in the field

- Inline `mcp_servers.<name>.env` keys work but sit in plaintext in config.yaml (secret redaction does not apply there) — security-scan flagged; prefer `.env` + env inheritance.
- `& $runtime <subcommand>` with `list`/pipes gets rejected by the foreground background-detection wrapper; use `Start-Process` with stdout/stderr redirects.
- `errors.log` warning lines that just echo terminal tool output (`Tool terminal returned error ... exit_code=1`) are the known PowerShell 5.1 exit-code quirk — not real failures.
