<#
.SYNOPSIS
    Web installer for the oh-my-claude status line (PowerShell edition).

.DESCRIPTION
    Downloads the latest theme from GitHub and installs it to
    ~/.claude/oh-my-claude, then points Claude Code's settings.json at
    `oh-my-posh claude`. This is the PowerShell equivalent of install.sh.

.PARAMETER Dir
    Install to a custom directory (default: ~/.claude/oh-my-claude).

.PARAMETER Help
    Show usage information and exit.

.EXAMPLE
    irm https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.ps1 | iex

.EXAMPLE
    # Custom directory (needs the script-block form so the argument binds):
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.ps1))) -Dir "$HOME\.custom\location"
#>
[CmdletBinding()]
param(
    [Alias('d')]
    [string]$Dir,

    [Alias('h')]
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

# --- Constants -------------------------------------------------------------
$GithubRepo        = 'JimiSmith/oh-my-claude'
$Branch            = 'main'
$Theme             = 'claude-native.omp.json'
$DefaultInstallDir = Join-Path $HOME '.claude\oh-my-claude'
$SettingsFile      = Join-Path $HOME '.claude\settings.json'

# Resolved during dependency checking.
$script:OmpBin = $null

# --- Output helpers --------------------------------------------------------
function Write-Ok    { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn  { param([string]$Message) Write-Host "[!] $Message"  -ForegroundColor Yellow }
function Write-Fail  { param([string]$Message) Write-Host "[x] $Message"  -ForegroundColor Red }

function Show-Help {
    @"
oh-my-claude Web Installer (PowerShell)

Usage:
  irm https://raw.githubusercontent.com/$GithubRepo/$Branch/install.ps1 | iex

Options:
  -Dir DIR     Install to a custom directory (default: ~/.claude/oh-my-claude)
  -Help        Show this help message

Examples:
  # Default installation
  irm https://raw.githubusercontent.com/$GithubRepo/$Branch/install.ps1 | iex

  # Custom directory (use the script-block form so -Dir binds)
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/$GithubRepo/$Branch/install.ps1))) -Dir "`$HOME\.custom\location"

Documentation: https://github.com/$GithubRepo
"@ | Write-Host
}

# --- Steps -----------------------------------------------------------------

# Download a single file, retrying with exponential backoff.
function Get-FileWithRetry {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Dest
    )

    $name     = Split-Path $Dest -Leaf
    $attempts = 3

    for ($i = 1; $i -le $attempts; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop
            Write-Ok $name
            return $true
        } catch {
            if ($i -lt $attempts) {
                Write-Warn "$name (retrying... $i/$attempts)"
                Start-Sleep -Seconds ($i * 2)  # Exponential backoff
            }
        }
    }

    Write-Fail "$name (failed after $attempts attempts)"
    return $false
}

# Download every required file from GitHub into $TempDir.
function Invoke-Downloads {
    param([Parameter(Mandatory)][string]$TempDir)

    $baseUrl = "https://raw.githubusercontent.com/$GithubRepo/$Branch"
    $failed  = $false

    Write-Host 'Downloading from GitHub...'

    # The status line is rendered directly by `oh-my-posh claude`, which reads
    # Claude Code's JSON from stdin - so only the theme and VERSION are needed.
    if (-not (Get-FileWithRetry "$baseUrl/src/$Theme" (Join-Path $TempDir $Theme)))    { $failed = $true }
    if (-not (Get-FileWithRetry "$baseUrl/VERSION"    (Join-Path $TempDir 'VERSION'))) { $failed = $true }

    if ($failed) {
        Write-Host ''
        Write-Fail 'Failed to download one or more files'
        Write-Host 'Please check your internet connection and try again.'
        Write-Host ''
        Write-Host 'Alternative: Clone the repository and use local-install.ps1'
        Write-Host "  git clone https://github.com/$GithubRepo.git"
        Write-Host '  cd oh-my-claude'
        Write-Host '  .\local-install.ps1'
        exit 1
    }
}

# Make sure each downloaded file exists and is non-empty.
function Confirm-Downloads {
    param([Parameter(Mandatory)][string]$TempDir)

    foreach ($file in @($Theme, 'VERSION')) {
        $path = Join-Path $TempDir $file
        if (-not (Test-Path $path) -or (Get-Item $path).Length -eq 0) {
            Write-Fail "Downloaded file $file is missing or empty"
            exit 1
        }
    }
}

