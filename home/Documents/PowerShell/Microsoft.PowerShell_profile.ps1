# ============================================================
#  PowerShell Profile — Windows Dev Environment
# ============================================================

# ─── Manual Update Commands ───────────────────────────────────────────────────

function Update-ProfileModules {
    <#
    .SYNOPSIS
        Check PSGallery for newer versions of common profile modules and update them on demand.
    #>
    $modules = @("PSReadLine", "PSFzf", "Terminal-Icons", "posh-git")
    $updated = @()

    try {
        if (-not (Test-Connection powershellgallery.com -Count 1 -Quiet -TimeoutSeconds 1)) {
            Write-Warning "[profile] PSGallery is not reachable right now."
            return
        }
    }
    catch {
        Write-Warning "[profile] Could not verify PSGallery connectivity."
        return
    }

    foreach ($moduleName in $modules) {
        try {
            $latest = Find-Module $moduleName -Repository PSGallery -ErrorAction Stop
            $current = Get-Module -ListAvailable $moduleName | Sort-Object Version -Descending | Select-Object -First 1

            if (-not $current) {
                Write-Host "[profile] $moduleName is not installed; skipping." -ForegroundColor DarkGray
                continue
            }

            if ($latest.Version -gt $current.Version) {
                Write-Host "[profile] Updating $moduleName $($current.Version) -> $($latest.Version)..." -ForegroundColor Yellow
                Update-Module $moduleName -Scope CurrentUser -Force -ErrorAction Stop
                $updated += $moduleName
            }
        }
        catch {
            Write-Warning ("[profile] Failed to update {0}: {1}" -f $moduleName, $_.Exception.Message)
        }
    }

    if ($updated.Count -gt 0) {
        Write-Host "[profile] Updated: $($updated -join ', ') — restart to apply." -ForegroundColor DarkGray
    }
    else {
        Write-Host "[profile] Profile modules are already up to date." -ForegroundColor DarkGray
    }
}

function Update-PowerShellRuntime {
    <#
    .SYNOPSIS
        Check GitHub for a newer PowerShell release and upgrade via winget if one exists.
    #>
    try {
        if (-not (Test-Connection github.com -Count 1 -Quiet -TimeoutSeconds 1)) {
            Write-Warning "[profile] GitHub is not reachable right now."
            return
        }
    }
    catch {
        Write-Warning "[profile] Could not verify GitHub connectivity."
        return
    }

    try {
        $current = $PSVersionTable.PSVersion
        $latestTag = (Invoke-RestMethod "https://api.github.com/repos/PowerShell/PowerShell/releases/latest" -ErrorAction Stop).tag_name
        $latestRaw = $latestTag.TrimStart('v')
        $latestNormalized = ([regex]::Match($latestRaw, '^\d+\.\d+\.\d+')).Value
        [version]$latest = [version]"0.0.0"

        if (-not $latestNormalized -or -not [version]::TryParse($latestNormalized, [ref]$latest)) {
            Write-Warning "[profile] Could not parse the latest PowerShell version from GitHub."
            return
        }

        if ($current -ge $latest) {
            Write-Host "[profile] PowerShell is already up to date ($current)." -ForegroundColor DarkGray
            return
        }

        Write-Host "[profile] PowerShell $latest available (you have $current) — updating..." -ForegroundColor Yellow
        $upgrade = Start-Process pwsh -ArgumentList "-NoProfile -Command winget upgrade Microsoft.PowerShell --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow -PassThru
        if ($upgrade.ExitCode -eq 0) {
            Write-Host "[profile] PowerShell updated — restart terminal." -ForegroundColor Magenta
        }
        else {
            Write-Warning "[profile] PowerShell update failed with exit code $($upgrade.ExitCode)."
        }
    }
    catch {
        Write-Warning "[profile] PowerShell update check failed: $($_.Exception.Message)"
    }
}

# ─── Telemetry Opt-out ───────────────────────────────────────────────────────

