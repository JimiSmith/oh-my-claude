<#
.SYNOPSIS
    Local installer for the oh-my-claude status line (PowerShell edition).

.DESCRIPTION
    For local development - run after cloning the repository. Installs the
    theme from this checkout to ~/.claude/oh-my-claude and points Claude Code's
    settings.json at `oh-my-posh claude`. This is the PowerShell equivalent of
    local-install.sh.

    For web-based installation use:
      irm https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.ps1 | iex
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# --- Output helpers --------------------------------------------------------
function Write-Ok    { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host "[!] $Message"  -ForegroundColor Yellow }
function Write-Fail  { param([string]$Message) Write-Host "[x] $Message"  -ForegroundColor Red }

# Write a string as UTF-8 without a BOM (a BOM breaks Claude Code's JSON parser).
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

# Set (or add) a property on a PSCustomObject, working across PS 5.1 and 7.
function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

# --- Setup -----------------------------------------------------------------
$ScriptDir   = $PSScriptRoot
$Theme       = 'claude-native.omp.json'
$VersionFile = Join-Path $ScriptDir 'VERSION'
$Version     = if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw).Trim() } else { 'unknown' }

$InstallDir   = Join-Path $HOME '.claude\oh-my-claude'
$SettingsFile = Join-Path $HOME '.claude\settings.json'

Write-Host '================================================'
Write-Host '   oh-my-claude Status Line Installation'
Write-Host "   Version: $Version"
Write-Host '================================================'
Write-Host ''

# --- Dependencies ----------------------------------------------------------
Write-Host 'Checking dependencies...'

$omp = Get-Command 'oh-my-posh' -ErrorAction SilentlyContinue
if (-not $omp) {
    Write-Fail 'Missing required dependency:'
    Write-Host '  - oh-my-posh'
    Write-Host ''
    Write-Host 'Install it from https://ohmyposh.dev/docs/installation/windows and try again.'
    exit 1
}

# git is optional - only needed for the git segment of the status line.
if (-not (Get-Command 'git' -ErrorAction SilentlyContinue)) {
    Write-Warn 'git not found - the git segment of the status line will be hidden'
}

# Resolve the full path so the status line command does not depend on PATH.
# (jq is NOT required: settings.json is updated with PowerShell's native JSON cmdlets.)
$OmpBin = $omp.Source

Write-Ok 'All dependencies found'
Write-Host ''

# --- Install files ---------------------------------------------------------
Write-Host 'Creating installation directory...'
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Write-Ok "Created $InstallDir"
Write-Host ''

Write-Host 'Copying theme...'
Copy-Item (Join-Path $ScriptDir "src\$Theme") (Join-Path $InstallDir $Theme)    -Force
Copy-Item $VersionFile                        (Join-Path $InstallDir 'VERSION') -Force
Write-Ok "Copied theme to $InstallDir"
Write-Host ''

# --- Update settings.json --------------------------------------------------
Write-Host 'Updating Claude Code settings...'

$config = Join-Path $InstallDir $Theme
# Quote both paths: Windows paths can contain spaces.
$cmd = '"{0}" claude --config "{1}"' -f $OmpBin, $config

if (Test-Path $SettingsFile) {
    $stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupFile = "$SettingsFile.backup.$stamp"
    Copy-Item $SettingsFile $backupFile -Force
    Write-Ok "Backed up settings to $backupFile"

    try {
        $settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json
    } catch {
        Write-Fail "Could not parse $SettingsFile as JSON"
        Write-Host "Your original file is preserved; the backup is at $backupFile"
        exit 1
    }
    if ($null -eq $settings) { $settings = [pscustomobject]@{} }
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $SettingsFile -Parent) | Out-Null
    $settings = [pscustomobject]@{}
}

# Preserve any existing statusLine sub-keys; override the three we manage.
if ($settings.PSObject.Properties.Name -contains 'statusLine' -and $settings.statusLine) {
    $statusLine = $settings.statusLine
} else {
    $statusLine = [pscustomobject]@{}
}
Set-JsonProperty $statusLine 'type'    'command'
Set-JsonProperty $statusLine 'command' $cmd
Set-JsonProperty $statusLine 'padding' 0
Set-JsonProperty $settings   'statusLine' $statusLine

Write-Utf8NoBom -Path $SettingsFile -Content ($settings | ConvertTo-Json -Depth 100)
Write-Ok 'Updated settings.json with new statusLine.command'
Write-Host ''

# --- Test installation -----------------------------------------------------
Write-Host 'Testing installation...'
$currentDir  = ($PWD.Path -replace '\\', '\\')
$testPayload = '{"model":{"display_name":"Test"},"workspace":{"current_dir":"' + $currentDir + '"},"context_window":{"current_usage":{"input_tokens":1000},"context_window_size":200000}}'
try {
    $testPayload | & $OmpBin claude --config $config 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'Status line renders'
    } else {
        Write-Warn 'Status line render test failed'
    }
} catch {
    Write-Warn 'Status line render test failed'
}
Write-Host ''

# --- Summary ---------------------------------------------------------------
Write-Host '================================================'
Write-Host '   Installation Complete!' -ForegroundColor Green
Write-Host '================================================'
Write-Host ''
Write-Host 'Installation summary:'
Write-Host "  - Theme installed to: $config"
Write-Host "  - Settings updated in: $SettingsFile"
Write-Host ''
Write-Host "The status line is rendered by 'oh-my-posh claude', which reads Claude"
Write-Host "Code's session JSON (model, context, and subscription usage) from stdin."
Write-Host 'No tokens, API calls, or background scripts are involved.'
Write-Host ''
Write-Host 'You can now use Claude Code and see the status line!'
Write-Host ''
Write-Host 'Test the status line with:'
Write-Host "  '{`"model`":{`"display_name`":`"Test`"},`"context_window`":{`"current_usage`":{`"input_tokens`":1000},`"context_window_size`":200000}}' | & '$OmpBin' claude --config '$config'"
Write-Host ''
Write-Host 'Documentation:'
Write-Host '  - README.md - Getting started guide'
Write-Host ''
Write-Host '================================================'
