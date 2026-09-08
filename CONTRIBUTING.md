# Contributing

Thanks for helping improve `hermes-environment-check`.

## Scope

This repository contains a troubleshooting-oriented Skill and its supporting
reference documents and maintenance scripts. Contributions should improve
diagnostic accuracy, reproducibility, safety, or documentation quality.

## Before opening a pull request

- Keep `SKILL.md` focused on routing, decision logic, and core procedures.
- Put detailed topic-specific material in `references/`.
- Do not commit credentials, access tokens, private URLs, personal paths, or
  machine-specific identifiers.
- Prefer placeholders such as `<username>`, `<path>`, and `<repository-url>`.
- Document potentially privileged or destructive commands.
- Keep Windows-specific behavior explicit where relevant.

## Validation

Run the repository validation script before submitting:

```powershell
pwsh ./scripts/validate-repo.ps1
```

If PowerShell 7 is unavailable, the checks can still be reviewed manually
using the same rules described by the script.

## Pull requests

Explain what changed, why it is needed, and how it was tested. For changes
to diagnostic procedures, include the affected Windows/Hermes environment
and the observed behavior when practical.
