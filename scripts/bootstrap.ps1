<#
.SYNOPSIS
    Windows Developer Environment Bootstrap Script
.DESCRIPTION
    Installs and configures a full developer environment using Winget and
    associated tools. Self-elevates when admin access is required and can run
    from a chezmoi read-source-state hook during first apply.
.NOTES
    Run with: Set-ExecutionPolicy Bypass -Scope Process -Force; .\bootstrap.ps1
#>

param(
    [string]$ChezmoiRepo = "",   # e.g. "https://github.com/yourname/dotfiles"
    [string]$DevDrive = "",   # leave blank to be prompted; or pass e.g. "D:" to skip prompt
    [switch]$FromChezmoiHook
)

$ErrorActionPreference = "Stop"
$script:BootstrapRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$script:BootstrapScriptPath = $PSCommandPath
$script:ChezmoiConfigDir = Join-Path $env:USERPROFILE ".config\chezmoi"
$script:ChezmoiConfigPath = Join-Path $script:ChezmoiConfigDir "chezmoi.toml"
$script:WindowsBootstrapMarkerPath = Join-Path $script:ChezmoiConfigDir "windows-bootstrap-complete"

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

function Test-RunningInPowerShellCoreHost {
    return $PSVersionTable.PSEdition -eq "Core"
}

function Test-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsBootstrapMarkerPath {
    return $script:WindowsBootstrapMarkerPath
}

function Test-WindowsBootstrapComplete {
    $markerPath = Get-WindowsBootstrapMarkerPath
    return Test-Path -LiteralPath $markerPath
}

function Set-WindowsBootstrapComplete {
    $markerPath = Get-WindowsBootstrapMarkerPath
    $markerDir = Split-Path $markerPath -Parent
    if (-not (Test-Path -LiteralPath $markerDir)) {
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
    }

    Set-Content -Path $markerPath -Value (Get-Date -Format "o") -Encoding UTF8
    Write-OK "Recorded Windows bootstrap marker"
}

function Start-SelfElevatedBootstrap {
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script:BootstrapScriptPath
    )

    if ($ChezmoiRepo) {
        $argumentList += @("-ChezmoiRepo", $ChezmoiRepo)
    }

    if ($DevDrive) {
        $argumentList += @("-DevDrive", $DevDrive)
    }

    if ($FromChezmoiHook) {
        $argumentList += "-FromChezmoiHook"
    }

    Write-Warn "Administrator privileges are required. Relaunching bootstrap with UAC..."
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $argumentList -Verb RunAs -PassThru -Wait
    if ($process.ExitCode -ne 0) {
        throw "Elevated bootstrap failed with exit code $($process.ExitCode)."
    }
}

function Set-PathEnvironment {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # Reload PATH from the registry so tools installed earlier in this session are immediately usable
    if ($PSCmdlet.ShouldProcess("PATH environment", "Refresh from machine and user registry values")) {
        $env:Path = (
            [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("Path", "User")
        )
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

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$Id)

    $output = @(& winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>&1)
    if ($LASTEXITCODE -eq 0) {
        return $true
    }

    $message = ($output | Out-String).Trim()
    if ($message -match "No installed package found matching input criteria") {
        return $false
    }

    throw "Unable to determine whether winget package '$Id' is installed. Output: $message"
}

function Install-WingetPackage {
    param([Parameter(Mandatory = $true)][object]$Package)

    $packageId = [string]$Package.id
    if ([string]::IsNullOrWhiteSpace($packageId)) {
        throw "Winget package entry is missing an id."
    }

    if (Test-WingetPackageInstalled -Id $packageId) {
        Write-OK "$packageId already installed"
        return
    }

    $arguments = @(
        "install",
        "--id", $packageId,
        "--exact",
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements",
        "--disable-interactivity"
    )

    if ($Package.PSObject.Properties.Name -contains "source" -and -not [string]::IsNullOrWhiteSpace([string]$Package.source)) {
        $arguments += @("--source", [string]$Package.source)
    }

    if ($Package.PSObject.Properties.Name -contains "scope" -and -not [string]::IsNullOrWhiteSpace([string]$Package.scope)) {
        $arguments += @("--scope", [string]$Package.scope)
    }

    if ($Package.PSObject.Properties.Name -contains "override" -and -not [string]::IsNullOrWhiteSpace([string]$Package.override)) {
        $arguments += @("--override", [string]$Package.override)
    }

    Write-Info "Installing $packageId via winget..."
    & winget @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install winget package '$packageId'."
    }

    Set-PathEnvironment
    Write-OK "$packageId installed via winget"
}

