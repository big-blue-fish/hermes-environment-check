#!/usr/bin/env pwsh
#Requires -Version 5.1
<#.SYNOPSIS
    Read-only health check for Hermes CN Desktop on Windows.

.DESCRIPTION
    Collects system info, Hermes runtime status, dependencies, configuration,
    DNS/HTTPS network diagnostics, processes, and MCP server status.
    No configuration files are modified.

.PARAMETER HermesHome
    Path to HERMES_HOME. Defaults to the HERMES_HOME environment variable,
    then to "$env:USERPROFILE\.hermes", with automatic CN Desktop discovery.

.PARAMETER OutputPath
    If provided, writes the redacted JSON report to this file.
#>
[CmdletBinding()]
param(
    [string]$HermesHome,
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

function Test-HermesHomeValid {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (Test-Path (Join-Path $Path "config.yaml")) { return $true }
    if (Test-Path (Join-Path $Path ".env")) { return $true }
    foreach ($rel in @("..", "..\..", ".")) {
        if (Test-Path (Join-Path (Join-Path $Path $rel) "data\versions")) { return $true }
    }
    return $false
}

function Resolve-HermesHome {
    param([string]$Explicit)
    $candidates = New-Object System.Collections.ArrayList
    if ($Explicit) { [void]$candidates.Add(@{ Path = $Explicit; Label = "explicit -HermesHome" }) }
    if ($env:HERMES_HOME) { [void]$candidates.Add(@{ Path = $env:HERMES_HOME; Label = "HERMES_HOME env var" }) }
    [void]$candidates.Add(@{ Path = (Join-Path $env:USERPROFILE ".hermes"); Label = "default ~/.hermes" })

    $installDirs = @()
    if ($env:LOCALAPPDATA) {
        $installDirs += (Join-Path $env:LOCALAPPDATA "Programs\Hermes Agent CN Desktop")
        $installDirs += (Join-Path $env:LOCALAPPDATA "Hermes Agent CN Desktop")
    }
    if ($env:ProgramFiles) { $installDirs += (Join-Path $env:ProgramFiles "Hermes Agent CN Desktop") }
    foreach ($driveRoot in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue).Root) {
        $installDirs += (Join-Path $driveRoot "Hermes Agent CN Desktop")
    }
    foreach ($dir in ($installDirs | Select-Object -Unique)) {
        [void]$candidates.Add(@{ Path = (Join-Path $dir "data\hermes-home"); Label = "auto-detected install: $dir" })
    }

    foreach ($c in $candidates) {
        if (Test-HermesHomeValid -Path $c.Path) { return @{ Path = $c.Path; Source = $c.Label } }
    }
    $fallback = if ($Explicit) { $Explicit } elseif ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:USERPROFILE ".hermes" }
    return @{ Path = $fallback; Source = "no valid home found (fallback)" }
}

$resolved = Resolve-HermesHome -Explicit $HermesHome
$HermesHome = $resolved.Path

function Invoke-External {
    param([string]$Command, [string[]]$Arguments, [int]$TimeoutSeconds = 30)
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("hermes-doctor-" + [guid]::NewGuid().ToString("N"))
    $stdoutPath = Join-Path $tempRoot "stdout.txt"
    $stderrPath = Join-Path $tempRoot "stderr.txt"
    try {
        [void](New-Item -ItemType Directory -Path $tempRoot -Force)
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Command
        $psi.Arguments = ($Arguments | ForEach-Object { '"{0}"' -f ($_ -replace '"', '""') }) -join " "
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        # Drain both streams asynchronously so a verbose child cannot deadlock.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch {}
            $proc.WaitForExit()
            return @{ exit_code = -2; timed_out = $true; stdout = $stdoutTask.Result.Trim(); stderr = $stderrTask.Result.Trim() }
        }
        return @{ exit_code = $proc.ExitCode; timed_out = $false; stdout = $stdoutTask.Result.Trim(); stderr = $stderrTask.Result.Trim() }
    } catch {
        return @{ exit_code = -1; timed_out = $false; stdout = ""; stderr = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-CommandVersion {
    param([string]$Name, [string[]]$VersionArgs = @("--version"))
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $cmd) { return @{ installed = $false } }
    $ext = [System.IO.Path]::GetExtension($cmd.Source).ToLower()
    if ($ext -eq ".ps1") {
        $result = Invoke-External -Command "powershell" -Arguments (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cmd.Source) + $VersionArgs)
    } else {
        $result = Invoke-External -Command $cmd.Source -Arguments $VersionArgs
    }
    $firstLine = ($result.stdout -split "`r?`n")[0]
    return @{ installed = ($result.exit_code -eq 0); path = $cmd.Source; version = $firstLine; exit_code = $result.exit_code; timed_out = $result.timed_out }
}

