[CmdletBinding(SupportsShouldProcess)]
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

function Get-ManifestJson {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $manifestPath = Join-Path $PSScriptRoot "..\$RelativePath"
    if (-not (Test-Path $manifestPath)) {
        throw "Manifest not found: $manifestPath"
    }

    return Get-Content $manifestPath -Raw | ConvertFrom-Json -Depth 10
}

function Get-ScoopCommandPath {
    $scoopCommand = Get-Command scoop.cmd -ErrorAction SilentlyContinue
    if ($null -ne $scoopCommand) {
        return $scoopCommand.Source
    }

    $scoopShim = Get-Command scoop -ErrorAction SilentlyContinue
    if ($null -ne $scoopShim) {
        $shimDirectory = Split-Path -Path $scoopShim.Source -Parent
        $scoopCmdPath = Join-Path $shimDirectory "scoop.cmd"
        if (Test-Path -LiteralPath $scoopCmdPath) {
            return $scoopCmdPath
        }
    }

    throw "Unable to locate scoop.cmd on PATH."
}

function Invoke-ScoopCommand {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    & $script:ScoopCommandPath @Arguments
    if ($LASTEXITCODE -ne 0) {
        $commandText = ($Arguments -join " ")
        throw "Scoop command failed: scoop $commandText"
    }
}

function Get-ScoopInstalledPackages {
    $packages = @{}
    foreach ($entry in (& $script:ScoopCommandPath list 2>$null)) {
        if ($null -eq $entry) { continue }

        if ($entry -is [string]) {
            $trimmed = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -like "Installed apps:*") { continue }
            if ($trimmed -match "^(Name|----)\b") { continue }

            $parts = $trimmed -split "\s+"
            if ($parts.Count -gt 0) {
                $packages[[string]$parts[0]] = $true
            }
            continue
        }

        if ($entry.PSObject.Properties.Name -contains "Name") {
            $packages[[string]$entry.Name] = $true
        }
    }

    return $packages
}

function Get-LegacyScoopPackages {
    $manifest = Get-ManifestJson -RelativePath "manifests/windows.packages.json"
    $legacyPackages = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($sectionName in @("wingetPackages", "fonts")) {
        foreach ($item in @($manifest.$sectionName)) {
            if ($null -eq $item) { continue }
            if (-not ($item.PSObject.Properties.Name -contains "legacyScoopPackage")) { continue }

            $packageName = [string]$item.legacyScoopPackage
            if ([string]::IsNullOrWhiteSpace($packageName)) { continue }

            $key = $packageName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }

            $seen[$key] = $true
            $legacyPackages.Add($packageName) | Out-Null
        }
    }

    return $legacyPackages
}

Write-Step "Loading migrated Scoop package list"
$legacyPackages = @(Get-LegacyScoopPackages)
if ($legacyPackages.Count -eq 0) {
    Write-Info "No migrated Scoop packages are defined in manifests/windows.packages.json."
    return
}

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Info "scoop is not available on PATH. Nothing to remove."
    return
}

$script:ScoopCommandPath = Get-ScoopCommandPath
$installedPackages = Get-ScoopInstalledPackages
$removedPackages = New-Object System.Collections.Generic.List[string]
$plannedPackages = New-Object System.Collections.Generic.List[string]

Write-Step "Removing migrated Scoop packages"
foreach ($packageName in $legacyPackages) {
    if (-not $installedPackages.ContainsKey($packageName)) {
        Write-Info "$packageName is not installed via Scoop"
        continue
    }

    if ($PSCmdlet.ShouldProcess("scoop package '$packageName'", "Uninstall")) {
        Invoke-ScoopCommand -Arguments @("uninstall", $packageName)
        $removedPackages.Add($packageName) | Out-Null
        Write-OK "Removed Scoop package: $packageName"
    }
    elseif ($WhatIfPreference) {
        $plannedPackages.Add($packageName) | Out-Null
    }
}

if ($removedPackages.Count -gt 0) {
    Write-Info ("Removed packages: {0}" -f ($removedPackages -join ", "))
}
elseif ($plannedPackages.Count -gt 0) {
    Write-Info ("Packages that would be removed: {0}" -f ($plannedPackages -join ", "))
}
else {
    Write-Info "No migrated Scoop packages were removed."
}