function Install-VSCodeExtensions {
    if (-not (Test-CommandAvailable "code")) {
        Write-Warn "VS Code 'code' CLI not on PATH yet — restart your shell and rerun:"
        Write-Warn "  .\scripts\bootstrap.ps1"
        return
    }

    $manifest = Get-ManifestJson -RelativePath "manifests/windows.packages.json"
    $extensions = @($manifest.vscode.extensions)
    $installed = @(code --list-extensions 2>$null | ForEach-Object { $_.ToLower() })
    $legacyLtexExtension = "valentjn.vscode-ltex"

    if ($installed -contains $legacyLtexExtension) {
        Write-Step "Migrating legacy LTeX extension"
        try {
            code --uninstall-extension $legacyLtexExtension --force 2>&1 | Out-Null
            Write-OK "Removed legacy extension: $legacyLtexExtension"
            $installed = @(code --list-extensions 2>$null | ForEach-Object { $_.ToLower() })
        }
        catch {
            Write-Warn "Failed to uninstall legacy extension: $legacyLtexExtension"
        }
    }

    Write-Step "Installing VS Code Extensions ($($extensions.Count) total)"

    $installedCount = 0
    $skippedCount = 0
    $failed = @()

    foreach ($ext in $extensions) {
        if ($installed -contains $ext.ToLower()) {
            Write-Host "  · $ext (already installed)" -ForegroundColor DarkGray
            $skippedCount++
            continue
        }

        try {
            Write-Host "  → Installing $ext..." -ForegroundColor Gray
            code --install-extension $ext --force 2>&1 | Out-Null
            Write-OK $ext
            $installedCount++
        }
        catch {
            Write-Warn "Failed to install: $ext"
            $failed += $ext
        }
    }

    Write-Host ""
    Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
    Write-OK "Installed : $installedCount"
    Write-Host "  · Skipped  : $skippedCount (already present)" -ForegroundColor DarkGray

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Warn "Failed to install $($failed.Count) extension(s):"
        $failed | ForEach-Object { Write-Warn "  · $_" }
    }
}

function Get-ChezmoiExecutable {
    Set-PathEnvironment -Confirm:$false

    $command = Get-Command chezmoi -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "chezmoi is required but was not found on PATH. Install it first with: winget install --exact --id twpayne.chezmoi"
    }

    return $command.Source
}

function Invoke-ChezmoiApplyChecked {
    param([switch]$ExcludeScripts)

    if ($ExcludeScripts) {
        chezmoi apply --exclude=scripts
    }
    else {
        chezmoi apply
    }

    if ($LASTEXITCODE -ne 0) {
        throw "chezmoi apply failed with exit code $LASTEXITCODE"
    }
}

function Invoke-ChezmoiInitApplyChecked {
    param(
        [Parameter(Mandatory = $true)][string]$DesiredSource,
        [switch]$ExcludeScripts
    )

    if ($ExcludeScripts) {
        chezmoi init --apply --exclude=scripts $DesiredSource
    }
    else {
        chezmoi init --apply $DesiredSource
    }

    if ($LASTEXITCODE -ne 0) {
        throw "chezmoi init --apply failed with exit code $LASTEXITCODE"
    }
}

function Invoke-MiseSync {
    $syncScript = Join-Path $PSScriptRoot "sync-mise.ps1"
    if (-not (Test-Path $syncScript)) {
        throw "mise sync script not found: $syncScript"
    }

    & $syncScript
    if ($LASTEXITCODE -ne 0) {
        throw "mise sync failed with exit code $LASTEXITCODE"
    }
}