function Find-HermesRuntime {
    param([string]$HomeDir)
    $candidates = @(
        "$HomeDir\..\data\versions\*\hermes-agent-cn-runtime-win32-x64.exe",
        "$HomeDir\..\..\data\versions\*\hermes-agent-cn-runtime-win32-x64.exe",
        "$HomeDir\data\versions\*\hermes-agent-cn-runtime-win32-x64.exe"
    )
    $found = $candidates | ForEach-Object { Get-Item $_ -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) { return @{ found = $false } }
    $version = $found.Directory.Name
    if ($version -notmatch "\d+\.\d+\.\d+") {
        $verResult = Invoke-External -Command $found.FullName -Arguments @("--version")
        if ($verResult.exit_code -eq 0) {
            $m = [regex]::Match($verResult.stdout, "(\d+\.\d+\.\d+(-cn\.\d+)?)")
            if ($m.Success) { $version = $m.Groups[1].Value }
        }
    }
    return @{ found = $true; path = $found.FullName; version = $version }
}

function Redact-SensitiveText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $r = $Text
    $r = [regex]::Replace($r, '(?i)(Authorization\s*[:=]\s*Bearer\s+)[^\s,;"''}]+', '$1[REDACTED]')
    $r = [regex]::Replace($r, '(?i)((?:[A-Za-z0-9]*[_-])?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret|password|passwd|token)\b["'']?\s*[:=]\s*["'']?)[^\s,"'']+', '$1[REDACTED]')
    $r = [regex]::Replace($r, '(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]{12,}', '$1[REDACTED]')
    $r = [regex]::Replace($r, '(?i)([?&](?:key|api_key|apikey|token|access_token|refresh_token|client_secret|password)=)[^&#\s]+', '$1[REDACTED]')
    return $r
}

function Get-HermesCliStatus {
    param([string]$RuntimePath)
    $commands = @(@("--version"), @("doctor"), @("config", "check"), @("status", "--all"))
    $results = [ordered]@{}
    foreach ($parts in $commands) {
        $result = Invoke-External -Command $RuntimePath -Arguments $parts
        $stdout = Redact-SensitiveText $result.stdout
        $stderr = Redact-SensitiveText $result.stderr
        if ($stdout.Length -gt 2000) { $stdout = $stdout.Substring(0, 2000) + "...(truncated)" }
        if ($stderr.Length -gt 1000) { $stderr = $stderr.Substring(0, 1000) + "...(truncated)" }
        $results[($parts -join " ")] = @{ exit_code = $result.exit_code; timed_out = $result.timed_out; stdout = $stdout; stderr = $stderr }
    }
    return $results
}

function Test-HttpsEndpoint {
    param([string]$HostName)
    $result = [ordered]@{ dns = $null; https = $null; status_code = $null; error = $null }
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($HostName)
        $result.dns = ($addresses.Count -gt 0)
    } catch {
        $result.dns = $false
        $result.error = "DNS: " + $_.Exception.Message
        return $result
    }
    try {
        $request = [System.Net.HttpWebRequest]::Create("https://$HostName/")
        $request.Method = "HEAD"
        $request.Timeout = 8000
        $request.ReadWriteTimeout = 8000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = "hermes-environment-check/1.0.0"
        $response = $request.GetResponse()
        $result.https = $true
        $result.status_code = [int]$response.StatusCode
        $response.Close()
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $result.https = $true
            $result.status_code = [int]$_.Exception.Response.StatusCode
            $_.Exception.Response.Close()
        } else {
            $result.https = $false
            $result.error = "HTTPS: " + $_.Exception.Message
        }
    } catch {
        $result.https = $false
        $result.error = "HTTPS: " + $_.Exception.Message
    }
    return $result
}

