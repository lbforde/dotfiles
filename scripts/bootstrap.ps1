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
    Write-Host "`n━━━ $Message ━━━" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Test-CommandExists {
    param([string]$Command)
    return [bool](Get-Command $Command -ErrorAction SilentlyContinue)
}

function Update-PathEnvironment {
    # Reload PATH from the registry so tools installed earlier in this session are immediately usable
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "  ⟳ PATH refreshed" -ForegroundColor DarkGray
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
        Write-Host "  Installing $packageRef..." -ForegroundColor Gray
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

function Test-MiseRuntimeCommands {
    param([Parameter(Mandatory = $true)][string[]]$RuntimeSpecs)

    $missing = @()
    foreach ($runtime in $RuntimeSpecs) {
        $command = Get-MiseRuntimeCommand -RuntimeSpec $runtime
        if (-not (Test-CommandExists $command)) {
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
    if (-not (Test-CommandExists "chezmoi")) { return "" }

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
    if (-not (Test-CommandExists "chezmoi")) { return "" }

    try {
        $origin = (& chezmoi git -- remote get-url origin 2>$null | Out-String).Trim()
        return $origin
    }
    catch {
        return ""
    }
}

function Test-ChezmoiHasManagedFiles {
    # Returns true when chezmoi currently has at least one managed target.
    if (-not (Test-CommandExists "chezmoi")) { return $false }

    try {
        $managed = (& chezmoi managed 2>$null | Out-String).Trim()
        return -not [string]::IsNullOrWhiteSpace($managed)
    }
    catch {
        return $false
    }
}

function Get-ExpectedPowerShellProfilePath {
    # Resolve the real PowerShell user profile target, including known-folder redirection.
    if (Test-CommandExists "pwsh") {
        try {
            $profilePath = (& pwsh -NoProfile -Command '$PROFILE.CurrentUserAllHosts' 2>$null | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($profilePath)) {
                return $profilePath
            }
        }
        catch {
            # Fall back to MyDocuments below.
        }
    }

    $documentsDir = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($documentsDir)) {
        $documentsDir = Join-Path $env:USERPROFILE "Documents"
    }

    return (Join-Path $documentsDir "PowerShell\profile.ps1")
}

function Sync-PowerShellProfileToExpectedPath {
    # Chezmoi manages home/Documents/PowerShell/profile.ps1, but Windows can redirect Documents.
    # Mirror the managed profile into the actual PowerShell profile location when they differ.
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
        Write-Warn "Skipping redirected profile sync."
        return
    }

    $expectedProfilePath = Get-ExpectedPowerShellProfilePath
    if ([string]::IsNullOrWhiteSpace($expectedProfilePath)) {
        Write-Warn "Could not resolve PowerShell profile target path; skipping redirected profile sync."
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

    $managedHash = (Get-FileHash $managedProfilePath -Algorithm SHA256).Hash
    $expectedHash = if (Test-Path $expectedProfilePath) { (Get-FileHash $expectedProfilePath -Algorithm SHA256).Hash } else { "" }

    if ($managedHash -eq $expectedHash) {
        Write-OK "PowerShell profile already synced to redirected path: $expectedProfilePath"
        return
    }

    Copy-Item -Path $managedProfilePath -Destination $expectedProfilePath -Force
    Write-OK "Synced PowerShell profile to redirected path: $expectedProfilePath"
}

function Set-TomlSection {
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
    param([Parameter(Mandatory = $true)][string]$ConfigPath)

    if (-not (Test-Path $ConfigPath)) { return }

    $content = Get-Content $ConfigPath -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        Write-Warn "Could not read local chezmoi config for editor migration: $ConfigPath"
        return
    }

    $changed = $false
    $content = Set-TomlSection -Content $content -Section "edit" -Lines @(
        'command = "code"',
        'args    = ["--wait"]'
    ) -Changed ([ref]$changed)
    $content = Set-TomlSection -Content $content -Section "merge" -Lines @(
        'command = "code"',
        'args    = ["--wait", "--merge", "{{ .Destination }}", "{{ .Source }}", "{{ .Base }}", "{{ .Destination }}"]'
    ) -Changed ([ref]$changed)
    $content = Set-TomlSection -Content $content -Section "diff" -Lines @(
        'command = "code"',
        'args    = ["--wait", "--diff", "{{ .Destination }}", "{{ .Target }}"]'
    ) -Changed ([ref]$changed)

    if (-not $changed) {
        Write-OK "Local chezmoi editor settings already use VS Code"
        return
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$ConfigPath.$timestamp.bak"
    Copy-Item -Path $ConfigPath -Destination $backupPath -Force
    $content | Set-Content -Path $ConfigPath -Encoding UTF8
    Write-OK "Migrated local chezmoi editor settings to VS Code (backup: $backupPath)"
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

    Write-Host "  No local chezmoi config found. Enter machine-specific identity values." -ForegroundColor Gray

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

function InitializeOrApplyChezmoi {
    param([Parameter(Mandatory = $true)][string]$DesiredSource)

    if (-not (Test-CommandExists "chezmoi")) {
        Write-Warn "chezmoi is not available on PATH — skipping dotfile apply."
        return
    }

    $currentSource = Get-ChezmoiSourcePath
    $hasManagedFiles = Test-ChezmoiHasManagedFiles

    # Treat "source exists but manages nothing" as effectively uninitialised.
    if ((-not $currentSource) -or (-not $hasManagedFiles)) {
        chezmoi init --apply $DesiredSource
        Write-OK "Chezmoi initialised and applied from $DesiredSource"
        return
    }

    $desiredIsRemote = $DesiredSource -match '^(https?|ssh)://|^git@'
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
    else {
        $desiredPath = (Resolve-Path $DesiredSource -ErrorAction Stop).Path
        try {
            $currentPath = (Resolve-Path $currentSource -ErrorAction Stop).Path
        }
        catch {
            $currentPath = $currentSource
        }

        if ($currentPath -ne $desiredPath) {
            Write-Warn "Chezmoi source is already initialised from a different local path."
            Write-Warn "Current source: $currentPath"
            Write-Warn "Desired source: $desiredPath"
            Write-Warn "Keeping existing source and applying current state."
        }
    }

    chezmoi apply
    Write-OK "Chezmoi apply complete"
}

# ─── Manifest Data ───────────────────────────────────────────────────────────

# Keep package/runtime inventories in JSON so this script stays logic-focused.
$windowsPackages = Get-ManifestJson "manifests\windows.packages.json"
$windowsRuntimes = Get-ManifestJson "manifests\windows.runtimes.json"

# ─── Execution Policy ────────────────────────────────────────────────────────

Write-Step "Configuring Execution Policy"
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    Write-OK "Execution policy set to RemoteSigned"
}
catch {
    Write-Warn "Could not set CurrentUser execution policy (likely overridden by Process/Group Policy). Continuing."
    Write-Host "  Effective policy: $(Get-ExecutionPolicy)" -ForegroundColor DarkGray
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
if (-not (Test-CommandExists "scoop")) {
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Update-PathEnvironment
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
    $existing = scoop bucket list 2>&1
    if ($existing -notmatch $bucketName) {
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
if (-not (Test-CommandExists "pwsh")) {
    # Winget IDs are manifest-driven so package choices stay in one place.
    $pwshWinget = $windowsPackages.wingetPackages | Where-Object { $_.id -eq "Microsoft.PowerShell" } | Select-Object -First 1
    $pwshWingetId = if ($pwshWinget) { $pwshWinget.id } else { "Microsoft.PowerShell" }
    $pwshWingetSource = if ($pwshWinget -and $pwshWinget.source) { $pwshWinget.source } else { "winget" }

    winget install --id $pwshWingetId --source $pwshWingetSource --accept-source-agreements --accept-package-agreements --silent
    Update-PathEnvironment
    Write-OK "PowerShell 7 installed via winget"
}
else {
    Write-OK "PowerShell 7 already installed"
}

# ─── Windows Terminal ─────────────────────────────────────────────────────────

Write-Step "Installing Windows Terminal"
if (-not (Test-CommandExists "wt")) {
    $wtWinget = $windowsPackages.wingetPackages | Where-Object { $_.id -eq "Microsoft.WindowsTerminal" } | Select-Object -First 1
    $wtWingetId = if ($wtWinget) { $wtWinget.id } else { "Microsoft.WindowsTerminal" }
    $wtWingetSource = if ($wtWinget -and $wtWinget.source) { $wtWinget.source } else { "winget" }

    winget install --id $wtWingetId --source $wtWingetSource --accept-source-agreements --accept-package-agreements --silent
    Update-PathEnvironment
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
Update-PathEnvironment
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
    InitializeOrApplyChezmoi -DesiredSource $desiredChezmoiSource
    Sync-PowerShellProfileToExpectedPath
}

# ─── Dev Drive Setup (Z:\) ───────────────────────────────────────────────────

Write-Step "Configuring Dev Drive"

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

    Write-Host ""
    Write-Host "  Available drives:" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $tag = if ($d.FS -eq "ReFS") { " ← ReFS (recommended)" } else { "" }
        $name = if ($d.Label) { " [$($d.Label)]" } else { "" }
        Write-Host ("  [{0}] {1}{2}  {3}  {4} GB free{5}" -f
            ($i + 1), $d.Letter, $name, $d.FS, $d.FreeGB, $tag) -ForegroundColor White
    }
    Write-Host ""

    do {
        $raw = Read-Host "  Select drive number (default: 1)"
        if ($raw -eq "") { $raw = "1" }
        $idx = 0
        $valid = [int]::TryParse($raw, [ref]$idx) -and $idx -ge 1 -and $idx -le $drives.Count
        if (-not $valid) { Write-Warn "Invalid selection — enter a number between 1 and $($drives.Count)" }
    } while (-not $valid)

    $DevDrive = $drives[$idx - 1].Letter
    Write-Host ""
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
    foreach ($dir in $devDirs) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Write-OK "Dev Drive directory structure created"

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
    foreach ($kv in $devEnvVars.GetEnumerator()) {
        [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "User")
        # Mirror to current session so later install steps see updated values immediately.
        Set-Item -Path "Env:$($kv.Key)" -Value $kv.Value
    }
    Write-OK "Dev Drive environment variables set (User scope)"

    # Add Dev Drive bin dirs to user PATH
    $devPaths = @(
        "$devDrive\tools\pnpm",
        "$devDrive\tools\npm-global\bin",
        "$devDrive\tools\cargo\bin",
        "$devDrive\tools\mise\shims",
        "$devDrive\go\bin"
    )
    $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    foreach ($p in $devPaths) {
        if ($currentPath -notlike "*$p*") {
            $currentPath = "$p;$currentPath"
        }
    }
    [System.Environment]::SetEnvironmentVariable("PATH", $currentPath, "User")
    Update-PathEnvironment
    Write-OK "Dev Drive paths added to user PATH"

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

if (-not (Test-CommandExists $dopplerPackage)) {
    $existing = scoop bucket list 2>&1
    if ($existing -notmatch $dopplerBucket) {
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

if (Test-CommandExists "mise") {
    # All core tools managed by mise — no external installers needed.
    # Rust and Bun are first-class core tools (https://mise.jdx.dev/core-tools.html).
    # pnpm is installed as a mise tool; corepack can activate it per-project via hooks.
    # Runtime inventory is stored in manifests/windows.runtimes.json.
    $runtimes = @($windowsRuntimes.miseRuntimes)
    foreach ($runtime in $runtimes) {
        Write-Host "  Installing $runtime..." -ForegroundColor Gray
        mise use --global $runtime
        Write-OK "$runtime installed"
    }

    # Ensure all runtime entrypoints (e.g. go.exe) are materialized under the shims directory.
    mise reshim
    Write-OK "mise shims refreshed"

    # Reload PATH from registry and fail fast if any configured runtime command is unresolved.
    Update-PathEnvironment
    Test-MiseRuntimeCommands -RuntimeSpecs $runtimes

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
if ((Test-Path $extScript) -and (Test-CommandExists "code")) {
    & $extScript
}
elseif (-not (Test-CommandExists "code")) {
    Write-Warn "VS Code 'code' CLI not on PATH yet — restart your shell and run:"
    Write-Warn "  .\scripts\install-vscode-extensions.ps1"
}

# ─── Done ─────────────────────────────────────────────────────────────────────

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  ✓  Dev environment setup complete!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host @"

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

"@ -ForegroundColor White
