#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Developer Environment Bootstrap Script
.DESCRIPTION
    Installs and configures a full developer environment using Scoop, Winget,
    and all associated tools. Run once as Administrator to get started.
.NOTES
    Run with: Set-ExecutionPolicy Bypass -Scope Process -Force; .\bootstrap.ps1
#>

param(
    [switch]$SkipFonts,
    [switch]$SkipChezmoi,
    [string]$ChezmoiRepo = "",   # e.g. "https://github.com/yourname/dotfiles"
    [string]$DevDrive = ""    # leave blank to be prompted; or pass e.g. "D:" to skip prompt
)

$ErrorActionPreference = "Stop"

# ─── Helpers ─────────────────────────────────────────────────────────────────

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

function Test-CommandAvailable {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Set-PathEnvironment {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Reload PATH from the registry so tools installed earlier in this session are immediately usable
    if ($PSCmdlet.ShouldProcess("PATH environment", "Refresh from machine and user registry values")) {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Info "⟳ PATH refreshed"
    }
}

function ConvertTo-NormalizedPathEntry {
    param([string]$PathEntry)

    if ([string]::IsNullOrWhiteSpace($PathEntry)) { return "" }
    return $PathEntry.Trim().TrimEnd('\')
}

function Get-ManifestJson {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    # Resolve manifest path from repo root (script lives in scripts/)
    $manifestPath = Join-Path $PSScriptRoot "..\$RelativePath"
    if (-not (Test-Path $manifestPath)) {
        throw "Manifest not found: $manifestPath"
    }

    return Get-Content $manifestPath -Raw | ConvertFrom-Json -Depth 10
}

function Install-ScoopApp {
    param([string]$App, [string]$Bucket = "main")

    # Use bucket-qualified names for non-main buckets so installs are explicit.
    $packageRef = if ($Bucket -and $Bucket -ne "main") { "$Bucket/$App" } else { $App }

    if (-not (scoop info $packageRef 2>&1 | Select-String "Installed")) {
        Write-Info "Installing $packageRef..."
        scoop install $packageRef
        Write-OK "$App installed"
    }
    else {
        Write-OK "$App already installed"
    }
}

function Get-MiseRuntimeCommand {
    param([Parameter(Mandatory = $true)][string]$RuntimeSpec)

    $runtimeName = ($RuntimeSpec -split "@")[0].ToLowerInvariant()
    switch ($runtimeName) {
        "rust" { return "rustc" }
        "python" { return "python" }
        default { return $runtimeName }
    }
}

function Test-MiseRuntimeInstalled {
    param([Parameter(Mandatory = $true)][string]$RuntimeSpec)

    try {
        $null = (& mise where $RuntimeSpec 2>$null | Out-String).Trim()
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Install-MiseRuntime {
    param([Parameter(Mandatory = $true)][string]$RuntimeSpec)

    if (Test-MiseRuntimeInstalled -RuntimeSpec $RuntimeSpec) {
        Write-OK "$RuntimeSpec already installed"
        return
    }

    Write-Info "Installing $RuntimeSpec..."
    $output = (& mise use --global $RuntimeSpec 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $RuntimeSpec via mise. Output: $output"
    }

    Write-OK "$RuntimeSpec installed"
}

function Test-MiseRuntimeCommandAvailability {
    param([Parameter(Mandatory = $true)][string[]]$RuntimeSpecs)

    $missing = @()
    foreach ($runtime in $RuntimeSpecs) {
        $command = Get-MiseRuntimeCommand -RuntimeSpec $runtime
        if (-not (Test-CommandAvailable $command)) {
            $resolvedPath = ""
            try {
                $resolvedPath = (& mise which $command 2>$null | Out-String).Trim()
            }
            catch {
                $resolvedPath = ""
            }

            $missing += [PSCustomObject]@{
                Runtime      = $runtime
                Command      = $command
                MiseResolved = if ($resolvedPath) { $resolvedPath } else { "<not found by mise which>" }
            }
        }
    }

    if ($missing.Count -gt 0) {
        Write-Warn "mise runtime validation failed. Commands missing from PATH:"
        foreach ($item in $missing) {
            Write-Warn "  runtime=$($item.Runtime) command=$($item.Command) miseWhich=$($item.MiseResolved)"
        }
        throw "Runtime validation failed. Ensure MISE_DATA_DIR shims are on PATH, then run 'mise reshim'."
    }

    Write-OK "Validated runtime commands on PATH"
}

function Get-ChezmoiSourcePath {
    # Returns empty string when chezmoi has not been initialised yet.
    if (-not (Test-CommandAvailable "chezmoi")) { return "" }

    try {
        $source = (& chezmoi source-path 2>$null | Out-String).Trim()
        return $source
    }
    catch {
        return ""
    }
}

function Get-ChezmoiRemoteOrigin {
    # Returns origin URL from chezmoi source repo when available.
    if (-not (Test-CommandAvailable "chezmoi")) { return "" }

    try {
        $origin = (& chezmoi git -- remote get-url origin 2>$null | Out-String).Trim()
        return $origin
    }
    catch {
        return ""
    }
}

function Test-ChezmoiManagedFilePresent {
    # Returns true when chezmoi currently has at least one managed target.
    if (-not (Test-CommandAvailable "chezmoi")) { return $false }

    try {
        $managed = (& chezmoi managed 2>$null | Out-String).Trim()
        return -not [string]::IsNullOrWhiteSpace($managed)
    }
    catch {
        return $false
    }
}

function Test-ScoopBucketPresent {
    param([Parameter(Mandatory = $true)][string]$BucketName)

    if (-not (Test-CommandAvailable "scoop")) { return $false }

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
        else {
            $name = [string]$entry
        }

        if ($name -eq $BucketName) {
            return $true
        }
    }

    return $false
}

function Get-ChezmoiSourceRootPath {
    param([string]$SourcePath)

    if ([string]::IsNullOrWhiteSpace($SourcePath)) { return "" }

    try {
        $resolvedSourcePath = (Resolve-Path $SourcePath -ErrorAction Stop).Path
    }
    catch {
        $resolvedSourcePath = $SourcePath
    }

    $sourceParent = Split-Path $resolvedSourcePath -Parent
    if (-not [string]::IsNullOrWhiteSpace($sourceParent)) {
        $parentRootMarker = Join-Path $sourceParent ".chezmoiroot"
        if (Test-Path $parentRootMarker) {
            $rootDirName = (Get-Content $parentRootMarker -Raw -ErrorAction SilentlyContinue).Trim()
            if (-not [string]::IsNullOrWhiteSpace($rootDirName)) {
                $sourceLeaf = Split-Path $resolvedSourcePath -Leaf
                if ($sourceLeaf -eq $rootDirName) {
                    try {
                        return (Resolve-Path $sourceParent -ErrorAction Stop).Path
                    }
                    catch {
                        return $sourceParent
                    }
                }
            }
        }
    }

    return $resolvedSourcePath
}

function Get-DefaultChezmoiSourceRoot {
    $defaultRoot = Join-Path $env:USERPROFILE ".local\share\chezmoi"
    try {
        return (Resolve-Path $defaultRoot -ErrorAction Stop).Path
    }
    catch {
        return $defaultRoot
    }
}

function Backup-ChezmoiSourceRoot {
    param([Parameter(Mandatory = $true)][string]$SourceRoot)

    if (-not (Test-Path $SourceRoot)) {
        Write-Warn "Chezmoi source backup skipped; source root not found: $SourceRoot"
        return ""
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$SourceRoot.backup-$timestamp"
    Copy-Item -Path $SourceRoot -Destination $backupPath -Recurse -Force
    Write-OK "Backed up current chezmoi source to $backupPath"
    return $backupPath
}

function Set-LocalChezmoiSourceDir {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory = $true)][string]$SourceDir)

    $chezmoiConfigDir = Join-Path $env:USERPROFILE ".config\chezmoi"
    $chezmoiConfigPath = Join-Path $chezmoiConfigDir "chezmoi.toml"

    if (-not (Test-Path $chezmoiConfigPath)) {
        throw "Local chezmoi config not found at $chezmoiConfigPath"
    }

    $content = Get-Content $chezmoiConfigPath -Raw -ErrorAction Stop
    $normalizedSource = $SourceDir -replace "\\", "/"
    $escapedSource = $normalizedSource.Replace('"', '\"')
    $line = "sourceDir = `"$escapedSource`""
    $changed = $false
    $updated = $content

    # Remove legacy section-scoped sourceDir values written by older bootstrap logic.
    if ($updated -match "(?ms)^\[chezmoi\][\s\S]*?(?=^\[|\z)") {
        $updated = [regex]::Replace(
            $updated,
            "(?ms)^(\[chezmoi\][\s\S]*?)(?=^\[|\z)",
            {
                param($m)
                $section = $m.Groups[1].Value
                $cleaned = [regex]::Replace($section, "(?m)^\s*sourceDir\s*=.*(?:\r?\n)?", "")
                return $cleaned
            }
        )
        if ($updated -ne $content) {
            $changed = $true
        }
    }

    # sourceDir must be top-level. Insert/update it before the first table header.
    if ($updated -match "(?m)^sourceDir\s*=") {
        $replaced = [regex]::Replace($updated, "(?m)^sourceDir\s*=.*$", $line)
        if ($replaced -ne $updated) {
            $updated = $replaced
            $changed = $true
        }
    }
    else {
        $firstTableMatch = [regex]::Match($updated, "(?m)^\[")
        if ($firstTableMatch.Success) {
            $updated = $updated.Insert($firstTableMatch.Index, "$line`n`n")
        }
        else {
            $trimmed = $updated.TrimEnd("`r", "`n")
            $updated = if ([string]::IsNullOrWhiteSpace($trimmed)) { "$line`n" } else { "$line`n`n$trimmed`n" }
        }
        $changed = $true
    }

    if ($changed) {
        if ($PSCmdlet.ShouldProcess($chezmoiConfigPath, "Set chezmoi sourceDir to $SourceDir")) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$chezmoiConfigPath.$timestamp.bak"
            Copy-Item -Path $chezmoiConfigPath -Destination $backupPath -Force
            $updated | Set-Content -Path $chezmoiConfigPath -Encoding UTF8
            Write-OK "Set local chezmoi sourceDir to $SourceDir (backup: $backupPath)"
        }
    }
    else {
        Write-OK "Local chezmoi sourceDir already set to $SourceDir"
    }
}

function Get-ExpectedPowerShellProfilePath {
    # Resolve the real PowerShell user profile target, including known-folder redirection.
    if (Test-CommandAvailable "pwsh") {
        try {
            $profilePath = (& pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts' 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
                return $profilePath
            }
        }
        catch {
            Write-Verbose "Falling back to MyDocuments because pwsh profile lookup failed: $($_.Exception.Message)"
        }
    }

    $documentsDir = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($documentsDir)) {
        $documentsDir = Join-Path $env:USERPROFILE "Documents"
    }

    return (Join-Path $documentsDir "PowerShell\profile.ps1")
}

function Sync-PowerShellProfileBridge {
    # Chezmoi manages home/Documents/PowerShell/profile.ps1, but Windows can redirect Documents.
    # Create a tiny bridge profile in the redirected location that dot-sources the managed profile.
    $sourceCandidates = @(
        (Join-Path $env:USERPROFILE "Documents\PowerShell\profile.ps1"),
        (Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "home\Documents\PowerShell\profile.ps1")
    )

    $chezmoiSourcePath = Get-ChezmoiSourcePath
    if (-not [string]::IsNullOrWhiteSpace($chezmoiSourcePath)) {
        $sourceCandidates += (Join-Path $chezmoiSourcePath "Documents\PowerShell\profile.ps1")
    }

    $managedProfilePath = $sourceCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($managedProfilePath)) {
        Write-Warn "Managed profile source not found; checked:"
        foreach ($candidate in $sourceCandidates | Select-Object -Unique) {
            Write-Warn "  $candidate"
        }
        Write-Warn "Skipping redirected profile bridge setup."
        return
    }

    $expectedProfilePath = Get-ExpectedPowerShellProfilePath
    if ([string]::IsNullOrWhiteSpace($expectedProfilePath)) {
        Write-Warn "Could not resolve PowerShell profile target path; skipping redirected profile bridge setup."
        return
    }

    $managedResolved = (Resolve-Path $managedProfilePath).Path
    try {
        $expectedResolved = (Resolve-Path $expectedProfilePath -ErrorAction Stop).Path
    }
    catch {
        $expectedResolved = $expectedProfilePath
    }

    if ($managedResolved -eq $expectedResolved) {
        Write-OK "PowerShell profile path is not redirected"
        return
    }

    $expectedDir = Split-Path $expectedProfilePath -Parent
    if (-not (Test-Path $expectedDir)) {
        New-Item -ItemType Directory -Path $expectedDir -Force | Out-Null
    }

    $bridgeMarker = "# Managed by bootstrap.ps1. Do not edit directly."
    $managedLiteralPath = $managedResolved.Replace("'", "''")
    $bridgeContent = @"
$bridgeMarker
# This bridge keeps redirected Documents profile paths in sync with chezmoi-managed content.
`$managedProfilePath = '$managedLiteralPath'
if (Test-Path -LiteralPath `$managedProfilePath) {
    . `$managedProfilePath
}
else {
    Write-Warning "Managed PowerShell profile not found at `$managedProfilePath"
}
"@
    $bridgeHash = (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($bridgeContent))) -Algorithm SHA256).Hash

    $expectedContent = if (Test-Path $expectedProfilePath) { Get-Content $expectedProfilePath -Raw -ErrorAction SilentlyContinue } else { "" }
    $expectedHash = if ($expectedContent) {
        (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($expectedContent))) -Algorithm SHA256).Hash
    }
    else {
        ""
    }

    if ($bridgeHash -eq $expectedHash) {
        Write-OK "PowerShell profile bridge already configured: $expectedProfilePath"
        return
    }

    $hasExpectedProfile = Test-Path $expectedProfilePath
    $isBootstrapManagedProfile = $hasExpectedProfile -and $expectedContent.Contains($bridgeMarker)
    if ($hasExpectedProfile -and (-not $isBootstrapManagedProfile)) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$expectedProfilePath.$timestamp.bak"
        Copy-Item -Path $expectedProfilePath -Destination $backupPath -Force
        Write-OK "Backed up existing redirected PowerShell profile to $backupPath"
    }

    Set-Content -Path $expectedProfilePath -Value $bridgeContent -Encoding UTF8
    Write-OK "Configured PowerShell profile bridge at redirected path: $expectedProfilePath"
}

