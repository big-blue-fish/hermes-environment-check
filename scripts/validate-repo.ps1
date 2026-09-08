$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$required = @("SKILL.md", "README.md", "LICENSE")

Write-Host "Validating repository: $root"

foreach ($file in $required) {
    $path = Join-Path $root $file
    if (-not (Test-Path $path)) {
        throw "Missing required file: $file"
    }
}

$skill = Get-Content (Join-Path $root "SKILL.md") -Raw

if (-not $skill.StartsWith("---")) {
    throw "SKILL.md does not start with YAML frontmatter."
}

if ($skill -notmatch "(?m)^name\s*:\s*\S+") {
    throw "SKILL.md frontmatter is missing 'name'."
}

if ($skill -notmatch "(?m)^description\s*:\s*(\S.*)") {
    throw "SKILL.md frontmatter is missing 'description'."
}

if ($skill -notmatch "(?m)^version\s*:\s*\S+") {
    throw "SKILL.md frontmatter is missing 'version'."
}

if ($skill -notmatch "(?m)^author\s*:\s*\S+") {
    throw "SKILL.md frontmatter is missing 'author'."
}

if ($skill -notmatch "(?m)^license\s*:\s*\S+") {
    throw "SKILL.md frontmatter is missing 'license'."
}

if ($skill -notmatch "(?m)^platforms\s*:") {
    throw "SKILL.md frontmatter is missing 'platforms'."
}

$references = Join-Path $root "references"
if (Test-Path $references) {
    $refs = Get-ChildItem $references -File
    Write-Host "Reference files: $($refs.Count)"
}

$scripts = Join-Path $root "scripts"
if (Test-Path $scripts) {
    # 8. PowerShell syntax (best effort: pwsh or powershell must be available)
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    $powershell = Get-Command "powershell" -ErrorAction SilentlyContinue
    $shell = if ($pwsh) { $pwsh.Source } elseif ($powershell) { $powershell.Source } else { $null }
    if ($shell) {
        foreach ($ps1 in Get-ChildItem $scripts -Filter *.ps1 -File) {
            $safePath = $ps1.FullName -replace "'", "''"
            $code = "`$e = `$null; [System.Management.Automation.Language.Parser]::ParseFile('$safePath', [ref]`$null, [ref]`$e); if (`$e.Count -gt 0) { exit 1 } else { exit 0 }"
            $result = & $shell -NoProfile -Command $code
            if ($LASTEXITCODE -ne 0) {
                throw "PowerShell syntax errors in $($ps1.Name)."
            }
        }
    } else {
        Write-Warning "Neither pwsh nor powershell found; skipping PowerShell syntax checks."
    }
}

# Basic secret-pattern scan. This validator is a local preflight helper, not a
# complete secret security system. Exclude this script from its own scan so the
# regex definitions themselves do not create false matches.
$patterns = @(
    'AKIA[0-9A-Z]{16}',
    'ghp_[A-Za-z0-9]{20,}',
    'github_pat_[A-Za-z0-9_]{20,}',
    'sk-[A-Za-z0-9]{20,}',
    'xox[baprs]-[A-Za-z0-9-]{10,}',
    '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
)

$validatorName = Split-Path -Leaf $PSCommandPath
$files = Get-ChildItem $root -Recurse -File |
    Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -ne $validatorName }

foreach ($file in $files) {
    $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            throw "Potential secret pattern found in: $($file.FullName)"
        }
    }
}

# Extended validation (reference links, frontmatter, zombie refs, syntax).
$pyValidator = Join-Path (Join-Path $root "scripts") "validate-repo.py"
if (Test-Path $pyValidator) {
    $pyCmd = Get-Command "python" -ErrorAction SilentlyContinue
    $uvCmd = Get-Command "uv" -ErrorAction SilentlyContinue
    $pyExit = 1
    # Prefer uv (real interpreter); skip python.exe if it is the WindowsApps store stub.
    $pyReal = $pyCmd -and $pyCmd.Source -notmatch "WindowsApps|Microsoft\\WindowsApps"
    if ($uvCmd) {
        & $uvCmd.Source run --no-project --with pyyaml python "$pyValidator"
        $pyExit = $LASTEXITCODE
    } elseif ($pyReal) {
        & $pyCmd.Source "$pyValidator"
        $pyExit = $LASTEXITCODE
    } else {
        Write-Warning "Neither a usable python nor uv found; skipping extended checks."
        $pyExit = 0
    }
    if ($pyExit -ne 0) {
        throw "Extended validation failed."
    }
} else {
    Write-Warning "validate-repo.py not found; skipping extended checks."
}

Write-Host "Validation passed."