# Verify required tooling is present. Resolves the oh-my-posh path.
function Test-Dependencies {
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
    $script:OmpBin = $omp.Source

    Write-Ok 'All dependencies found'
    Write-Host ''
}

# Report whether this is a fresh install, reinstall, or upgrade.
function Show-InstallType {
    param(
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$TempDir
    )

    $installedVersionFile = Join-Path $InstallDir 'VERSION'
    $downloadingVersion   = (Get-Content (Join-Path $TempDir 'VERSION') -Raw).Trim()

    if (Test-Path $installedVersionFile) {
        $installedVersion = (Get-Content $installedVersionFile -Raw).Trim()
        if ($installedVersion -eq $downloadingVersion) {
            Write-Host "Reinstalling version $downloadingVersion"
        } else {
            Write-Host "Updating from $installedVersion to $downloadingVersion"
        }
    } else {
        Write-Host "Installing oh-my-claude version $downloadingVersion"
    }
}

# Copy the theme and VERSION into the install directory.
function Install-Files {
    param(
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$TempDir
    )

    Write-Host ''
    Write-Host "Installing to $InstallDir..."

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

    Copy-Item (Join-Path $TempDir $Theme)     (Join-Path $InstallDir $Theme)     -Force
    Copy-Item (Join-Path $TempDir 'VERSION')  (Join-Path $InstallDir 'VERSION')  -Force

    Write-Ok 'Files copied'
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

# Write a string as UTF-8 without a BOM (a BOM breaks Claude Code's JSON parser).
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

# Point Claude Code's settings.json at `oh-my-posh claude`.
function Update-Settings {
    param([Parameter(Mandatory)][string]$InstallDir)

    Write-Host ''
    Write-Host 'Updating settings...'

    $config = Join-Path $InstallDir $Theme
    # Quote both paths: Windows paths can contain spaces.
    $cmd = '"{0}" claude --config "{1}"' -f $script:OmpBin, $config

    if (Test-Path $SettingsFile) {
        # Back up existing settings.
        $stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backupFile = "$SettingsFile.backup.$stamp"
        Copy-Item $SettingsFile $backupFile -Force
        Write-Ok "Backed up settings to $(Split-Path $backupFile -Leaf)"

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

    $json = $settings | ConvertTo-Json -Depth 100
    Write-Utf8NoBom -Path $SettingsFile -Content $json

    Write-Ok 'Configuration updated'
}

# Final summary.
function Show-Success {
    param([Parameter(Mandatory)][string]$InstallDir)

    $versionFile = Join-Path $InstallDir 'VERSION'
    $version = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { 'unknown' }

    Write-Host ''
    Write-Host '================================================'
    Write-Host '   Installation Complete!' -ForegroundColor Green
    Write-Host '================================================'
    Write-Host ''
    Write-Host "Location: $InstallDir"
    Write-Host "Version: $version"
    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  1. Restart Claude Code (if running)'
    Write-Host '  2. Status line will appear automatically'
    Write-Host ''
    Write-Host "Documentation: https://github.com/$GithubRepo"
    Write-Host '================================================'
}

# --- Main ------------------------------------------------------------------
function Invoke-Main {
    if ($Help) {
        Show-Help
        return
    }

    # Resolve the install directory (expand a leading ~ if the user passed one).
    $installDir = if ($Dir) { $Dir -replace '^~', $HOME } else { $DefaultInstallDir }

    Write-Host '================================================'
    Write-Host '   oh-my-claude Web Installer'
    Write-Host '================================================'
    Write-Host ''

    Test-Dependencies

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "oh-my-claude-install-$PID"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    try {
        Invoke-Downloads   -TempDir $tempDir
        Write-Host ''
        Confirm-Downloads  -TempDir $tempDir
        Show-InstallType   -InstallDir $installDir -TempDir $tempDir
        Install-Files      -InstallDir $installDir -TempDir $tempDir
        Update-Settings    -InstallDir $installDir
        Show-Success       -InstallDir $installDir
    } finally {
        # Always remove the temp directory.
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Invoke-Main