function Update-TomlSectionContent {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][string[]]$Lines,
        [Parameter(Mandatory = $true)][ref]$Changed
    )

    $sectionHeader = "[{0}]" -f $Section
    $sectionBody = ($Lines | ForEach-Object { "    $_" }) -join "`n"
    $replacement = "$sectionHeader`n$sectionBody`n"
    $pattern = "(?ms)^\[" + [regex]::Escape($Section) + "\][\s\S]*?(?=^\[|\z)"

    if ([regex]::IsMatch($Content, $pattern)) {
        $updated = [regex]::Replace($Content, $pattern, $replacement)
        if ($updated -ne $Content) {
            $Changed.Value = $true
        }
        return $updated
    }

    $trimmed = $Content.TrimEnd("`r", "`n")
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        $updated = $replacement
    }
    else {
        $updated = "$trimmed`n`n$replacement"
    }

    $Changed.Value = $true
    return $updated
}

function Update-LocalChezmoiEditorConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) { return }

    $content = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Write-Warn "Could not read local chezmoi config for editor migration: $ConfigPath"
        return
    }

    $changed = $false
    $content = Update-TomlSectionContent -Content $content -Section "edit" -Lines @(
        'command = "code"',
        'args    = ["--wait"]'
    ) -Changed ([ref]$changed)
    $content = Update-TomlSectionContent -Content $content -Section "merge" -Lines @(
        'command = "code"',
        'args    = ["--wait", "--merge", "{{ .Destination }}", "{{ .Source }}", "{{ .Base }}", "{{ .Destination }}"]'
    ) -Changed ([ref]$changed)
    $content = Update-TomlSectionContent -Content $content -Section "diff" -Lines @(
        'command = "code"',
        'args    = ["--wait", "--diff", "{{ .Destination }}", "{{ .Target }}"]'
    ) -Changed ([ref]$changed)

    if (-not $changed) {
        Write-OK "Local chezmoi editor settings already use VS Code"
        return
    }

    if ($PSCmdlet.ShouldProcess($ConfigPath, "Update chezmoi editor settings to VS Code")) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$ConfigPath.$timestamp.bak"
        Copy-Item -Path $ConfigPath -Destination $backupPath -Force
        $content | Set-Content -Path $ConfigPath -Encoding UTF8
        Write-OK "Migrated local chezmoi editor settings to VS Code (backup: $backupPath)"
    }
}

