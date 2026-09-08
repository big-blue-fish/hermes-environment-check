# Changelog

## 1.0.0 - 2026-08-25

First public release.

### Diagnostics scripts

- Added `scripts/hermes-doctor.ps1`: read-only one-shot health check that discovers the active Hermes runtime automatically and emits a structured JSON report (system, runtime, dependencies, config audit, network, processes, MCP status). Handles the WindowsApps python stub and `.ps1` npm wrappers correctly.
- `hermes-doctor.ps1` auto-detects the Hermes CN Desktop install location (scans `%LOCALAPPDATA%`, `Program Files`, and each drive root for `Hermes Agent CN Desktop\data\hermes-home`) when `HERMES_HOME` is unset or stale, and reports the resolution source via `hermes_home_source`.
- Reworked network diagnostics to report DNS + HTTPS status instead of treating ICMP failure as network failure; uses `baidu.com` (instead of `google.com`) as the third reachability target so CN Desktop users do not see spurious unreachable warnings.
- Hardened external-command timeout handling so verbose or hung child processes cannot block the doctor indefinitely.
- Added `--dry-run` / `--verify` support to `scripts/apply-weixin-cron-fix.py`; positional `HERMES_HOME` override is flag-agnostic, and version detection picks the newest installed runtime across both layout candidates.
- Hardened the WeChat cron repair with an automatic timestamped `.bak` backup, atomic config writes, post-write verification, and rollback on failure.

### Removed

- **Removed `scripts/empty-working-sets.ps1`**: its system-wide memory manipulation (SeDebugPrivilege + SetProcessWorkingSetSize on all processes) was tangential to Hermes environment diagnosis and posed AV-flagging risks. The skill now focuses on diagnostics and Hermes-specific repairs; stale references were also cleaned up.

### Repository & validation

- Added `scripts/validate-repo.py` (extended validation): broken reference links, zombie references, frontmatter presence on every reference, Python syntax, and anchor-level validation of `references/xxx.md#anchor` links.
- `validate-repo.ps1` prefers `uv` over the WindowsApps python stub and falls back gracefully.
- Fixed `scripts/validate-repo.ps1`'s description-frontmatter regex: it required content on the same line as `description:` and therefore failed against this repo's own `SKILL.md`, which uses a YAML folded block scalar (`description: >`). The script would have failed its own repository's validation in CI.
- Fixed a stray leading backslash in `scripts/validate-repo.ps1` that ran before `$ErrorActionPreference` was set.
- Added repository validation and GitHub Actions CI, contribution guidance, and a standard `.gitignore`.
- Restored repository-only GitHub metadata (`.github`, `.gitattributes`, `.gitignore`) so `RELEASE_MANIFEST.txt` matches the artifact.
- Normalized all text files to LF line endings, added `.gitattributes` to enforce it going forward, and ensured trailing newlines.
- Standardized repository author metadata and clarified script privilege/safety expectations.
- Removed unverified OpenClaw support wording from the repository description.

### Documentation

- Fixed the installable package layout so `SKILL.md` is at the skill root instead of a nested `skill_fix/` directory.
- Added uniform YAML frontmatter (scope / status / last_verified) to all 36 reference files.
- Split the original monolithic pitfalls archive into 36 topic-specific `references/` files, removing 23 archived sections that duplicated the standalone references; `references/agent-browser-setup.md` is the surviving standalone piece.
- `SKILL.md`: added Modes (health-check / deep-diag / repair), Prerequisites, Rollback Checklist, and replaced hardcoded runtime version paths with automatic runtime discovery.
- `SKILL.md` Quick Pitfalls: expanded 8 pitfalls with root-cause explanations; "Phase 3 empty output" details the WindowsApps python stub behavior and workarounds.
- `README.md`: added the 环境依赖 section distinguishing required vs optional dependencies, split installation into "find skills directory" (auto-discoverable via the doctor script) and "copy skill" steps, added error-handling guidance with the PyYAML pre-req and version-gate explanation for `apply-weixin-cron-fix.py`, and simplified the quick-start to a no-argument doctor call.
- Replaced detailed reverse-engineering instructions in `references/pyinstaller-pyc-inspection.md` with a security-compliant notice directing users to contact official support, with explicit legal disclaimers.
- Removed references to unavailable external skills (`windows-task-automation`, `windows-native-ocr`); replaced with self-contained guidance in `references/scheduled-automation.md`.
- Removed an out-of-scope third-party integration reference.

### Pre-publication review fixes (2026-09-06)

- Fixed the credential-redaction regex in `hermes-doctor.ps1` so keys with underscore prefixes (`TAVILY_API_KEY`, `OPENAI_API_KEY`, etc.) are masked — the previous `\b`-anchored pattern silently missed them and leaked real secrets in MCP config output.
- Extended the redaction regex to mask JSON-style `"KEY": "value"` pairs (a quote between key and colon previously bypassed matching) — verified against 7 output styles with zero leaks.
- Added `tvly-` to the `env_secrets` audit prefix list so Tavily keys in `config.yaml` are no longer a false negative.
- Added `pip install pyyaml` to the Validate workflow — the CI job crashed on `ModuleNotFoundError` because `validate-repo.py` requires PyYAML.
- Clarified README's `pwsh` vs `powershell` for first-time users (PowerShell 7 vs the built-in 5.1; both entries verified).
- Removed disclosure of the dashboard's internal session-authentication mechanism from four reference files; affected steps now state that authentication is handled by the desktop app and defer to official support. Replaced the email-based contact in `SECURITY.md` with GitHub private vulnerability reporting.
- Slimmed the reference documents: removed debug-log residue (session date stamps, one-off session IDs, personal calibration numbers, user-specific narrative) so the published documents read as reusable procedures rather than private troubleshooting logs.
