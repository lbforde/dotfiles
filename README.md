# Developer Environment Setup Guide (Windows + Linux)

Reproducible dotfiles + tooling bootstrap using Chezmoi and manifest-driven installs.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Manifest-Driven Installs](#manifest-driven-installs)
5. [Step-by-Step Installation (Windows)](#step-by-step-installation-windows)
6. [File Structure](#file-structure)
7. [PowerShell Profile Reference](#powershell-profile-reference)
8. [Windows Terminal Keybindings](#windows-terminal-keybindings)
9. [Chezmoi Dotfile Management](#chezmoi-dotfile-management)
10. [Tool Reference](#tool-reference)
11. [Customisation](#customisation)

---

## Overview

This setup gives you:

- Chezmoi-first dotfile deployment (single source of truth)
- Manifest-driven installs for packages, runtimes, and VS Code extensions
- Windows-focused bootstrap flow today, with Linux bootstrap scaffolded
- Runtime management with `mise`
- Terminal/editor stack with Windows Terminal, Starship, PowerShell profile, and VS Code settings

---

## Prerequisites

Windows:
- Windows 10 22H2+ or Windows 11
- PowerShell 5.1 (for bootstrap invocation)
- Internet connection
- Administrator rights for bootstrap

Linux (Ubuntu/Arch, including WSL2):
- `bash`, `python3`, `sudo`
- Internet connection
- Sudo-capable user

---

## Quick Start

### Windows

Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\bootstrap.ps1
```

Optional:

```powershell
.\scripts\bootstrap.ps1 -DevDrive "D:"
.\scripts\bootstrap.ps1 -ChezmoiRepo "https://github.com/yourname/dotfiles"
```

First run behavior:
- Prompts for git name/email if local `~/.config/chezmoi/chezmoi.toml` is missing.
- Creates local `~/.config/chezmoi/chezmoi.toml` once (machine-local, untracked by source-state).
- Auto-migrates existing local chezmoi `[edit]`/`[merge]`/`[diff]` settings to VS Code defaults, with timestamped backup.

### Linux (Ubuntu / Arch / WSL2)

```bash
chmod +x ./scripts/bootstrap-linux.sh
./scripts/bootstrap-linux.sh
```

Useful options:

```bash
./scripts/bootstrap-linux.sh --dry-run
./scripts/bootstrap-linux.sh --skip-runtimes
./scripts/bootstrap-linux.sh --manifest manifests/linux.ubuntu.packages.json
./scripts/bootstrap-linux.sh --manifest manifests/linux.arch.packages.json
```

Note:
- Linux manifests are placeholders for now. The script is wired, but package/runtime lists are intentionally empty.

---

## Manifest-Driven Installs

Bootstrap reads install inventories from:

- `manifests/windows.packages.json`
  - Scoop buckets/tools
  - PowerShell modules
  - Winget packages (PowerShell + Windows Terminal)
  - Doppler bucket/package
- `manifests/windows.runtimes.json`
  - Global `mise` runtime list
- `manifests/windows.vscode-extensions.json`
  - VS Code extension install list
- `manifests/linux.ubuntu.packages.json` (placeholder)
- `manifests/linux.arch.packages.json` (placeholder)

Scripts consuming manifests:

- `scripts/bootstrap.ps1`
- `scripts/install-vscode-extensions.ps1`
- `scripts/bootstrap-linux.sh`

Linux manifest schema (placeholder-ready):

- `packageManager`: `apt` or `pacman`
- `systemPackages`: distro packages
- `miseRuntimes`: runtime identifiers (e.g. `node@lts`)

---

## Step-by-Step Installation (Windows)

### 1. Bootstrap

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\bootstrap.ps1
```

### 2. What bootstrap does

- Installs Scoop and configured buckets/tools
- Installs PowerShell 7 (winget)
- Installs Windows Terminal (winget)
- Installs PowerShell modules
- Installs configured `mise` runtimes
- Configures Dev Drive directories and environment variables
- Adds Dev Drive `mise` shims (`<DevDrive>\tools\mise\shims`) to user PATH
- Runs `mise reshim` so runtime binaries (for example `go`) are immediately available
- Validates configured runtime commands are resolvable on PATH (fails fast if not)
- Sets up Chezmoi (init/apply) and deploys managed dotfiles
- Syncs PowerShell profile to the real `$PROFILE.CurrentUserAllHosts` path when Documents is redirected
- Installs VS Code extensions from manifest

### 3. Post-bootstrap auth

```powershell
gh auth login
doppler login
gopass setup
```

### 4. First launch workflow

1. Open Windows Terminal.
2. Start `pwsh` and confirm your profile loaded.
3. Open VS Code and verify extensions/settings were applied.

---

## File Structure

```text
dotfiles/
|-- .chezmoiroot
|-- examples/
|   `-- chezmoi/
|       `-- chezmoi.toml.example
|-- manifests/
|   |-- windows.packages.json
|   |-- windows.runtimes.json
|   |-- windows.vscode-extensions.json
|   |-- linux.ubuntu.packages.json
|   `-- linux.arch.packages.json
|-- scripts/
|   |-- bootstrap.ps1
|   |-- bootstrap-linux.sh
|   `-- install-vscode-extensions.ps1
`-- home/
    |-- .chezmoiignore.tmpl
    |-- dot_gitconfig.tmpl
    |-- Documents/PowerShell/profile.ps1
    |-- scoop/persist/vscode/data/user-data/User/settings.json
    |-- AppData/Local/Packages/
    |   `-- Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json
    `-- dot_config/
        `-- starship.toml
```

Conventions:

- `.chezmoiroot` points source-state at `home/`.
- `dot_` prefix maps to leading `.` in destination paths.
- `.chezmoiignore.tmpl` is template-based platform routing.
- Local `~/.config/chezmoi/chezmoi.toml` is machine-local and intentionally untracked by source-state.

---

## PowerShell Profile Reference

Source-state path:
- `home/Documents/PowerShell/profile.ps1`

Chezmoi-managed path (non-redirected default):
- `%USERPROFILE%\Documents\PowerShell\profile.ps1`

Actual PowerShell runtime path:
- `$PROFILE.CurrentUserAllHosts`
- If Documents is redirected (for example `D:\Documents`), bootstrap mirrors the managed profile to this runtime path automatically.

Quick verification:
- `echo $PROFILE.CurrentUserAllHosts`
- `Test-Path $PROFILE.CurrentUserAllHosts`

Highlights:
- Dev Drive environment routing
- Linux-style aliases/functions
- VS Code-first `$EDITOR` resolution (`code --wait`)
- `edit <file>` alias for opening files in `$EDITOR` (replaces Vim-style naming)
- Argument completers (`git`, `winget`, `gh`, `mise`, `chezmoi`, etc.)
- `Show-Help` command for in-shell command reference

---

## Windows Terminal Keybindings

Managed settings path:
- `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`

Keybindings (balanced port):

- `Alt+Shift+-` split pane vertical
- `Alt+Shift+\` split pane horizontal
- `Alt+h/j/k/l` move pane focus
- `Alt+Shift+h/j/k/l` resize panes
- `Alt+Shift+c` new tab
- `Alt+n / Alt+p` next/prev tab
- `Alt+Shift+z` toggle pane zoom
- `Alt+Shift+x` close pane
- `Ctrl+Shift+c / Ctrl+Shift+v` copy/paste
- `Ctrl+Shift+f` find

---

## Chezmoi Dotfile Management

Bootstrap behavior:

- `-ChezmoiRepo` provided: init/apply from that source.
- Not provided: init/apply from current checked-out repo.
- Already initialized with different source: warn, keep existing source, run `chezmoi apply`.
- Existing local `~/.config/chezmoi/chezmoi.toml`: editor sections are migrated to VS Code defaults and backup is created.

Daily workflow:

```powershell
czmd          # chezmoi diff
czma          # chezmoi apply
czms          # chezmoi status
czmu          # chezmoi update
czmadd <path> # chezmoi add
```

Git identity data:

- `dot_gitconfig.tmpl` uses `{{ .name }}` and `{{ .email }}`.
- Values come from local `~/.config/chezmoi/chezmoi.toml`.
- Example template: `examples/chezmoi/chezmoi.toml.example`.

---

## Tool Reference

### VS Code

- Settings managed on Windows via Chezmoi target:
  - `%USERPROFILE%\scoop\persist\vscode\data\user-data\User\settings.json`
- Scoop path note:
  - `%USERPROFILE%\scoop\apps\vscode\current\data\user-data\User` points to the same persisted data.
- Migration note:
  - Legacy `%APPDATA%\Code\User\settings.json` may remain on disk but is no longer managed by this repo for Scoop VS Code installs.
- Extensions installed via:
  - `manifests/windows.vscode-extensions.json`
  - `.\scripts\install-vscode-extensions.ps1`
- Formatter policy:
  - Format on save is enabled with language-specific formatters (for example: Ruff for Python, Prettier for web/text formats, and language-native formatter extensions for Go/Rust/PowerShell/C/C++).
  - Save-time safe fixes are explicitly enabled for ESLint and Ruff.

### Windows Terminal

- Settings managed on Windows via Chezmoi target:
  - `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
- Installed by bootstrap via winget package:
  - `Microsoft.WindowsTerminal`

### Runtimes

- Managed by `mise`.
- Global runtime list from `manifests/windows.runtimes.json`.
- Bootstrap persists the `mise` shims path to user PATH and refreshes shims after install.
- Quick verification:
  - `mise which go`
  - `where.exe go`
  - `go version`

Repair existing machine (if runtime commands are missing):

```powershell
$devDrive = [Environment]::GetEnvironmentVariable("DEV_DRIVE", "User")
if (-not $devDrive) { $devDrive = "Z:" }

$miseDataDir = "$devDrive\tools\mise"
$miseShims = "$miseDataDir\shims"

New-Item -ItemType Directory -Path $miseShims -Force | Out-Null
[Environment]::SetEnvironmentVariable("MISE_DATA_DIR", $miseDataDir, "User")

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$miseShims*") {
  [Environment]::SetEnvironmentVariable("Path", "$miseShims;$userPath", "User")
}

$env:MISE_DATA_DIR = $miseDataDir
$env:Path = "$miseShims;$env:Path"

mise reshim

where.exe go
go version
```

Then close all terminals and VS Code windows, and reopen.

### Git Commit Signing (SSH)

Use this if you want signed commits in terminal and VS Code without GPG.

```powershell
git config --global gpg.format ssh
git config --global user.signingkey "<SSH_PUBLIC_KEY_PATH>"
git config --global commit.gpgsign true
git config --global gpg.ssh.allowedSignersFile "$env:USERPROFILE\.ssh\allowed_signers"
```

Create/update `~/.ssh/allowed_signers` with one line:

```text
<SIGNING_EMAIL> namespaces="git" <KEY_TYPE> <BASE64_KEY_DATA>
```

Placeholder guide:
- `<SSH_PUBLIC_KEY_PATH>`: path to your signing public key, for example `$env:USERPROFILE\.ssh\github_signing_key.pub`
- `<SIGNING_EMAIL>`: the value from `git config user.email`
- `<KEY_TYPE> <BASE64_KEY_DATA>`: copy the key type + base64 payload from the `.pub` file

Verification:

```powershell
git config --global --get gpg.format
git config --global --get user.signingkey
git config --global --get commit.gpgsign
git log --show-signature -1
```

---

## Customisation

Main files to edit:

- `home/dot_config/starship.toml`
- `home/Documents/PowerShell/profile.ps1`
- `home/scoop/persist/vscode/data/user-data/User/settings.json`
- `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`
- `manifests/windows.packages.json`
- `manifests/windows.runtimes.json`
- `manifests/windows.vscode-extensions.json`

After updates:

```powershell
chezmoi apply
```