function Initialize-LocalChezmoiConfig {
    # ~/.config/chezmoi/chezmoi.toml is machine-local state and is never managed by source-state.
    $chezmoiConfigDir = Join-Path $env:USERPROFILE ".config\chezmoi"
    $chezmoiConfigPath = Join-Path $chezmoiConfigDir "chezmoi.toml"

    if (Test-Path $chezmoiConfigPath) {
        $existing = Get-Content $chezmoiConfigPath -Raw -ErrorAction SilentlyContinue
        if ($existing -match "Your Name|your@email.com") {
            Write-Warn "Local chezmoi config still has placeholder identity values: $chezmoiConfigPath"
        }
        else {
            Write-OK "Local chezmoi config already present"
        }
        Update-LocalChezmoiEditorConfig -ConfigPath $chezmoiConfigPath
        return
    }

    Write-Info "No local chezmoi config found. Enter machine-specific identity values."

    $defaultName = (git config --global user.name 2>$null | Out-String).Trim()
    $defaultEmail = (git config --global user.email 2>$null | Out-String).Trim()

    do {
        $namePrompt = if ($defaultName) { "  Git user.name [$defaultName]" } else { "  Git user.name" }
        $name = Read-Host $namePrompt
        if (-not $name -and $defaultName) { $name = $defaultName }
    } while ([string]::IsNullOrWhiteSpace($name))

    do {
        $emailPrompt = if ($defaultEmail) { "  Git user.email [$defaultEmail]" } else { "  Git user.email" }
        $email = Read-Host $emailPrompt
        if (-not $email -and $defaultEmail) { $email = $defaultEmail }
    } while ([string]::IsNullOrWhiteSpace($email))

    New-Item -ItemType Directory -Path $chezmoiConfigDir -Force | Out-Null

    @"
# Local Chezmoi runtime config (machine-specific)
[data]
    name  = "$name"
    email = "$email"

[edit]
    command = "code"
    args    = ["--wait"]

[merge]
    command = "code"
    args    = ["--wait", "--merge", "{{ .Destination }}", "{{ .Source }}", "{{ .Base }}", "{{ .Destination }}"]

[diff]
    command = "code"
    args    = ["--wait", "--diff", "{{ .Destination }}", "{{ .Target }}"]

[git]
    autoCommit = false
    autoPush   = false

[template]
    # Valid options are default/invalid, zero, or error.
    options = ["missingkey=default"]
"@ | Set-Content -Path $chezmoiConfigPath -Encoding UTF8

    Write-OK "Created local chezmoi config at $chezmoiConfigPath"
}