function Get-ChezmoiSourcePath {
    # Returns empty string when chezmoi has not been initialised yet.
    if ($FromChezmoiHook) {
        return $script:BootstrapRepoRoot
    }

    Get-ChezmoiExecutable | Out-Null

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
    Get-ChezmoiExecutable | Out-Null

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
    Get-ChezmoiExecutable | Out-Null

    try {
        $managed = (& chezmoi managed 2>$null | Out-String).Trim()
        return -not [string]::IsNullOrWhiteSpace($managed)
    }
    catch {
        return $false
    }
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
    param(
        [string]$ProfileProperty = "CurrentUserCurrentHost",
        [string]$FallbackFileName = "Microsoft.PowerShell_profile.ps1"
    )

    # Resolve the real PowerShell user profile target, including known-folder redirection.
    if (Test-CommandAvailable "pwsh") {
        try {
            $profilePath = (& pwsh -NoProfile -Command "`$PROFILE.$ProfileProperty" 2>$null | Out-String).Trim()
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

    return (Join-Path $documentsDir ("PowerShell\{0}" -f $FallbackFileName))
}

function Set-PowerShellProfileBridge {
    param(
        [Parameter(Mandatory = $true)][string]$ManagedProfilePath,
        [Parameter(Mandatory = $true)][string]$ExpectedProfilePath,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $managedResolved = (Resolve-Path -LiteralPath $ManagedProfilePath | Select-Object -ExpandProperty Path -First 1)
    try {
        $expectedResolved = (Resolve-Path $ExpectedProfilePath -ErrorAction Stop).Path
    }
    catch {
        $expectedResolved = $ExpectedProfilePath
    }

    if ($managedResolved -eq $expectedResolved) {
        Write-OK "$Description is not redirected"
        return
    }

    $expectedDir = Split-Path $ExpectedProfilePath -Parent
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

    $expectedContent = if (Test-Path -LiteralPath $ExpectedProfilePath) {
        [string](Get-Content -LiteralPath $ExpectedProfilePath -Raw -ErrorAction SilentlyContinue)
    }
    else {
        ""
    }
    $expectedHash = if ($expectedContent) {
        (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($expectedContent))) -Algorithm SHA256).Hash
    }
    else {
        ""
    }

    if ($bridgeHash -eq $expectedHash) {
        Write-OK "$Description already configured: $ExpectedProfilePath"
        return
    }

    $hasExpectedProfile = Test-Path -LiteralPath $ExpectedProfilePath
    $isBootstrapManagedProfile = $hasExpectedProfile -and ([string]$expectedContent).Contains($bridgeMarker)
    if ($hasExpectedProfile -and (-not $isBootstrapManagedProfile)) {
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $backupPath = "$ExpectedProfilePath.$timestamp.bak"
        Copy-Item -Path $ExpectedProfilePath -Destination $backupPath -Force
        Write-OK "Backed up existing profile to $backupPath"
    }

    Set-Content -Path $ExpectedProfilePath -Value $bridgeContent -Encoding UTF8
    Write-OK "Configured $Description at redirected path: $ExpectedProfilePath"
}

function Remove-LegacyPowerShellProfileBridge {
    $legacyProfilePath = Get-ExpectedPowerShellProfilePath -ProfileProperty "CurrentUserAllHosts" -FallbackFileName "profile.ps1"
    if ([string]::IsNullOrWhiteSpace($legacyProfilePath) -or (-not (Test-Path -LiteralPath $legacyProfilePath))) {
        return
    }

    $bridgeMarker = "# Managed by bootstrap.ps1. Do not edit directly."
    $legacyContent = [string](Get-Content -LiteralPath $legacyProfilePath -Raw -ErrorAction SilentlyContinue)
    if ($legacyContent -and $legacyContent.Contains($bridgeMarker)) {
        Remove-Item -Path $legacyProfilePath -Force
        Write-OK "Removed legacy all-hosts PowerShell profile bridge: $legacyProfilePath"
    }
}

function Sync-PowerShellProfileBridge {
    # Chezmoi manages the current-host profile and a VS Code stub, but Windows can redirect Documents.
    # Create tiny bridges in the redirected location that dot-source the managed files.
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $runtimeCurrentHostPath = Get-ExpectedPowerShellProfilePath -ProfileProperty "CurrentUserCurrentHost" -FallbackFileName "Microsoft.PowerShell_profile.ps1"
    if ([string]::IsNullOrWhiteSpace($runtimeCurrentHostPath)) {
        Write-Warn "Could not resolve PowerShell current-host profile target path; skipping profile bridge setup."
        return
    }

    $runtimeProfileDir = Split-Path $runtimeCurrentHostPath -Parent
    $profileMappings = @(
        @{
            ManagedCandidates = @(
                (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"),
                (Join-Path $repoRoot "home\Documents\PowerShell\Microsoft.PowerShell_profile.ps1")
            )
            ExpectedProfilePath = $runtimeCurrentHostPath
            Description = "PowerShell current-host profile bridge"
        },
        @{
            ManagedCandidates = @(
                (Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.VSCode_profile.ps1"),
                (Join-Path $repoRoot "home\Documents\PowerShell\Microsoft.VSCode_profile.ps1")
            )
            ExpectedProfilePath = (Join-Path $runtimeProfileDir "Microsoft.VSCode_profile.ps1")
            Description = "VS Code PowerShell profile bridge"
        }
    )

    $chezmoiSourcePath = Get-ChezmoiSourcePath
    foreach ($mapping in $profileMappings) {
        $sourceCandidates = @($mapping.ManagedCandidates)
        if (-not [string]::IsNullOrWhiteSpace($chezmoiSourcePath)) {
            $leafName = Split-Path $mapping.ExpectedProfilePath -Leaf
            $sourceCandidates += (Join-Path $chezmoiSourcePath ("Documents\PowerShell\{0}" -f $leafName))
        }

        $managedProfilePath = $sourceCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($managedProfilePath)) {
            Write-Warn "Managed profile source not found for $($mapping.Description); checked:"
            foreach ($candidate in $sourceCandidates | Select-Object -Unique) {
                Write-Warn "  $candidate"
            }
            continue
        }

        Set-PowerShellProfileBridge -ManagedProfilePath $managedProfilePath -ExpectedProfilePath $mapping.ExpectedProfilePath -Description $mapping.Description
    }

    Remove-LegacyPowerShellProfileBridge
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
    if (Test-Path $script:ChezmoiConfigPath) {
        $existing = Get-Content $script:ChezmoiConfigPath -Raw -ErrorAction SilentlyContinue
        if ($existing -match "Your Name|your@email.com") {
            Write-Warn "Local chezmoi config still has placeholder identity values: $script:ChezmoiConfigPath"
        }
        else {
            Write-OK "Local chezmoi config already present"
        }
        Update-LocalChezmoiEditorConfig -ConfigPath $script:ChezmoiConfigPath
        return $true
    }

    Write-Info "Local chezmoi config is not present yet. It will be created by '.chezmoi.toml.tmpl' during 'chezmoi init'."
    return $false
}

function Resolve-DesiredChezmoiSource {
    if ($ChezmoiRepo -ne "") { return $ChezmoiRepo }

    # Default source is this checked-out repo (script lives under scripts/).
    return $script:BootstrapRepoRoot
}

function Invoke-ChezmoiApply {
    param([Parameter(Mandatory = $true)][string]$DesiredSource)

    Get-ChezmoiExecutable | Out-Null

    $desiredIsRemote = $DesiredSource -match '^(https?|ssh)://|^git@'

    if (-not $desiredIsRemote) {
        $desiredPath = (Resolve-Path $DesiredSource -ErrorAction Stop).Path

        $currentSource = Get-ChezmoiSourcePath
        $currentSourceRoot = Get-ChezmoiSourceRootPath -SourcePath $currentSource
        $defaultSourceRoot = Get-DefaultChezmoiSourceRoot
        $hasManagedFiles = Test-ChezmoiManagedFilePresent

        Write-Info "Chezmoi source mode: direct-path"
        Write-Info "Desired source root: $desiredPath"

        if ((-not $currentSource) -or (-not $hasManagedFiles)) {
            Invoke-ChezmoiInitApplyChecked -DesiredSource $desiredPath -ExcludeScripts
            Write-OK "Chezmoi initialised and applied from $desiredPath"
            return
        }

        if ($hasManagedFiles -and $currentSourceRoot -and ($currentSourceRoot -ne $desiredPath) -and ($currentSourceRoot -eq $defaultSourceRoot)) {
            Backup-ChezmoiSourceRoot -SourceRoot $currentSourceRoot | Out-Null
        }
        elseif ($hasManagedFiles -and $currentSourceRoot -and ($currentSourceRoot -ne $desiredPath) -and ($currentSourceRoot -ne $defaultSourceRoot)) {
            Write-Warn "Chezmoi source is already direct-path from a different local path."
            Write-Warn "Current source root: $currentSourceRoot"
            Write-Warn "Desired source root: $desiredPath"
            Write-Warn "Keeping existing source and applying current state."
            Invoke-ChezmoiApplyChecked -ExcludeScripts
            Write-OK "Chezmoi apply complete"
            $finalSourcePath = Get-ChezmoiSourcePath
            Write-Info "Final chezmoi source-path: $finalSourcePath"
            return
        }

        Set-LocalChezmoiSourceDir -SourceDir $desiredPath

        try {
            Invoke-ChezmoiApplyChecked -ExcludeScripts
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
        Invoke-ChezmoiInitApplyChecked -DesiredSource $DesiredSource -ExcludeScripts
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
    Invoke-ChezmoiApplyChecked -ExcludeScripts
    Write-OK "Chezmoi apply complete"
}

if ($FromChezmoiHook -and $env:DOTFILES_BOOTSTRAP_ACTIVE -eq "1") {
    return
}

$env:DOTFILES_BOOTSTRAP_ACTIVE = "1"

if ($FromChezmoiHook) {
    Write-Step "Checking Windows bootstrap hook"
    if (Test-WindowsBootstrapComplete) {
        Write-OK "Windows bootstrap already completed for this machine"
        return
    }

    if (-not (Test-Administrator)) {
        Start-SelfElevatedBootstrap
        return
    }

    Write-OK "Running elevated bootstrap from chezmoi hook"
}
elseif (-not (Test-Administrator)) {
    Start-SelfElevatedBootstrap
    return
}

# ─── Manifest Data ───────────────────────────────────────────────────────────

# Keep package/runtime inventories in JSON so this script stays logic-focused.
$windowsPackages = Get-ManifestJson "manifests\windows.packages.json"

# ─── Winget Availability ─────────────────────────────────────────────────────

Write-Step "Checking Winget"
if (-not (Test-CommandAvailable "winget")) {
    throw "winget is required for Windows bootstrap. Install Microsoft App Installer / Winget, then rerun .\scripts\bootstrap.ps1."
}
Write-OK "winget is available"

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

# ─── Git + Chezmoi Prereqs ───────────────────────────────────────────────────

Write-Step "Checking Git"
if (-not (Test-CommandAvailable "git")) {
    throw "git is required but was not found on PATH. Install it first with: winget install --exact --id Git.Git"
}
Write-OK "git is available"

# Ensure long paths are enabled for Windows
git config --system core.longpaths true 2>$null

Write-Step "Checking Chezmoi"
Get-ChezmoiExecutable | Out-Null
Write-OK "chezmoi is available"

# ─── Windows Applications (Winget) ───────────────────────────────────────────

Write-Step "Installing Winget Packages"
$wingetPackages = @($windowsPackages.wingetPackages)
$skippedPowerShellPackage = $false

foreach ($package in $wingetPackages) {
    if ($package.id -eq "Microsoft.PowerShell" -and (Test-RunningInPowerShellCoreHost)) {
        Write-Warn "Skipping Microsoft.PowerShell because bootstrap is running inside pwsh. Updating the current shell can terminate this session."
        Write-Info "Run bootstrap from Windows PowerShell 5.1 to let it install or upgrade PowerShell, or run: winget upgrade --id Microsoft.PowerShell --exact"
        $skippedPowerShellPackage = $true
        continue
    }

    Install-WingetPackage -Package $package
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

# ─── Chezmoi Init + Mise Sync ────────────────────────────────────────────────

Write-Step "Configuring Chezmoi"
Initialize-LocalChezmoiConfig
if ($FromChezmoiHook) {
    Write-OK "Chezmoi source apply is managed by the calling chezmoi command"
}
else {
    $desiredChezmoiSource = Resolve-DesiredChezmoiSource
    Invoke-ChezmoiApply -DesiredSource $desiredChezmoiSource
}

Invoke-MiseSync

Write-Step "Configuring PowerShell Profile Bridge"
Sync-PowerShellProfileBridge

# ─── VS Code Extensions ───────────────────────────────────────────────────────

Install-VSCodeExtensions

if ($skippedPowerShellPackage) {
    Write-Warn "Microsoft.PowerShell was skipped because bootstrap ran inside pwsh."
}

if ($FromChezmoiHook) {
    Set-WindowsBootstrapComplete
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


