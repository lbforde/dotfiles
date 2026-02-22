# install-vscode-extensions.ps1
# Installs all VS Code extensions defined in manifests/windows.packages.json.
# Run manually after VS Code is installed, or called automatically by bootstrap.ps1.
#
# Usage:
#   .\scripts\install-vscode-extensions.ps1
#   .\scripts\install-vscode-extensions.ps1 -Force   # reinstall even if already present

param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step { param($m) Write-Host "`n  ► $m" -ForegroundColor Cyan }
function Write-OK { param($m) Write-Host "  ✓ $m"   -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  ⚠ $m"   -ForegroundColor Yellow }

# ─── Verify code CLI is available ─────────────────────────────────────────────

if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Write-Warn "VS Code 'code' command not found on PATH."
    Write-Warn "Make sure VS Code is installed (scoop install vscode) and the shell has been restarted."
    exit 1
}

# ─── Load extension list from manifest ────────────────────────────────────────

$extensionsFile = Join-Path $PSScriptRoot "..\manifests\windows.packages.json"
if (-not (Test-Path $extensionsFile)) {
    Write-Warn "VS Code extensions manifest not found at: $extensionsFile"
    exit 1
}

$extensions = (Get-Content $extensionsFile -Raw | ConvertFrom-Json).vscode.recommendations

# ─── Get currently installed extensions ───────────────────────────────────────

$installed = code --list-extensions 2>$null | ForEach-Object { $_.ToLower() }
$legacyLtexExtension = "valentjn.vscode-ltex"

if ($installed -contains $legacyLtexExtension) {
    Write-Step "Migrating legacy LTeX extension"
    try {
        code --uninstall-extension $legacyLtexExtension --force 2>&1 | Out-Null
        Write-OK "Removed legacy extension: $legacyLtexExtension"
        $installed = code --list-extensions 2>$null | ForEach-Object { $_.ToLower() }
    }
    catch {
        Write-Warn "Failed to uninstall legacy extension: $legacyLtexExtension"
    }
}

# ─── Install ──────────────────────────────────────────────────────────────────

Write-Step "Installing VS Code Extensions ($($extensions.Count) total)"

$installed_count = 0
$skipped_count = 0
$failed = @()

foreach ($ext in $extensions) {
    if (-not $Force -and ($installed -contains $ext.ToLower())) {
        Write-Host "  · $ext (already installed)" -ForegroundColor DarkGray
        $skipped_count++
        continue
    }

    try {
        Write-Host "  → Installing $ext..." -ForegroundColor Gray
        code --install-extension $ext --force 2>&1 | Out-Null
        Write-OK $ext
        $installed_count++
    }
    catch {
        Write-Warn "Failed to install: $ext"
        $failed += $ext
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  ─────────────────────────────────" -ForegroundColor DarkGray
Write-OK   "Installed : $installed_count"
Write-Host "  · Skipped  : $skipped_count (already present)" -ForegroundColor DarkGray

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Warn "Failed to install $($failed.Count) extension(s):"
    $failed | ForEach-Object { Write-Warn "  · $_" }
    Write-Warn "Re-run with -Force to retry, or install them manually via VS Code."
}