function Resolve-DesiredChezmoiSource {
    if ($ChezmoiRepo -ne "") { return $ChezmoiRepo }

    # Default source is this checked-out repo (script lives under scripts/).
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Invoke-ChezmoiApply {
    param([Parameter(Mandatory = $true)][string]$DesiredSource)

    if (-not (Test-CommandAvailable "chezmoi")) {
        Write-Warn "chezmoi is not available on PATH — skipping dotfile apply."
        return
    }

    $desiredIsRemote = $DesiredSource -match '^(https?|ssh)://|^git@'

    if (-not $desiredIsRemote) {
        $desiredPath = (Resolve-Path $DesiredSource -ErrorAction Stop).Path

        $currentSource = Get-ChezmoiSourcePath
        $currentSourceRoot = Get-ChezmoiSourceRootPath -SourcePath $currentSource
        $defaultSourceRoot = Get-DefaultChezmoiSourceRoot
        $hasManagedFiles = Test-ChezmoiManagedFilePresent

        Write-Info "Chezmoi source mode: direct-path"
        Write-Info "Desired source root: $desiredPath"

        if ($hasManagedFiles -and $currentSourceRoot -and ($currentSourceRoot -ne $desiredPath) -and ($currentSourceRoot -eq $defaultSourceRoot)) {
            Backup-ChezmoiSourceRoot -SourceRoot $currentSourceRoot | Out-Null
        }
        elseif ($hasManagedFiles -and $currentSourceRoot -and ($currentSourceRoot -ne $desiredPath) -and ($currentSourceRoot -ne $defaultSourceRoot)) {
            Write-Warn "Chezmoi source is already direct-path from a different local path."
            Write-Warn "Current source root: $currentSourceRoot"
            Write-Warn "Desired source root: $desiredPath"
            Write-Warn "Keeping existing source and applying current state."
            chezmoi apply
            Write-OK "Chezmoi apply complete"
            $finalSourcePath = Get-ChezmoiSourcePath
            Write-Info "Final chezmoi source-path: $finalSourcePath"
            return
        }

        Set-LocalChezmoiSourceDir -SourceDir $desiredPath

        try {
            chezmoi apply
            $finalSourcePath = Get-ChezmoiSourcePath
            Write-OK "Chezmoi apply complete"
            Write-Info "Final chezmoi source-path: $finalSourcePath"
        }
        catch {
            throw "Chezmoi apply failed after switching sourceDir to '$desiredPath'. Restore from backup or rerun with -ChezmoiRepo. Error: $($_.Exception.Message)"
        }

        return
    }

    $currentSource = Get-ChezmoiSourcePath
    $hasManagedFiles = Test-ChezmoiManagedFilePresent

    # Treat "source exists but manages nothing" as effectively uninitialised.
    if ((-not $currentSource) -or (-not $hasManagedFiles)) {
        chezmoi init --apply $DesiredSource
        Write-OK "Chezmoi initialised and applied from $DesiredSource"
        return
    }

    if ($desiredIsRemote) {
        $currentOrigin = Get-ChezmoiRemoteOrigin
        if ($currentOrigin -and ($currentOrigin -ne $DesiredSource)) {
            Write-Warn "Chezmoi source is already initialised from a different origin."
            Write-Warn "Current origin: $currentOrigin"
            Write-Warn "Desired origin: $DesiredSource"
            Write-Warn "Keeping existing source and applying current state."
        }
        elseif (-not $currentOrigin) {
            Write-Warn "Could not determine current chezmoi origin; keeping existing source and applying current state."
        }
    }
    chezmoi apply
    Write-OK "Chezmoi apply complete"
}

# ─── Manifest Data ───────────────────────────────────────────────────────────

# Keep package/runtime inventories in JSON so this script stays logic-focused.
$windowsPackages = Get-ManifestJson "manifests\windows.packages.json"

# ─── Execution Policy ────────────────────────────────────────────────────────

Write-Step "Configuring Execution Policy"
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    Write-OK "Execution policy set to RemoteSigned"
}
catch {
    Write-Warn "Could not set CurrentUser execution policy (likely overridden by Process/Group Policy). Continuing."
    Write-Info "Effective policy: $(Get-ExecutionPolicy)"
}

