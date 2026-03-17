[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Information "`n=== $Message ===" -InformationAction Continue
}

function Write-OK {
    param([string]$Message)
    Write-Information "  [ok] $Message" -InformationAction Continue
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Write-Info {
    param([string]$Message)
    Write-Information "  [info] $Message" -InformationAction Continue
}

function Set-PathEnvironment {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-MiseShimsPath {
    $miseDataDir = [System.Environment]::GetEnvironmentVariable("MISE_DATA_DIR", "Process")
    if ([string]::IsNullOrWhiteSpace($miseDataDir)) {
        $miseDataDir = [System.Environment]::GetEnvironmentVariable("MISE_DATA_DIR", "User")
    }

    if ([string]::IsNullOrWhiteSpace($miseDataDir)) {
        return ""
    }

    return (Join-Path $miseDataDir "shims")
}

function Test-PathEntryPresent {
    param(
        [Parameter(Mandatory = $true)][string]$PathValue,
        [Parameter(Mandatory = $true)][string]$ExpectedEntry
    )

    $entries = $PathValue -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($entry in $entries) {
        if ($entry.Trim().TrimEnd('\').ToLowerInvariant() -eq $ExpectedEntry.Trim().TrimEnd('\').ToLowerInvariant()) {
            return $true
        }
    }

    return $false
}

Write-Step "Syncing mise tools"

if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    throw "mise is not available on PATH. Install it first, then rerun this script."
}

$miseConfigPath = Join-Path $env:USERPROFILE ".config\mise\config.toml"
if (-not (Test-Path -LiteralPath $miseConfigPath)) {
    throw "Managed mise config not found at $miseConfigPath"
}

$shimsPath = Get-MiseShimsPath
if ([string]::IsNullOrWhiteSpace($shimsPath)) {
    throw "MISE_DATA_DIR is not configured. Run bootstrap.ps1 first so Dev Drive paths are set."
}

if (-not (Test-Path -LiteralPath $shimsPath)) {
    New-Item -ItemType Directory -Path $shimsPath -Force | Out-Null
    Write-OK "Created mise shims directory"
}

& mise install -y
if ($LASTEXITCODE -ne 0) {
    throw "mise install failed"
}
Write-OK "mise tools installed"

& mise reshim
if ($LASTEXITCODE -ne 0) {
    throw "mise reshim failed"
}
Write-OK "mise shims refreshed"

Set-PathEnvironment

if (-not (Test-PathEntryPresent -PathValue $env:Path -ExpectedEntry $shimsPath)) {
    throw "mise shims path is not present on PATH: $shimsPath"
}

$missingRaw = & mise ls --current --missing --json
if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine missing mise tools"
}

$missing = $missingRaw | ConvertFrom-Json
$missingProperties = @($missing.PSObject.Properties)
if ($missingProperties.Count -gt 0) {
    $toolNames = $missingProperties.Name -join ", "
    throw "mise still reports missing current tools: $toolNames"
}

Write-OK "Validated current mise tools"