# Only when running as SYSTEM (e.g. during provisioning) — sets machine-wide opt-out
if ([bool]([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem) {
    [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', 'true', [System.EnvironmentVariableTarget]::Machine)
}

# ─── Admin Indicator ─────────────────────────────────────────────────────────

$_isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$_adminSuffix = if ($_isAdmin) { " [ADMIN]" } else { "" }
$Host.UI.RawUI.WindowTitle = "PowerShell $($PSVersionTable.PSVersion)$_adminSuffix"

# ─── Environment Setup ───────────────────────────────────────────────────────

$env:EDITOR = if (Get-Command code       -ErrorAction SilentlyContinue) { "code --wait" }
elseif (Get-Command codium     -ErrorAction SilentlyContinue) { "codium --wait" }
elseif (Get-Command notepad++  -ErrorAction SilentlyContinue) { "notepad++" }
elseif (Get-Command sublime_text -ErrorAction SilentlyContinue) { "sublime_text" }
else { "notepad" }
$env:VISUAL = $env:EDITOR

function Invoke-Editor {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    # $env:EDITOR can include flags (e.g. "code --wait"), so route known patterns explicitly.
    if ($env:EDITOR -eq "code --wait") {
        code --wait @Args
        return
    }
    if ($env:EDITOR -eq "codium --wait") {
        codium --wait @Args
        return
    }

    & $env:EDITOR @Args
}

# Keep a neutral editor command that respects $env:EDITOR.
Set-Alias -Name edit -Value Invoke-Editor -Option AllScope -Force -ErrorAction SilentlyContinue

$env:PAGER = if (Get-Command bat -ErrorAction SilentlyContinue) { "bat" } else { "more" }
$env:BAT_THEME = "OneHalfDark"   # closest bat theme to One Dark Pro; change with: bat --list-themes
$env:FZF_DEFAULT_COMMAND = "fd --type f --hidden --follow --exclude .git"
$env:FZF_DEFAULT_OPTS = "--height 40% --layout=reverse --border --preview 'bat --color=always --line-range :50 {}'"

# ─── Dev Drive ───────────────────────────────────────────────────────────────
# Drive letter is set by bootstrap.ps1 (-DevDrive param) and persisted as DEV_DRIVE.
# Falls back to Z: if the env var isn't set. Change it by re-running bootstrap with
# -DevDrive "D:" (or whatever letter your drive is assigned on this machine).

$_devDrive = if ($env:DEV_DRIVE) { $env:DEV_DRIVE.TrimEnd('\') } else { "Z:" }

# npm / Node
$env:npm_config_cache = "$_devDrive\caches\npm"
$env:npm_config_prefix = "$_devDrive\tools\npm-global"

# pnpm
$env:PNPM_HOME = "$_devDrive\tools\pnpm"

# Rust / Cargo — mise manages the toolchain, CARGO_HOME just controls where crates cache
$env:CARGO_HOME = "$_devDrive\tools\cargo"

# Go
$env:GOPATH = "$_devDrive\go"
$env:GOMODCACHE = "$_devDrive\caches\gomod"

# Zig cache
$env:ZIG_GLOBAL_CACHE_DIR = "$_devDrive\caches\zig"

# mise — runtimes and shims on Dev Drive
$env:MISE_DATA_DIR = "$_devDrive\tools\mise"
$env:MISE_CACHE_DIR = "$_devDrive\caches\mise"

# Projects root
$env:PROJECTS = "$_devDrive\projects"

# Extend PATH with Dev Drive tool bin dirs
$_devPaths = @(
    "$_devDrive\tools\pnpm",
    "$_devDrive\tools\npm-global\bin",
    "$_devDrive\tools\cargo\bin",
    "$_devDrive\tools\mise\shims",
    "$_devDrive\go\bin"
)
foreach ($p in $_devPaths) {
    if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
        $env:PATH = "$p;$env:PATH"
    }
}

# ─── Module Imports ───────────────────────────────────────────────────────────

# PSReadLine — enhanced readline with history, predictions, and key bindings
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Windows
    # Prediction UI fails in redirected/non-interactive hosts; enable only when supported.
    try {
        if ((-not [Console]::IsOutputRedirected) -and $Host.UI.SupportsVirtualTerminal) {
            Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
            Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
        }
    }
    catch {
        # Skip prediction settings when the current host cannot render them.
    }
    Set-PSReadLineOption -HistoryNoDuplicates:$true
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd:$true
    Set-PSReadLineOption -ShowToolTips:$true
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineOption -Colors @{
        Command          = '#4aa5f0'   # OneDark Pro darker blue
        Parameter        = '#8cc265'   # OneDark Pro darker green
        Operator         = '#42b3c2'   # OneDark Pro darker cyan
        Variable         = '#e05561'   # OneDark Pro darker red
        String           = '#8cc265'   # OneDark Pro darker green
        Number           = '#d19a66'   # OneDark Pro darker orange
        Member           = '#d18f52'   # OneDark Pro darker yellow
        InlinePrediction = '#4f5666'   # OneDark Pro darker comment
    }

    # Key bindings
    Set-PSReadLineKeyHandler -Key Tab             -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow         -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow       -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Ctrl+d          -Function DeleteCharOrExit
    Set-PSReadLineKeyHandler -Key Ctrl+w          -Function BackwardDeleteWord
    Set-PSReadLineKeyHandler -Key Alt+d           -Function DeleteWord
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow  -Function BackwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+Backspace  -Function BackwardDeleteWord
    Set-PSReadLineKeyHandler -Key Ctrl+k          -Function DeleteToEnd
    Set-PSReadLineKeyHandler -Key Ctrl+u          -Function BackwardDeleteLine
    Set-PSReadLineKeyHandler -Key Ctrl+z          -Function Undo
    Set-PSReadLineKeyHandler -Key Ctrl+y          -Function Redo

    Set-PSReadLineOption -MaximumHistoryCount 10000

    # Don't save commands containing sensitive keywords to history
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        $blocked = @('password', 'passwd', 'secret', 'token', 'apikey', 'api_key', 'connectionstring', 'connstr')
        return ($null -eq ($blocked | Where-Object { $line -imatch $_ }))
    }
}

# Terminal-Icons — pretty ls icons
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# PSFzf — fzf integration
if ((Get-Module -ListAvailable -Name PSFzf) -and (Get-Command fzf -ErrorAction SilentlyContinue)) {
    Import-Module PSFzf
    # Ctrl+F — fuzzy search files, paste selected path into command line
    # Ctrl+R — fuzzy search command history
    # Alt+C  — fzf tab completion on current word at cursor
    Set-PsFzfOption -PSReadLineChordProvider "Ctrl+f"
    Set-PsFzfOption -PSReadLineChordReverseHistory "Ctrl+r"
    Set-PSReadLineKeyHandler -Key Alt+c -ScriptBlock { Invoke-FzfTabCompletion }
}

# ─── Starship Prompt ─────────────────────────────────────────────────────────

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# ─── Mise (runtime version manager) ──────────────────────────────────────────

if (Get-Command mise -ErrorAction SilentlyContinue) {
    # mise can emit multiple objects/lines; coerce to a single script string before Invoke-Expression.
    Invoke-Expression (& { (mise activate pwsh | Out-String) })
}

# ─── Navigation & Directory Aliases ─────────────────────────────────────────

function Set-LocationHome { Set-Location $env:USERPROFILE }
function Set-LocationUp { Set-Location .. }
function Set-LocationUp2 { Set-Location ../.. }
function Set-LocationUp3 { Set-Location ../../.. }

Set-Alias -Name "~"   -Value Set-LocationHome
Set-Alias -Name ".."  -Value Set-LocationUp
Set-Alias -Name "..." -Value Set-LocationUp2
Set-Alias -Name "...." -Value Set-LocationUp3

function mkcd {
    param([string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# Jump to projects root on Dev Drive (falls back gracefully if Z:\ not mounted)
function proj {
    $target = if ($env:PROJECTS -and (Test-Path $env:PROJECTS)) { $env:PROJECTS } else { "$env:USERPROFILE\projects" }
    Set-Location $target
}

# ─── eza (modern ls replacement) ─────────────────────────────────────────────

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function Get-ChildItemEza { eza --icons --group-directories-first @args }
    function Get-ChildItemEzaLong { eza --icons --group-directories-first -l --git @args }
    function Get-ChildItemEzaAll { eza --icons --group-directories-first -la --git @args }
    function Get-ChildItemEzaTree { eza --icons --group-directories-first --tree @args }
    function Get-ChildItemEzaTree2 { eza --icons --group-directories-first --tree --level=2 @args }

    Set-Alias -Name ls    -Value Get-ChildItemEza      -Option AllScope -Force
    Set-Alias -Name ll    -Value Get-ChildItemEzaLong  -Option AllScope -Force
    Set-Alias -Name la    -Value Get-ChildItemEzaAll   -Option AllScope -Force
    Set-Alias -Name lt    -Value Get-ChildItemEzaTree  -Option AllScope -Force
    Set-Alias -Name lt2   -Value Get-ChildItemEzaTree2 -Option AllScope -Force
    Set-Alias -Name l     -Value Get-ChildItemEza      -Option AllScope -Force
}
else {
    # Fallback to built-in with some Linux-like formatting
    function Get-ChildItemFallback { Get-ChildItem @args }
    Set-Alias -Name ls -Value Get-ChildItemFallback -Option AllScope -Force
    Set-Alias -Name ll -Value Get-ChildItem         -Option AllScope -Force
}

# ─── bat (better cat) ────────────────────────────────────────────────────────

if (Get-Command bat -ErrorAction SilentlyContinue) {
    function Invoke-Bat { bat --paging=never @args }
    Set-Alias -Name cat -Value Invoke-Bat -Option AllScope -Force

    # man replacement using bat for syntax highlighting
    function man {
        param([string]$Command)
        Get-Help $Command -Full | bat --paging=always --language=man
    }
}

# ─── ripgrep / fd ─────────────────────────────────────────────────────────────

if (Get-Command rg -ErrorAction SilentlyContinue) {
    Set-Alias -Name grep -Value rg -Option AllScope -Force
}

if (Get-Command fd -ErrorAction SilentlyContinue) {
    Set-Alias -Name find -Value fd -Option AllScope -Force
}

# ─── yazi — file manager ─────────────────────────────────────────────────────

if (Get-Command yazi -ErrorAction SilentlyContinue) {
    # Wrapper that cds into the last directory yazi was in when you quit
    function y {
        $tmp = [System.IO.Path]::GetTempFileName()
        yazi @args --cwd-file=$tmp
        $cwd = Get-Content -Raw $tmp -ErrorAction SilentlyContinue
        if ($cwd -and (Test-Path $cwd) -and $cwd -ne $PWD.Path) {
            Set-Location $cwd
        }
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# ─── lazygit ─────────────────────────────────────────────────────────────────

if (Get-Command lazygit -ErrorAction SilentlyContinue) {
    Set-Alias -Name lg -Value lazygit -Option AllScope
}

# ─── Git Shortcuts (oh-my-zsh style subset) ──────────────────────────────────

function Invoke-GitCommand {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $gitCommand = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCommand) {
        Write-Error "git executable not found in PATH."
        return
    }

    & $gitCommand.Source @Arguments
}

function Invoke-GitAdd { Invoke-GitCommand @('add') @args }
function Invoke-GitAddAll { Invoke-GitCommand @('add', '--all') @args }
function Invoke-GitBranch { Invoke-GitCommand @('branch') @args }
function Invoke-GitCommitVerbose { Invoke-GitCommand @('commit', '-v') @args }
function Invoke-GitCommitAmend { Invoke-GitCommand @('commit', '-v', '--amend') @args }
function Invoke-GitCommitAllMessage { Invoke-GitCommand @('commit', '-a', '-m') @args }
function Invoke-GitCheckout { Invoke-GitCommand @('checkout') @args }
function Invoke-GitCheckoutBranch { Invoke-GitCommand @('checkout', '-b') @args }
function Invoke-GitDiff { Invoke-GitCommand @('diff') @args }
function Invoke-GitDiffStaged { Invoke-GitCommand @('diff', '--staged') @args }
function Invoke-GitFetch { Invoke-GitCommand @('fetch') @args }
function Invoke-GitPull { Invoke-GitCommand @('pull') @args }
function Invoke-GitLogOneline { Invoke-GitCommand @('log', '--oneline', '--decorate') @args }
function Invoke-GitLogOnelineAll { Invoke-GitCommand @('log', '--oneline', '--decorate', '--graph', '--all') @args }
function Invoke-GitPush { Invoke-GitCommand @('push') @args }
function Invoke-GitPushForceWithLease { Invoke-GitCommand @('push', '--force-with-lease') @args }
function Invoke-GitPullRebase { Invoke-GitCommand @('pull', '--rebase') @args }
function Invoke-GitStatus { Invoke-GitCommand @('status') @args }
function Invoke-GitSwitch { Invoke-GitCommand @('switch') @args }
function Invoke-GitSwitchCreate { Invoke-GitCommand @('switch', '-c') @args }

Set-Alias -Name g     -Value git                        -Option AllScope -Force
Set-Alias -Name ga    -Value Invoke-GitAdd              -Option AllScope -Force
Set-Alias -Name gaa   -Value Invoke-GitAddAll           -Option AllScope -Force
Set-Alias -Name gb    -Value Invoke-GitBranch           -Option AllScope -Force
Set-Alias -Name gc    -Value Invoke-GitCommitVerbose    -Option AllScope -Force
Set-Alias -Name "gc!" -Value Invoke-GitCommitAmend      -Option AllScope -Force
Set-Alias -Name gcam  -Value Invoke-GitCommitAllMessage -Option AllScope -Force
Set-Alias -Name gco   -Value Invoke-GitCheckout         -Option AllScope -Force
Set-Alias -Name gcb   -Value Invoke-GitCheckoutBranch   -Option AllScope -Force
Set-Alias -Name gd    -Value Invoke-GitDiff             -Option AllScope -Force
Set-Alias -Name gds   -Value Invoke-GitDiffStaged       -Option AllScope -Force
Set-Alias -Name gf    -Value Invoke-GitFetch            -Option AllScope -Force
Set-Alias -Name gl    -Value Invoke-GitPull             -Option AllScope -Force
Set-Alias -Name glo   -Value Invoke-GitLogOneline       -Option AllScope -Force
Set-Alias -Name gloga -Value Invoke-GitLogOnelineAll    -Option AllScope -Force
Set-Alias -Name gp    -Value Invoke-GitPush             -Option AllScope -Force
Set-Alias -Name "gpf!" -Value Invoke-GitPushForceWithLease -Option AllScope -Force
Set-Alias -Name gpr   -Value Invoke-GitPullRebase       -Option AllScope -Force
Set-Alias -Name gst   -Value Invoke-GitStatus           -Option AllScope -Force
Set-Alias -Name gsw   -Value Invoke-GitSwitch           -Option AllScope -Force
Set-Alias -Name gswc  -Value Invoke-GitSwitchCreate     -Option AllScope -Force

# ─── Linux-compatible Filesystem Commands ────────────────────────────────────

function touch {
    param([string[]]$Path)
    foreach ($p in $Path) {
        if (Test-Path $p) {
            (Get-Item $p).LastWriteTime = Get-Date
        }
        else {
            New-Item -ItemType File -Path $p -Force | Out-Null
        }
    }
}

function which {
    param([string]$Command)
    Get-Command $Command | Select-Object -ExpandProperty Source
}

function sudo {
    $pwshArgs = @("-NoExit")

    if ($args.Count -gt 0) {
        $quotedArgs = $args | ForEach-Object {
            "'$([System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$_))'"
        }
        $commandText = '$cmd = @(' + ($quotedArgs -join ', ') + '); if ($cmd.Count -gt 1) { & $cmd[0] @($cmd[1..($cmd.Count - 1)]) } else { & $cmd[0] }'
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($commandText))
        $pwshArgs += @("-EncodedCommand", $encodedCommand)
    }

    # Prefer opening in Windows Terminal; fall back to plain pwsh if not found.
    if (Get-Command wt -ErrorAction SilentlyContinue) {
        Start-Process wt -Verb RunAs -ArgumentList (@("pwsh") + $pwshArgs)
    }
    else {
        Start-Process pwsh -Verb RunAs -ArgumentList $pwshArgs
    }
}
Set-Alias -Name su -Value sudo -Option AllScope

function head {
    param([string]$Path, [int]$Lines = 10)
    Get-Content $Path -TotalCount $Lines
}

function tail {
    param([string]$Path, [int]$Lines = 10, [switch]$Follow)
    if ($Follow) {
        Get-Content $Path -Tail $Lines -Wait
    }
    else {
        Get-Content $Path -Tail $Lines
    }
}

function wc {
    param([string]$Path, [switch]$l, [switch]$w, [switch]$c)
    $content = Get-Content $Path
    $lines = $content.Count
    $words = ($content | ForEach-Object { $_ -split '\s+' } | Where-Object { $_ -ne '' }).Count
    $chars = ($content | Measure-Object -Character).Characters
    if ($l) { return $lines }
    if ($w) { return $words }
    if ($c) { return $chars }
    "$lines`t$words`t$chars`t$Path"
}

function df {
    Get-PSDrive -PSProvider FileSystem | Select-Object Name,
    @{N = "Used(GB)"; E = { [math]::Round($_.Used / 1GB, 2) } },
    @{N = "Free(GB)"; E = { [math]::Round($_.Free / 1GB, 2) } },
    @{N = "Total(GB)"; E = { [math]::Round(($_.Used + $_.Free) / 1GB, 2) } } |
    Format-Table -AutoSize
}

function du {
    param([string]$Path = ".")
    Get-ChildItem $Path -Recurse -File -ErrorAction SilentlyContinue |
    Measure-Object -Property Length -Sum |
    ForEach-Object { "{0:N2} MB — {1}" -f ($_.Sum / 1MB), (Resolve-Path $Path) }
}

function ps {
    Get-Process @args
}

function kill {
    param([string]$Name, [int]$Id)
    if ($Id) { Stop-Process -Id $Id -Force }
    elseif ($Name) { Stop-Process -Name $Name -Force }
}

function env {
    Get-ChildItem Env: | Sort-Object Name | Format-Table -AutoSize
}

function export {
    param([string]$Assignment)
    $parts = $Assignment -split '=', 2
    if ($parts.Count -eq 2) {
        [Environment]::SetEnvironmentVariable($parts[0], $parts[1], "User")
        Set-Item "Env:$($parts[0])" $parts[1]
    }
}

function unset {
    param([string]$Name)
    [Environment]::SetEnvironmentVariable($Name, $null, "User")
    Remove-Item "Env:$Name" -ErrorAction SilentlyContinue
}

function pwd { (Get-Location).Path }

function clear { [Console]::Clear() }

function history {
    param([int]$Count = 50)
    Get-History -Count $Count
}

function cp {
    param([string]$Source, [string]$Destination, [switch]$r, [switch]$f)
    $opts = @{}
    if ($r) { $opts['Recurse'] = $true }
    if ($f) { $opts['Force'] = $true }
    Copy-Item $Source $Destination @opts
}

function mv {
    param([string]$Source, [string]$Destination, [switch]$f)
    $opts = @{}
    if ($f) { $opts['Force'] = $true }
    Move-Item $Source $Destination @opts
}

function rm {
    param([string[]]$Path, [switch]$r, [switch]$f)
    $opts = @{}
    if ($r) { $opts['Recurse'] = $true }
    if ($f) { $opts['Force'] = $true }
    foreach ($p in $Path) { Remove-Item $p @opts }
}

function mkdir {
    # Always behaves like mkdir -p — creates intermediate directories without error
    param([string[]]$Path)
    foreach ($d in $Path) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
}

function ln {
    param([string]$Target, [string]$Link, [switch]$s)
    if ($s) {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force
    }
    else {
        New-Item -ItemType HardLink     -Path $Link -Target $Target -Force
    }
}

# ─── Process & Network Commands ──────────────────────────────────────────────

function pgrep {
    param([string]$Pattern)
    Get-Process | Where-Object { $_.Name -match $Pattern } | Select-Object Id, Name, CPU, WorkingSet
}

function pkill {
    param([string]$Pattern)
    Get-Process | Where-Object { $_.Name -match $Pattern } | Stop-Process -Force
}

function netstat {
    Get-NetTCPConnection | Where-Object { $_.State -ne "Closed" } |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess |
    Format-Table -AutoSize
}

function curl {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
    $nativeCurl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($nativeCurl) {
        & $nativeCurl.Source @Arguments
        return
    }

    Invoke-WebRequest @Arguments
}

function wget {
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
    $nativeWget = Get-Command wget.exe -ErrorAction SilentlyContinue
    if ($nativeWget) {
        & $nativeWget.Source @Arguments
        return
    }

    Invoke-WebRequest @Arguments
}

# ─── Text Utilities ───────────────────────────────────────────────────────────

function echo { Write-Output @args }

function sort {
    param([switch]$r, [switch]$u)
    $input | Sort-Object { [string]$_ } -Descending:$r -Unique:$u
}

function uniq {
    $input | Select-Object -Unique
}

function sed {
    param([string]$Pattern, [string]$Replacement, [string]$Path)
    if ($Path) {
        (Get-Content $Path) -replace $Pattern, $Replacement | Set-Content $Path
    }
    else {
        $input | ForEach-Object { $_ -replace $Pattern, $Replacement }
    }
}

function awk {
    # Basic awk-like column extraction: awk '{print $1,$2}'
    param([string]$Program)
    $match = [regex]::Match($Program, '\{print\s+(.+)\}')
    if ($match.Success) {
        $cols = $match.Groups[1].Value -split ',' | ForEach-Object {
            [int]($_.Trim() -replace '\$', '') - 1
        }
        $input | ForEach-Object {
            $parts = $_ -split '\s+'
            ($cols | ForEach-Object { $parts[$_] }) -join ' '
        }
    }
    else {
        $input
    }
}

function xargs {
    param([string]$Command)
    $input | ForEach-Object { & $Command $_ }
}

function tee {
    param([string]$Path)
    $input | ForEach-Object {
        Write-Output $_
        $_ | Add-Content $Path
    }
}

function less {
    param([string]$Path)
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        bat --paging=always $Path
    }
    else {
        Get-Content $Path | more
    }
}

function more {
    param([string]$Path)
    if ($Path) { Get-Content $Path | Out-Host -Paging }
    else { $input | Out-Host -Paging }
}

# ─── System Utilities ─────────────────────────────────────────────────────────

function uptime {
    try {
        $bootTime = if ($PSVersionTable.PSVersion.Major -ge 6) {
            Get-Uptime -Since
        }
        else {
            $raw = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
            [System.Management.ManagementDateTimeConverter]::ToDateTime($raw)
        }
        $up = (Get-Date) - $bootTime
        Write-Host ("System started: {0}" -f $bootTime.ToString("dddd, MMMM dd, yyyy HH:mm:ss")) -ForegroundColor DarkGray
        Write-Host ("Uptime:         {0}d {1}h {2}m {3}s" -f $up.Days, $up.Hours, $up.Minutes, $up.Seconds) -ForegroundColor Blue
    }
    catch {
        Write-Error "Could not retrieve uptime."
    }
}

function reboot { Restart-Computer -Force }
function poweroff { Stop-Computer -Force }

function sysinfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor
    $ram = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    Write-Host "OS:  $($os.Caption) $($os.OSArchitecture)" -ForegroundColor Cyan
    Write-Host "CPU: $($cpu.Name)" -ForegroundColor Cyan
    Write-Host "RAM: ${ram} GB" -ForegroundColor Cyan
    Write-Host "Host: $($env:COMPUTERNAME)" -ForegroundColor Cyan
}

# ─── jq aliases ───────────────────────────────────────────────────────────────

if (Get-Command jq -ErrorAction SilentlyContinue) {
    function jqpretty { $input | jq '.' }
    function jqkeys { $input | jq 'keys' }
}

# ─── Clipboard ────────────────────────────────────────────────────────────────

function pbcopy { $input | Set-Clipboard }
function pbpaste { Get-Clipboard }

# ─── Open / xdg-open ─────────────────────────────────────────────────────────

function open {
    param([string]$Path)
    if ($Path) { Start-Process $Path }
    else { explorer.exe . }
}
Set-Alias -Name xdg-open -Value open -Option AllScope

# ─── Useful Functions ─────────────────────────────────────────────────────────

function Get-ManagedProfilePath {
    if ($PROFILE.CurrentUserCurrentHost) {
        $currentHostDir = Split-Path -Parent $PROFILE.CurrentUserCurrentHost
        if ($currentHostDir) {
            $consoleProfilePath = Join-Path $currentHostDir "Microsoft.PowerShell_profile.ps1"
            if (Test-Path -LiteralPath $consoleProfilePath) {
                return $consoleProfilePath
            }
        }
    }

    if ($PROFILE.CurrentUserCurrentHost -and (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)) {
        return $PROFILE.CurrentUserCurrentHost
    }

    if ($PROFILE.CurrentUserAllHosts -and (Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts)) {
        return $PROFILE.CurrentUserAllHosts
    }

    return $PROFILE
}

function Invoke-Reload {
    $reloadTarget = if ($PROFILE.CurrentUserCurrentHost -and (Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost)) {
        $PROFILE.CurrentUserCurrentHost
    }
    else {
        Get-ManagedProfilePath
    }

    . $reloadTarget

    Write-Host "[profile] Reloaded." -ForegroundColor DarkGray
}
Set-Alias -Name reload -Value Invoke-Reload

function Invoke-ProfileEdit {
    Invoke-Editor (Get-ManagedProfilePath)
}
Set-Alias -Name editprofile -Value Invoke-ProfileEdit
Set-Alias -Name ep          -Value Invoke-ProfileEdit

# Count lines of code in a directory
function Measure-CodeLineCount {
    param([string]$Path = ".", [string[]]$Extensions = @("*.ps1", "*.py", "*.js", "*.ts", "*.go", "*.rs"))
    $total = 0
    foreach ($ext in $Extensions) {
        $count = (Get-ChildItem $Path -Recurse -Filter $ext -ErrorAction SilentlyContinue |
            Get-Content | Measure-Object -Line).Lines
        if ($count) {
            Write-Host "$ext : $count lines"
            $total += $count
        }
    }
    Write-Host "Total: $total lines" -ForegroundColor Cyan
}
Set-Alias -Name cloc-simple -Value Measure-CodeLineCount

# Quick HTTP server in current directory (requires Python)
function serve {
    param([int]$Port = 8000)
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Host "Serving on http://localhost:$Port" -ForegroundColor Cyan
        python -m http.server $Port
    }
    else {
        Write-Warning "Python not found — install it with: mise use python@latest"
    }
}

# Extract common archive formats
function extract {
    param([string]$Path)
    switch -Wildcard ($Path) {
        "*.zip" { Expand-Archive $Path . }
        "*.tar.gz" { tar -xzf $Path }
        "*.tar.bz2" { tar -xjf $Path }
        "*.tar.xz" { tar -xJf $Path }
        "*.7z" { 7z x $Path }
        default { Write-Warning "Unknown archive format: $Path" }
    }
}

# ─── File & Process Utilities ────────────────────────────────────────────────

# Send to Recycle Bin instead of permanently deleting (safer rm alternative)
function trash {
    param([string]$Path)
    $fullPath = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue)?.Path
    if (-not $fullPath) { Write-Error "Path not found: $Path"; return }
    $item = Get-Item $fullPath
    $shell = New-Object -ComObject 'Shell.Application'
    $shellItem = $shell.NameSpace($item.PSParentPath.Replace("Microsoft.PowerShell.Core\FileSystem::", "")).ParseName($item.Name)
    if ($shellItem) {
        $shellItem.InvokeVerb('delete')
        Write-Host "Moved to Recycle Bin: $fullPath" -ForegroundColor DarkGray
    }
    else {
        Write-Error "Could not trash: $fullPath"
    }
}