# NuGet is required for Install-Module to work without prompting on a fresh machine
Write-Step "Checking NuGet Provider"
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
    Write-OK "NuGet provider installed"
}
else {
    Write-OK "NuGet provider already present"
}

# ─── Scoop ───────────────────────────────────────────────────────────────────

Write-Step "Installing Scoop"
if (-not (Test-CommandAvailable "scoop")) {
    $scoopInstallerPath = Join-Path $env:TEMP "install-scoop.ps1"
    Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $scoopInstallerPath -ErrorAction Stop
    try {
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $scoopInstallerPath
    }
    finally {
        Remove-Item -Path $scoopInstallerPath -Force -ErrorAction SilentlyContinue
    }
    Set-PathEnvironment
    Write-OK "Scoop installed"
}
else {
    Write-OK "Scoop already installed"
}

# Add buckets
Write-Step "Configuring Scoop Buckets"
$buckets = @($windowsPackages.scoopBuckets)
foreach ($bucket in $buckets) {
    $bucketName = $bucket.name
    if (-not (Test-ScoopBucketPresent -BucketName $bucketName)) {
        if ($bucket.PSObject.Properties.Name -contains "url" -and $bucket.url) {
            scoop bucket add $bucketName $bucket.url
        }
        else {
            scoop bucket add $bucketName
        }
        Write-OK "Added bucket: $bucketName"
    }
    else {
        Write-OK "Bucket already added: $bucketName"
    }
}

# ─── Git (needed early for chezmoi etc.) ─────────────────────────────────────

Write-Step "Installing Git"
Install-ScoopApp "git"
# Ensure long paths are enabled for Windows
git config --system core.longpaths true 2>$null

# ─── PowerShell 7 ────────────────────────────────────────────────────────────

