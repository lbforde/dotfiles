[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Information "`n$($PSStyle.Foreground.Cyan)━━━ $Message ━━━$($PSStyle.Reset)" -InformationAction Continue
}

function Write-OK {
    param([string]$Message)
    Write-Information "  $($PSStyle.Foreground.Green)✓ $Message$($PSStyle.Reset)" -InformationAction Continue
}

function Write-Warn {
    param([string]$Message)
    Write-Warning "$($PSStyle.Foreground.Yellow)⚠ $Message$($PSStyle.Reset)"
}

function Write-Info {
    param([string]$Message)
    Write-Information "  $($PSStyle.Foreground.DarkGray)🛈 $Message$($PSStyle.Reset)" -InformationAction Continue
}

function Get-ScoopInstalledPackages {
    $packages = @{}
    foreach ($entry in (scoop list)) {
        if ($null -eq $entry) { continue }

        if ($entry -is [string]) {
            $trimmed = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -like "Installed apps:*") { continue }
            if ($trimmed -match "^(Name|----)\b") { continue }
            $parts = $trimmed -split "\s+"
            if ($parts.Count -gt 0) {
                $packages[$parts[0]] = $true
            }
            continue
        }

        if ($entry.PSObject.Properties.Name -contains "Name") {
            $packages[[string]$entry.Name] = $true
        }
    }

    return $packages
}

function Test-ScoopBucketUnused {
    param([Parameter(Mandatory = $true)][string]$BucketName)

    foreach ($entry in (scoop list)) {
        if ($null -eq $entry) { continue }

        $source = ""
        if ($entry -is [string]) {
            $trimmed = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed -like "Installed apps:*") { continue }
            if ($trimmed -match "^(Name|----)\b") { continue }
            $parts = $trimmed -split "\s+"
            if ($parts.Count -ge 3) {
                $source = $parts[2]
            }
        }
        elseif ($entry.PSObject.Properties.Name -contains "Source") {
            $source = [string]$entry.Source
        }

        if ($source -eq $BucketName) {
            return $false
        }
    }

    return $true
}

function Test-MiseToolReady {
    param(
        [Parameter(Mandatory = $true)][string]$ToolName,
        [Parameter(Mandatory = $true)][string]$CommandName
    )

    $currentRaw = & mise ls --current --json
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query current mise tools"
    }

    $current = $currentRaw | ConvertFrom-Json
    $toolProperty = $current.PSObject.Properties[$ToolName]
    if ($null -eq $toolProperty) {
        return $false
    }

    $toolEntries = @($toolProperty.Value)
    if ($toolEntries.Count -eq 0 -or (-not $toolEntries[0].installed)) {
        return $false
    }

    $resolvedPath = (& mise which $CommandName 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($resolvedPath)) {
        return $false
    }

    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

function Test-ScoopBucketPresent {
    param([Parameter(Mandatory = $true)][string]$BucketName)

    try {
        $bucketLines = scoop bucket list 2>$null
    }
    catch {
        return $false
    }

    foreach ($entry in $bucketLines) {
        if ($null -eq $entry) { continue }

        $name = ""
        if ($entry -is [string]) {
            $trimmed = $entry.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($trimmed -match "^(Name|----)\b") { continue }
            $parts = $trimmed -split "\s+"
            if ($parts.Count -gt 0) {
                $name = $parts[0]
            }
        }
        elseif ($entry.PSObject.Properties.Name -contains "Name") {
            $name = [string]$entry.Name
        }

        if ($name -eq $BucketName) {
            return $true
        }
    }

    return $false
}

if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    throw "scoop is not available on PATH. There is nothing to clean up."
}

if (-not (Get-Command mise -ErrorAction SilentlyContinue)) {
    throw "mise is not available on PATH. Run bootstrap.ps1 first so migrated tools are installed."
}

$migrationMap = @(
    @{ Scoop = "bat"; Tool = "bat"; Command = "bat" },
    @{ Scoop = "chezmoi"; Tool = "chezmoi"; Command = "chezmoi" },
    @{ Scoop = "cmake"; Tool = "cmake"; Command = "cmake" },
    @{ Scoop = "croc"; Tool = "croc"; Command = "croc" },
    @{ Scoop = "eza"; Tool = "eza"; Command = "eza" },
    @{ Scoop = "fd"; Tool = "fd"; Command = "fd" },
    @{ Scoop = "fzf"; Tool = "fzf"; Command = "fzf" },
    @{ Scoop = "gh"; Tool = "gh"; Command = "gh" },
    @{ Scoop = "gopass"; Tool = "gopass"; Command = "gopass" },
    @{ Scoop = "grex"; Tool = "grex"; Command = "grex" },
    @{ Scoop = "jq"; Tool = "jq"; Command = "jq" },
    @{ Scoop = "lazygit"; Tool = "lazygit"; Command = "lazygit" },
    @{ Scoop = "ripgrep"; Tool = "ripgrep"; Command = "rg" },
    @{ Scoop = "starship"; Tool = "starship"; Command = "starship" },
    @{ Scoop = "yazi"; Tool = "yazi"; Command = "yazi" },
    @{ Scoop = "zoxide"; Tool = "zoxide"; Command = "zoxide" },
    @{ Scoop = "doppler"; Tool = "doppler"; Command = "doppler" }
)

$installedPackages = Get-ScoopInstalledPackages
$removed = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

Write-Step "Removing migrated Scoop packages"

foreach ($item in $migrationMap) {
    if (-not $installedPackages.ContainsKey($item.Scoop)) {
        continue
    }

    if (-not (Test-MiseToolReady -ToolName $item.Tool -CommandName $item.Command)) {
        $message = "$($item.Scoop) is still installed via Scoop and was skipped because the mise-managed replacement is not ready."
        Write-Warn $message
        $skipped.Add($item.Scoop) | Out-Null
        continue
    }

    if ($PSCmdlet.ShouldProcess("scoop package '$($item.Scoop)'", "Uninstall")) {
        scoop uninstall $item.Scoop
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to uninstall Scoop package: $($item.Scoop)"
        }
        Write-OK "Removed Scoop package: $($item.Scoop)"
        $removed.Add($item.Scoop) | Out-Null
    }
}

Write-Step "Removing unused managed buckets"

$bucketNames = @("doppler", "versions")
foreach ($bucketName in $bucketNames) {
    if (-not (Test-ScoopBucketPresent -BucketName $bucketName)) {
        continue
    }

    if (-not (Test-ScoopBucketUnused -BucketName $bucketName)) {
        Write-Info "Keeping Scoop bucket '$bucketName' because installed packages still reference it."
        continue
    }

    if ($PSCmdlet.ShouldProcess("scoop bucket '$bucketName'", "Remove")) {
        scoop bucket rm $bucketName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to remove Scoop bucket: $bucketName"
        }
        Write-OK "Removed Scoop bucket: $bucketName"
    }
}

if ($removed.Count -eq 0) {
    Write-Info "No migrated Scoop packages were removed."
}
else {
    Write-Info ("Removed packages: {0}" -f ($removed -join ", "))
}

if ($skipped.Count -gt 0) {
    Write-Warn ("Skipped packages: {0}" -f ($skipped -join ", "))
}
