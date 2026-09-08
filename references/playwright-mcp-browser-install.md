---
scope: Hermes CN Desktop 0.20.0-cn.5
status: verified
last_verified: '2026-08-14'
---

# Installing the Playwright MCP browser on Hermes CN Desktop (verified)

## Symptom
The `mcp__playwright__*` tools error on first call:
```
Error: Browser "chrome-for-testing" is not installed; expected executable at
C:\Users\<user>\AppData\Local\ms-playwright\chromium-1237\chrome-win64\chrome.exe.
Run `npx @playwright/mcp install-browser chrome-for-testing` to install
```
But `~/AppData/Local/ms-playwright/` looks empty.

## Root cause (3-part — don't stop at "no browser")
1. **Playwright MCP looks ONLY in `~/AppData/Local/ms-playwright/`** — the MCP subprocess does NOT inherit Hermes's `PLAYWRIGHT_BROWSERS_PATH` env var, even though the main Hermes runtime sets it to `$HERMES_HOME\cache\ms-playwright`. So a browser present in the Hermes cache is invisible to the MCP.
2. **Version mismatch is the real trap**: Hermes's own cache has one chromium build (e.g. `chromium-1234`), but the `@playwright/mcp@latest` (0.0.79) needs a NEWER build (`chromium-1237`). The executable path embedded in the error is authoritative — read the build number from it.
3. `~/AppData/Local/ms-playwright/` may genuinely be empty even while the Hermes cache has a full browser.

## Verify your assumptions first (don't guess)
- Check BOTH locations:
  - `ls "$HOME/AppData/Local/ms-playwright/"` (what MCP uses)
  - `ls "$HERMES_HOME/cache/ms-playwright/"` (what the runtime sets PLAYWRIGHT_BROWSERS_PATH to)
- Find the exact expected path from a real MCP call error (or `node -e "console.log(require('playwright').chromium.executablePath())"`).
- Confirm which playwright version MCP needs:
  ```bash
  npm view @playwright/mcp@<version-from-error> dependencies   # -> playwright / playwright-core version
  ```
  e.g. `@playwright/mcp@0.0.79` → `playwright 1.63.0-alpha-...` → chromium build 1237.

## Dead ends (do NOT waste time again)
- `npx -y playwright install chromium` run from a bare dir **silently no-ops**: prints only the "install your project's dependencies first" warning box, exits 0, downloads NOTHING. The `-y` npx-temp package never resolves a browser to download.
- `npx -y @playwright/mcp@latest install-browser chrome-for-testing` prints the SAME warning box and **hangs** (no download starts). It is not a working install path in this environment.
- Don't rely on the Hermes cache browser: even though it's a complete 400MB+ chromium, it's the WRONG build number and the wrong location for the MCP.

## Working approach: manual download + unzip to the expected path
The zip URL for a given Chrome-for-Testing version `X.Y.Z` and build `N` is:
```
https://cdn.playwright.dev/builds/cft/X.Y.Z/win64/chrome-win64.zip
```
Get `X.Y.Z` by matching the build number: chromium-N maps to a Chrome-for-Testing release (e.g. build 1237 ≈ `151.0.7922.34`; resolve exactly via the MCP error's expected path + `playwright-core`'s browser registry if needed).

Target layout (must match the MCP error exactly):
```
~/AppData/Local/ms-playwright/chromium-<N>/chrome-win64/chrome.exe
```

```bash
cd "$HOME/AppData/Local/ms-playwright"
curl -L --retry 3 -C - -o chrome-win64.zip \
  "https://cdn.playwright.dev/builds/cft/151.0.7922.34/win64/chrome-win64.zip"
# then unzip chrome-win64.zip into a dir named chromium-<N>
```

### Network reality (CN)
- `cdn.playwright.dev` → 307 → `storage.googleapis.com` (200). Fine for small probes but 真实下载速度可能很慢（大文件需 1 小时以上），用支持断点续传的下载方式。
- Faster mirror: `https://registry.npmmirror.com/-/binary/chrome-for-testing/<ver>/win64/chrome-win64.zip`. Use `-C -` for resume.
- No fast source observed in this environment; plan for a long background download with `terminal(background=true, notify_on_complete=true)`.

## Fix pattern
1. Read the exact expected path from the MCP error.
2. Determine build `N` and Chrome-for-Testing version `X.Y.Z`.
3. Background-download the zip to `~/AppData/Local/ms-playwright/` with resume.
4. On completion unzip to `chromium-<N>/chrome-win64/`.
5. Re-call the playwright MCP tool to confirm the error is gone.
6. Clean up `chrome-win64.zip` and any temp npm setup dir.