# Find files recursively by partial name
function ff {
    param([string]$Name)
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue |
    ForEach-Object { $_.FullName }
}

# Quick new file creation
function nf {
    param([string]$Name)
    New-Item -ItemType File -Path . -Name $Name | Out-Null
}

# Kill process by name shorthand
function k9 {
    param([string]$Name)
    Stop-Process -Name $Name -Force -ErrorAction SilentlyContinue
}

# ─── Network Utilities ────────────────────────────────────────────────────────

function pubip {
    (Invoke-WebRequest -Uri "https://ifconfig.me/ip" -UseBasicParsing).Content.Trim()
}

function flushdns {
    Clear-DnsClientCache
    Write-Host "DNS cache flushed." -ForegroundColor Green
}

# ─── shasum (checksum helper) ─────────────────────────────────────────────────

function shasum {
    param(
        [string]$Path,
        [ValidateSet("1", "256", "384", "512")]
        [string]$a = "256"
    )
    $algo = switch ($a) { "1" { "SHA1" } "384" { "SHA384" } "512" { "SHA512" } default { "SHA256" } }
    $hash = (Get-FileHash $Path -Algorithm $algo).Hash.ToLower()
    "$hash  $Path"
}

# ─── Argument Completers ──────────────────────────────────────────────────────