function Test-NetworkHosts {
    $hosts = @("api.siliconflow.cn", "github.com", "baidu.com")
    $results = [ordered]@{}
    foreach ($h in $hosts) { $results[$h] = Test-HttpsEndpoint -HostName $h }
    return $results
}

function Get-ConfigAudit {
    param([string]$HomeDir)
    $path = Join-Path $HomeDir "config.yaml"
    $audit = @{ exists = Test-Path $path; encoding_utf8 = $null; env_secrets = $null }
    if ($audit.exists) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            $audit.encoding_utf8 = -not $hasBom
        } catch { $audit.encoding_utf8 = $false }
        $text = Get-Content $path -Raw -ErrorAction SilentlyContinue
        $audit.env_secrets = $text -match '(?i)(?:api_key|secret|token|password)\s*:\s*["'']?(?:sk-|ghp_|gho_|AKIA|xox[baprs]-|tvly-)'
    }
    return $audit
}

function Get-McpStatus {
    param([string]$HomeDir, [string]$RuntimePath)
    $logPath = Join-Path $HomeDir "logs\mcp-stderr.log"
    $result = Invoke-External -Command $RuntimePath -Arguments @("config", "get", "mcp_servers")
    $tail = $null
    if (Test-Path $logPath) { $tail = @(Get-Content $logPath -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { Redact-SensitiveText $_ }) }
    return @{ config_exit_code = $result.exit_code; timed_out = $result.timed_out; config_stdout = Redact-SensitiveText $result.stdout; stderr_log_tail = $tail }
}

$report = [ordered]@{
    generated_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    hermes_home = $HermesHome
    hermes_home_source = $resolved.Source
    system = [ordered]@{
        os = (Get-CimInstance Win32_OperatingSystem).Caption
        version = (Get-CimInstance Win32_OperatingSystem).Version
        architecture = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
        powershell = $PSVersionTable.PSVersion.ToString()
        username = $env:USERNAME
    }
    runtime = Find-HermesRuntime -HomeDir $HermesHome
    dependencies = [ordered]@{
        python = Get-CommandVersion -Name "python"
        pip = Get-CommandVersion -Name "pip"
        git = Get-CommandVersion -Name "git"
        node = Get-CommandVersion -Name "node"
        npm = Get-CommandVersion -Name "npm"
        rg = Get-CommandVersion -Name "rg"
        uv = Get-CommandVersion -Name "uv"
        ffmpeg = Get-CommandVersion -Name "ffmpeg" -VersionArgs @("-version")
    }
    hermes_home_check = [ordered]@{
        config_yaml = Test-Path (Join-Path $HermesHome "config.yaml")
        env_file = Test-Path (Join-Path $HermesHome ".env")
        state_db = Test-Path (Join-Path $HermesHome "state.db")
        directories = @(Get-ChildItem $HermesHome -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
    }
    config_audit = Get-ConfigAudit -HomeDir $HermesHome
    network = Test-NetworkHosts
}

if ($report.runtime.found) {
    $report.cli_status = Get-HermesCliStatus -RuntimePath $report.runtime.path
    $report.mcp_status = Get-McpStatus -HomeDir $HermesHome -RuntimePath $report.runtime.path
}

$report.processes = @(Get-Process | Where-Object { $_.ProcessName -match "hermes|gateway" } | Select-Object ProcessName, Id, @{N="WorkingSetMB";E={[math]::Round($_.WorkingSet64/1MB,1)}})
$json = $report | ConvertTo-Json -Depth 6

$privacyNotice = @"
IMPORTANT: This report is redacted for common credential patterns, but it still contains sensitive environment metadata.
Before sharing publicly, review usernames, full paths, hostnames, logs, and any application-specific secrets.
"@

if ($OutputPath) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    Write-Host "Report written to: $OutputPath"
    Write-Host ""
    Write-Host $privacyNotice
} else {
    Write-Host $privacyNotice
    Write-Host ""
    Write-Output $json
}