Write-Step "Installing PowerShell 7"
if (-not (Test-CommandAvailable "pwsh")) {
    # Winget IDs are manifest-driven so package choices stay in one place.
    $pwshWinget = $windowsPackages.wingetPackages | Where-Object { $_.id -eq "Microsoft.PowerShell" } | Select-Object -First 1
    $pwshWingetId = if ($pwshWinget) { $pwshWinget.id } else { "Microsoft.PowerShell" }
    $pwshWingetSource = if ($pwshWinget -and $pwshWinget.source) { $pwshWinget.source } else { "winget" }

    winget install --id $pwshWingetId --source $pwshWingetSource --accept-source-agreements --accept-package-agreements --silent
    Set-PathEnvironment
    Write-OK "PowerShell 7 installed via winget"
}
else {
    Write-OK "PowerShell 7 already installed"
}

# ─── Windows Terminal ─────────────────────────────────────────────────────────

Write-Step "Installing Windows Terminal"
if (-not (Test-CommandAvailable "wt")) {
    $wtWinget = $windowsPackages.wingetPackages | Where-Object { $_.id -eq "Microsoft.WindowsTerminal" } | Select-Object -First 1
    $wtWingetId = if ($wtWinget) { $wtWinget.id } else { "Microsoft.WindowsTerminal" }
    $wtWingetSource = if ($wtWinget -and $wtWinget.source) { $wtWinget.source } else { "winget" }

    winget install --id $wtWingetId --source $wtWingetSource --accept-source-agreements --accept-package-agreements --silent
    Set-PathEnvironment
    Write-OK "Windows Terminal installed via winget"
}
else {
    Write-OK "Windows Terminal already installed"
}

# ─── Core CLI Tools (Scoop) ───────────────────────────────────────────────────

Write-Step "Installing Core CLI Tools"

$scoopTools = @($windowsPackages.scoopTools)

foreach ($tool in $scoopTools) {
    $bucketName = if ($tool.bucket) { $tool.bucket } else { "main" }
    Install-ScoopApp $tool.name $bucketName
}

# ─── JetBrains Mono Nerd Font ────────────────────────────────────────────────

if (-not $SkipFonts) {
    Write-Step "Installing Nerd Fonts"
    $fonts = @($windowsPackages.fonts)
    foreach ($fontName in $fonts) {
        $installed = scoop info $fontName 2>&1 | Select-String "Installed"
        if (-not $installed) {
            scoop install $fontName
            Write-OK "$fontName installed"
        }
        else {
            Write-OK "$fontName already installed"
        }
    }
}

# ─── PowerShell Modules ──────────────────────────────────────────────────────

Write-Step "Installing PowerShell Modules"
# Refresh PATH so fzf, git, and other just-installed tools are visible to modules that check for them
Set-PathEnvironment
$modules = @($windowsPackages.powershellModules)

foreach ($mod in $modules) {
    $existing = Get-Module -ListAvailable -Name $mod.name | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $existing) {
        Install-Module -Name $mod.name -Scope CurrentUser -Force -AllowClobber -Repository PSGallery
        Write-OK "$($mod.name) installed"
    }
    else {
        Write-OK "$($mod.name) already installed (v$($existing.Version))"
    }
}

# ─── Mise Config ─────────────────────────────────────────────────────────────

Write-Step "Setting up mise config"
$miseConfig = "$env:USERPROFILE\.config\mise\config.toml"
$miseDir = Split-Path $miseConfig
if (-not (Test-Path $miseDir)) {
    New-Item -ItemType Directory -Path $miseDir -Force | Out-Null
}
if (-not (Test-Path $miseConfig)) {
    @'
[settings]
experimental = true   # required for hooks and some core tool features

[tools]
node    = "lts"
rust    = "stable"
go      = "latest"
bun     = "latest"
pnpm    = "latest"
zig     = "latest"
python  = "latest"
java    = "temurin-21"

# Add more runtimes here as needed, e.g.:
# python = "3.12"
# deno   = "latest"
# ruby   = "latest"
'@ | Set-Content -Path $miseConfig -Encoding UTF8
    Write-OK "mise config created at $miseConfig"
}
else {
    Write-OK "mise config already exists"
}

# ─── Chezmoi Init ─────────────────────────────────────────────────────────────

if (-not $SkipChezmoi) {
    Write-Step "Configuring Chezmoi"
    Initialize-LocalChezmoiConfig
    $desiredChezmoiSource = Resolve-DesiredChezmoiSource
    Invoke-ChezmoiApply -DesiredSource $desiredChezmoiSource
    Sync-PowerShellProfileBridge
}

# ─── Dev Drive Setup (Z:\) ───────────────────────────────────────────────────

Write-Step "Configuring Dev Drive"