# posh-git — full dynamic git completion (branches, remotes, tags, stash refs, etc.)
if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git
}

# dotnet — native completion via `dotnet complete`
if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        dotnet complete --position $cursorPosition $commandAst.ToString() | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# winget — native completion via `winget complete`
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = [System.Text.Utf8Encoding]::new()
        $word = $wordToComplete.Replace('"', '""')
        $ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$word" --commandline "$ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# gh (GitHub CLI) — native completion via `gh completion`
if (Get-Command gh -ErrorAction SilentlyContinue) {
    Invoke-Expression -Command $(gh completion -s powershell | Out-String)
}

# mise - static subcommand completion (avoids external `usage` CLI dependency)
if (Get-Command mise -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName mise -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $subcommands = @(
            'activate', 'tool-alias', 'backends', 'bin-paths', 'cache', 'completion',
            'config', 'deactivate', 'doctor', 'en', 'env', 'exec', 'fmt', 'generate',
            'implode', 'edit', 'install', 'install-into', 'latest', 'link', 'lock',
            'ls', 'ls-remote', 'mcp', 'outdated', 'plugins', 'prepare', 'prune',
            'registry', 'reshim', 'run', 'search', 'self-update', 'set', 'settings',
            'shell', 'shell-alias', 'sync', 'tasks', 'test-tool', 'tool', 'tool-stub',
            'trust', 'uninstall', 'unset', 'unuse', 'upgrade', 'use', 'version', 'watch',
            'where', 'which', 'help'
        )
        if ($commandAst.CommandElements.Count -le 2) {
            $subcommands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}

# scoop — static subcommand completion (no native complete API)
Register-ArgumentCompleter -Native -CommandName scoop -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $subcommands = @(
        'install', 'uninstall', 'update', 'status', 'search', 'info', 'list',
        'bucket', 'cache', 'cleanup', 'reset', 'depends', 'export', 'import',
        'hold', 'unhold', 'prefix', 'home', 'cat', 'which', 'checkup', 'help'
    )
    $elements = $commandAst.CommandElements
    if ($elements.Count -ge 2 -and $elements[1].Value -eq 'bucket') {
        # scoop bucket <subcommand>
        @('add', 'remove', 'list', 'known', 'update') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
    elseif ($elements.Count -le 2) {
        # Completing the top-level subcommand
        $subcommands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# chezmoi — static subcommand completion (no native complete API)
Register-ArgumentCompleter -Native -CommandName chezmoi -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $subcommands = @(
        'add', 'apply', 'archive', 'cat', 'cd', 'chattr', 'completion', 'data',
        'diff', 'doctor', 'dump', 'edit', 'edit-config', 'execute-template',
        'forget', 'git', 'help', 'import', 'init', 'manage', 'managed', 'merge',
        'merge-all', 'purge', 're-add', 'remove', 'secret', 'source-path',
        'state', 'status', 'unmanage', 'unmanaged', 'update', 'upgrade', 'verify'
    )
    if ($commandAst.CommandElements.Count -le 2) {
        $subcommands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# doppler — static subcommand completion
if (Get-Command doppler -ErrorAction SilentlyContinue) {
    Register-ArgumentCompleter -Native -CommandName doppler -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $subcommands = @(
            'completion', 'configure', 'environments', 'groups', 'import',
            'login', 'logout', 'open', 'projects', 'run', 'secrets', 'setup',
            'update'
        )
        if ($commandAst.CommandElements.Count -le 2) {
            $subcommands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
    }
}

# ─── Show-Help ────────────────────────────────────────────────────────────────

function Show-Help {
    $c = $PSStyle.Foreground.Cyan
    $g = $PSStyle.Foreground.Green
    $y = $PSStyle.Foreground.Yellow
    $r = $PSStyle.Reset
    Write-Host @"
${c}Navigation${r}
${y}──────────────────────────────────────────${r}
  ${g}~${r}                   Go to home directory
  ${g}..  ...  ....${r}       Up 1 / 2 / 3 directories
  ${g}z <query>${r}           Smart jump to frecent directory (zoxide)
  ${g}zi${r}                  Interactive zoxide jump with fzf
  ${g}mkcd <dir>${r}          Create directory and cd into it
  ${g}proj${r}                Jump to Dev Drive projects root
  ${g}y${r}                   Yazi file manager (cds on exit)

${c}File Listing (eza)${r}
${y}──────────────────────────────────────────${r}
  ${g}ls${r}  ${g}l${r}               List with icons, dirs first
  ${g}ll${r}                  Long list + git status
  ${g}la${r}                  Long list including hidden files
  ${g}lt${r}                  Tree view
  ${g}lt2${r}                 Tree view, 2 levels deep

${c}File Operations${r}
${y}──────────────────────────────────────────${r}
  ${g}touch <file>${r}        Create file or update timestamp
  ${g}nf <file>${r}           New empty file in current directory
  ${g}ff <n>${r}           Find files recursively by partial name
  ${g}cp${r}  ${g}mv${r}  ${g}rm${r}  ${g}mkdir${r}  ${g}ln${r}   Linux-style file ops (-r, -f, -s flags)
  ${g}trash <path>${r}        Move to Recycle Bin (safer than rm)
  ${g}extract <file>${r}      Extract zip / tar.gz / tar.bz2 / tar.xz / 7z
  ${g}shasum <file>${r}       Checksum — SHA256 by default (-a 1/384/512)
  ${g}wc <file>${r}           Line/word/char count (-l, -w, -c)
  ${g}du [path]${r}           Directory size in MB
  ${g}df${r}                  Disk usage per drive

${c}Git${r}
${y}──────────────────────────────────────────${r}
  ${g}g${r}  ${g}ga${r}  ${g}gaa${r}  ${g}gb${r}         git / add / add --all / branch
  ${g}gc${r}  ${g}gc!${r}  ${g}gcam${r}           commit -v / amend / commit -a -m
  ${g}gco${r}  ${g}gcb${r}  ${g}gsw${r}  ${g}gswc${r}     checkout / checkout -b / switch / switch -c
  ${g}gd${r}  ${g}gds${r}  ${g}gf${r}  ${g}gl${r}        diff / diff --staged / fetch / pull
  ${g}gp${r}  ${g}gpf!${r}  ${g}gpr${r}           push / force-with-lease / pull --rebase
  ${g}gst${r}  ${g}glo${r}  ${g}gloga${r}          status / oneline log / graph log (all branches)
  ${g}lg${r}                  lazygit TUI

${c}Process & System${r}
${y}──────────────────────────────────────────${r}
  ${g}ps${r}                  Process list
  ${g}pgrep <pattern>${r}     Find processes by name pattern
  ${g}pkill <pattern>${r}     Kill processes by name pattern
  ${g}kill -Name/-Id${r}      Kill by exact name or PID
  ${g}k9 <n>${r}           Kill process by exact name (shorthand)
  ${g}sudo <cmd>${r}          Run elevated in new Windows Terminal window
  ${g}su${r}                  Open elevated Windows Terminal session
  ${g}sysinfo${r}             OS / CPU / RAM / hostname summary
  ${g}uptime${r}              Boot time and formatted uptime
  ${g}reboot${r}              Restart computer immediately
  ${g}poweroff${r}            Shut down computer immediately

${c}Network${r}
${y}──────────────────────────────────────────${r}
  ${g}pubip${r}               Public IP address
  ${g}flushdns${r}            Clear the Windows DNS cache
  ${g}netstat${r}             Active TCP connections
  ${g}curl <url>${r}          Invoke-WebRequest wrapper
  ${g}wget <url>${r}          Invoke-WebRequest wrapper (supports -OutFile)

${c}Text Utilities${r}
${y}──────────────────────────────────────────${r}
  ${g}cat${r}                 bat wrapper — syntax highlighting, no paging
  ${g}grep${r}                ripgrep (rg) alias
  ${g}find${r}                fd alias
  ${g}less${r}                bat with paging
  ${g}head <file>${r}         First N lines (default 10)
  ${g}tail <file>${r}         Last N lines (-Follow for live tail)
  ${g}sed <pat> <rep> [f]${r} Regex replace on file or pipe
  ${g}awk '{print \$N}'${r}    Basic column extraction
  ${g}sort${r}                Sort piped input (-r reverse, -u unique)
  ${g}uniq${r}                Deduplicate piped input
  ${g}tee <file>${r}          Write to file and stdout simultaneously
  ${g}xargs <cmd>${r}         Pipe lines as arguments to a command
  ${g}man <cmd>${r}           Get-Help output rendered via bat
  ${g}history [n]${r}         Show last N commands (default 50)

${c}Clipboard & Open${r}
${y}──────────────────────────────────────────${r}
  ${g}pbcopy${r}              Pipe to Windows clipboard
  ${g}pbpaste${r}             Print from Windows clipboard
  ${g}open / xdg-open${r}     Open file with default app, or explorer .

${c}Environment${r}
${y}──────────────────────────────────────────${r}
  ${g}env${r}                 List all environment variables (sorted)
  ${g}export X=Y${r}          Set a persistent user environment variable
  ${g}unset X${r}             Remove an environment variable
  ${g}which <cmd>${r}         Show full path of a command

${c}jq${r}
${y}──────────────────────────────────────────${r}
  ${g}jqpretty${r}            Pretty-print JSON from pipe
  ${g}jqkeys${r}              Print top-level keys from pipe

${c}Utilities${r}
${y}──────────────────────────────────────────${r}
  ${g}reload${r}              Reload this profile in the current session
  ${g}editprofile${r}  ${g}ep${r}    Open profile in \$EDITOR
  ${g}edit <file>${r}         Open file in \$EDITOR (code --wait → codium --wait → notepad++ → sublime_text → notepad)
  ${g}Update-ProfileModules${r} Update common profile modules from PSGallery
  ${g}Update-PowerShellRuntime${r} Update PowerShell via GitHub + winget
  ${g}serve [port]${r}        Python HTTP server in current dir (default 8000)
  ${g}cloc-simple${r}         Count lines of code by file extension
"@
}

# Hint at the bottom of startup
Write-Host "Type $($PSStyle.Foreground.Green)Show-Help$($PSStyle.Reset) for a command reference." -ForegroundColor DarkGray
Write-Host "pwsh $($PSVersionTable.PSVersion)  $(Get-Date -Format 'ddd dd MMM yyyy')" -ForegroundColor DarkGray

# ─── Zoxide (smarter cd) ─────────────────────────────────────────────────────

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
# ─── End of Profile ──────────────────────────────────────────────────────────


