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
8. [WezTerm Keybindings](#wezterm-keybindings)
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
- Terminal/editor stack with WezTerm, Starship, PowerShell profile, and VS Code settings

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
  - Winget packages
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
- Installs PowerShell modules
- Installs configured `mise` runtimes
- Configures Dev Drive directories and environment variables
- Sets up Chezmoi (init/apply) and deploys managed dotfiles
- Installs VS Code extensions from manifest

### 3. Post-bootstrap auth

```powershell
gh auth login
doppler login
gopass setup
```

### 4. First Neovim launch

```powershell
nvim
```

---

## File Structure

```text
dotfiles/
├── .chezmoiroot
├── examples/
│   └── chezmoi/
│       └── chezmoi.toml.example
├── manifests/
│   ├── windows.packages.json
│   ├── windows.runtimes.json
│   ├── windows.vscode-extensions.json
│   ├── linux.ubuntu.packages.json
│   └── linux.arch.packages.json
├── scripts/
│   ├── bootstrap.ps1
│   ├── bootstrap-linux.sh
│   └── install-vscode-extensions.ps1
└── home/
    ├── .chezmoiignore.tmpl
    ├── dot_gitconfig.tmpl
    ├── Documents/PowerShell/profile.ps1
    ├── AppData/Roaming/Code/User/settings.json
    └── dot_config/
        ├── wezterm/wezterm.lua
        └── starship.toml
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

Applied Windows target:
- `%USERPROFILE%\Documents\PowerShell\profile.ps1`

Highlights:

- Dev Drive environment routing
- Linux-style aliases/functions
- Argument completers (`git`, `winget`, `gh`, `mise`, `chezmoi`, etc.)
- `Show-Help` command for in-shell command reference

---

## WezTerm Keybindings

Leader key: `Ctrl+A`

Common bindings:

- `Leader + |` split horizontal
- `Leader + -` split vertical
- `Leader + h/j/k/l` move panes
- `Leader + H/J/K/L` resize panes
- `Leader + c` new tab
- `Leader + n/p` next/prev tab
- `Leader + r` reload config

---

## Chezmoi Dotfile Management

Bootstrap behavior:

- `-ChezmoiRepo` provided: init/apply from that source.
- Not provided: init/apply from current checked-out repo.
- Already initialized with different source: warn, keep existing source, run `chezmoi apply`.

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
  - `%APPDATA%\Code\User\settings.json`
- Extensions installed via:
  - `manifests/windows.vscode-extensions.json`
  - `.\scripts\install-vscode-extensions.ps1`

### Runtimes

- Managed by `mise`.
- Global runtime list from `manifests/windows.runtimes.json`.

### Neovim

- Installed via Scoop.
- Kickstart cloned by bootstrap if no existing config found.

---

## Customisation

Main files to edit:

- `home/dot_config/starship.toml`
- `home/dot_config/wezterm/wezterm.lua`
- `home/Documents/PowerShell/profile.ps1`
- `home/AppData/Roaming/Code/User/settings.json`
- `manifests/windows.packages.json`
- `manifests/windows.runtimes.json`
- `manifests/windows.vscode-extensions.json`

After updates:

```powershell
chezmoi apply
```

---

Maintained for this repo; keep docs aligned with script behavior.
