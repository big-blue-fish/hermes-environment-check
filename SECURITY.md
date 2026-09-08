# Security Policy

This repository is a Hermes Agent Skill focused on diagnosing and repairing Hermes Agent environments on Windows. It contains diagnostic instructions, configuration repair recipes, and executable helper scripts.

## Reporting security issues

If you discover a security issue involving any of the following, please report it privately rather than opening a public issue or pull request:

- Credential exposure (API keys, tokens, cookies, `.env` contents)
- Unsafe script behavior
- Arbitrary command execution
- Malicious or misleading instructions in the Skill or its references

**Do not include API keys, access tokens, cookies, or private configuration files in reports.**

To report privately, use GitHub's private vulnerability reporting feature (Security → Advisories → Report a vulnerability) on this repository.

## Scope and risks

This Skill intentionally guides an Agent through environment inspection and repair, including:

- Reading Hermes configuration files (`config.yaml`, `.env`, plugins)
- Running diagnostic commands and scripts
- Modifying configuration files after user approval
- Interacting with running processes
- Installing missing dependencies when explicitly requested

The current release does not include the previously removed `scripts/empty-working-sets.ps1`. Do not rely on historical references to that script. The included repair script is version-gated and designed to be reversible. Review the source before execution and use it only on systems you control.

## Safe usage expectations

- Diagnose before modifying.
- Always back up configuration files before editing.
- Never expose credentials in logs, issue reports, or chat output.
- Confirm the target Hermes version before applying version-specific workarounds.
- Do not run scripts blindly; review the source first.

## Security-related configuration

When this Skill is loaded by an Agent, the Agent should follow the Safety Rules in `SKILL.md`:

1. Diagnose before modifying.
2. Never expose or print API keys, cookies, tokens, or `.env` contents.
3. Explain before destructive or system-level changes.
4. Prefer reversible backups before editing configuration.
5. Do not install software unless the user requests repair/install action.
6. Version-specific workarounds must verify the target Hermes version first.
7. After every modification, run a verification step.