# Re-use existing user DEV_DRIVE on re-runs to avoid unnecessary prompts.
if (-not $DevDrive) {
    $existingDevDrive = [System.Environment]::GetEnvironmentVariable("DEV_DRIVE", "User")
    if (-not [string]::IsNullOrWhiteSpace($existingDevDrive)) {
        $candidateDrive = $existingDevDrive.TrimEnd('\')
        if (Test-Path $candidateDrive) {
            $DevDrive = $candidateDrive
            Write-OK "Using existing DEV_DRIVE: $DevDrive"
        }
        else {
            Write-Warn "Existing DEV_DRIVE is set but path is missing: $candidateDrive"
            Write-Warn "Falling back to drive selection prompt."
        }
    }
}

# ── Drive picker ──────────────────────────────────────────────────────────────
if (-not $DevDrive) {
    $drives = Get-PSDrive -PSProvider FileSystem |
    Where-Object { $_.Root -match '^[A-Z]:\\$' } |
    ForEach-Object {
        $fs = (Get-Volume -DriveLetter $_.Name -ErrorAction SilentlyContinue).FileSystemType
        [PSCustomObject]@{
            Letter = "$($_.Name):"
            Label  = (Get-Volume -DriveLetter $_.Name -ErrorAction SilentlyContinue).FileSystemLabel
            FS     = if ($fs) { $fs } else { "?" }
            FreeGB = [math]::Round($_.Free / 1GB, 1)
        }
    }

    Write-Information "" -InformationAction Continue
    Write-Information "  $($PSStyle.Foreground.Cyan)Available drives:$($PSStyle.Reset)" -InformationAction Continue
    Write-Information "" -InformationAction Continue
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $tag = if ($d.FS -eq "ReFS") { " ← ReFS (recommended)" } else { "" }
        $name = if ($d.Label) { " [$($d.Label)]" } else { "" }
        Write-Information ("  [{0}] {1}{2}  {3}  {4} GB free{5}" -f
            ($i + 1), $d.Letter, $name, $d.FS, $d.FreeGB, $tag) -InformationAction Continue
    }
    Write-Information "" -InformationAction Continue

    do {
        $raw = Read-Host "  Select drive number (default: 1)"
        if ($raw -eq "") { $raw = "1" }
        $idx = 0
        $valid = [int]::TryParse($raw, [ref]$idx) -and $idx -ge 1 -and $idx -le $drives.Count
        if (-not $valid) { Write-Warn "Invalid selection — enter a number between 1 and $($drives.Count)" }
    } while (-not $valid)

    $DevDrive = $drives[$idx - 1].Letter
    Write-Information "" -InformationAction Continue
    Write-OK "Dev Drive set to $DevDrive"
}

$devDrive = $DevDrive.TrimEnd('\')   # normalise — strip any trailing backslash

if (Test-Path $devDrive) {
    # Create standard directory structure on the Dev Drive
    $devDirs = @(
        "$devDrive\projects",
        "$devDrive\tools\cargo",
        "$devDrive\tools\pnpm",
        "$devDrive\tools\npm-global",
        "$devDrive\tools\mise",
        "$devDrive\tools\mise\shims",
        "$devDrive\go",
        "$devDrive\caches\npm",
        "$devDrive\caches\gomod",
        "$devDrive\caches\zig",
        "$devDrive\caches\mise"
    )
    $createdDirCount = 0
    foreach ($dir in $devDirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $createdDirCount++
        }
    }
    if ($createdDirCount -gt 0) {
        Write-OK "Created $createdDirCount Dev Drive directories"
    }
    else {
        Write-OK "Dev Drive directories already configured"
    }

    # Persist Dev Drive environment variables for the user
    $devEnvVars = @{
        "DEV_DRIVE"            = $devDrive     # read by profile.ps1 to route all tool paths
        "npm_config_cache"     = "$devDrive\caches\npm"
        "npm_config_prefix"    = "$devDrive\tools\npm-global"
        "PNPM_HOME"            = "$devDrive\tools\pnpm"
        "CARGO_HOME"           = "$devDrive\tools\cargo"
        "GOPATH"               = "$devDrive\go"
        "GOMODCACHE"           = "$devDrive\caches\gomod"
        "ZIG_GLOBAL_CACHE_DIR" = "$devDrive\caches\zig"
        "MISE_DATA_DIR"        = "$devDrive\tools\mise"
        "MISE_CACHE_DIR"       = "$devDrive\caches\mise"
        "PROJECTS"             = "$devDrive\projects"
    }
    $updatedUserEnvCount = 0
    $updatedSessionEnvCount = 0
    foreach ($kv in $devEnvVars.GetEnumerator()) {
        $currentUserValue = [System.Environment]::GetEnvironmentVariable($kv.Key, "User")
        if ($currentUserValue -ne $kv.Value) {
            [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "User")
            $updatedUserEnvCount++
        }

        # Mirror to current session so later install steps see updated values immediately.
        $currentSessionValue = [System.Environment]::GetEnvironmentVariable($kv.Key, "Process")
        if ($currentSessionValue -ne $kv.Value) {
            Set-Item -Path "Env:$($kv.Key)" -Value $kv.Value
            $updatedSessionEnvCount++
        }
    }
    if ($updatedUserEnvCount -gt 0 -or $updatedSessionEnvCount -gt 0) {
        Write-OK "Updated Dev Drive environment variables (user: $updatedUserEnvCount, session: $updatedSessionEnvCount)"
    }
    else {
        Write-OK "Dev Drive environment variables already configured"
    }

    # Add Dev Drive bin dirs to user PATH
    $devPaths = @(
        "$devDrive\tools\pnpm",
        "$devDrive\tools\npm-global\bin",
        "$devDrive\tools\cargo\bin",
        "$devDrive\tools\mise\shims",
        "$devDrive\go\bin"
    )

    $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    $existingEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
        $existingEntries = $currentPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $seen = @{}
    $dedupedExisting = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $existingEntries) {
        $normalized = ConvertTo-NormalizedPathEntry -PathEntry $entry
        if ([string]::IsNullOrWhiteSpace($normalized)) { continue }

        $key = $normalized.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $dedupedExisting.Add($normalized) | Out-Null
        }
    }

    $missingDevPaths = New-Object System.Collections.Generic.List[string]
    foreach ($devPath in $devPaths) {
        $normalizedDevPath = ConvertTo-NormalizedPathEntry -PathEntry $devPath
        if ([string]::IsNullOrWhiteSpace($normalizedDevPath)) { continue }

        $key = $normalizedDevPath.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $missingDevPaths.Add($normalizedDevPath) | Out-Null
        }
    }

    $finalPathEntries = @($missingDevPaths) + @($dedupedExisting)
    $newPath = ($finalPathEntries -join ";")
    $pathChanged = $false
    if ($newPath -ne $currentPath) {
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        $pathChanged = $true
    }
    Set-PathEnvironment
    if ($pathChanged) {
        Write-OK "Updated user PATH with Dev Drive entries"
    }
    else {
        Write-OK "Dev Drive PATH entries already configured"
    }

}
else {
    Write-Warn "$devDrive not found — skipping Dev Drive setup. Format your SSD as a Dev Drive and re-run with -DevDrive '$devDrive'."
    Write-Warn "Guide: Settings > System > Storage > Advanced storage settings > Disks & volumes"
}

# ─── Doppler CLI ─────────────────────────────────────────────────────────────

Write-Step "Installing Doppler CLI"
$dopplerBucket = $windowsPackages.doppler.bucketName
$dopplerBucketUrl = $windowsPackages.doppler.bucketUrl
$dopplerPackage = $windowsPackages.doppler.packageName

if (-not (Test-CommandAvailable $dopplerPackage)) {
    if (-not (Test-ScoopBucketPresent -BucketName $dopplerBucket)) {
        scoop bucket add $dopplerBucket $dopplerBucketUrl
        Write-OK "Added bucket: $dopplerBucket"
    }
    else {
        Write-OK "Bucket already added: $dopplerBucket"
    }

    scoop install "$dopplerBucket/$dopplerPackage"
    Write-OK "Doppler CLI installed"
}
else {
    Write-OK "Doppler CLI already installed"
}

# ─── Languages & Runtimes ─────────────────────────────────────────────────────

Write-Step "Installing Languages & Runtimes via mise"

if (Test-CommandAvailable "mise") {
    # All core tools managed by mise — no external installers needed.
    # Rust and Bun are first-class core tools (https://mise.jdx.dev/core-tools.html).
    # pnpm is installed as a mise tool; corepack can activate it per-project via hooks.
    # Runtime inventory is stored in manifests/windows.packages.json.
    $runtimes = @($windowsPackages.mise.runtimes)
    foreach ($runtime in $runtimes) {
        Install-MiseRuntime -RuntimeSpec $runtime
    }

    # Ensure all runtime entrypoints (e.g. go.exe) are materialized under the shims directory.
    mise reshim
    Write-OK "mise shims refreshed"

    # Reload PATH from registry and fail fast if any configured runtime command is unresolved.
    Set-PathEnvironment
    Test-MiseRuntimeCommandAvailability -RuntimeSpecs $runtimes

    Write-OK "All runtimes installed — managed by mise"
}
else {
    Write-Warn "mise not found — skipping runtime installs. Run 'scoop install mise' then re-run."
}

# ─── Dotfiles Apply (Chezmoi-first) ──────────────────────────────────────────

if ($SkipChezmoi) {
    Write-Warn "Chezmoi apply was skipped. Managed dotfiles were not deployed."
    Write-Warn "Re-run bootstrap without -SkipChezmoi, or run 'chezmoi apply' manually."
}

# ─── VS Code Extensions ───────────────────────────────────────────────────────

Write-Step "Installing VS Code Extensions"
$extScript = Join-Path $PSScriptRoot "install-vscode-extensions.ps1"
if ((Test-Path $extScript) -and (Test-CommandAvailable "code")) {
    & $extScript
}
elseif (-not (Test-CommandAvailable "code")) {
    Write-Warn "VS Code 'code' CLI not on PATH yet — restart your shell and run:"
    Write-Warn "  .\scripts\install-vscode-extensions.ps1"
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Information "`n$($PSStyle.Foreground.Green)============================================================$($PSStyle.Reset)" -InformationAction Continue
Write-Information "  $($PSStyle.Foreground.Green)✓  Dev environment setup complete!$($PSStyle.Reset)" -InformationAction Continue
Write-Information "$($PSStyle.Foreground.Green)============================================================$($PSStyle.Reset)" -InformationAction Continue
Write-Information @"

Next steps:
  1. Open Windows Terminal (dotfiles are deployed by chezmoi apply)
  2. Launch pwsh and verify the profile loads correctly
  3. Open VS Code — extensions were installed automatically
  4. Authenticate GitHub CLI:
       gh auth login
  5. Authenticate Doppler (opens browser, once per workplace):
       doppler login
  6. Configure gopass:
       gopass setup

"@ -InformationAction Continue


