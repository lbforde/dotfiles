# Dotfiles

Dotfiles and bootstrap scripts for rebuilding this dev environment with `chezmoi`.

## Platform Support

| Platform | Status    | Notes                                            |
| -------- | --------- | ------------------------------------------------ |
| Windows  | Supported | Bootstrapped via `scripts/bootstrap.ps1`         |
| WSL      | Supported | Bootstrapped via `scripts/bootstrap-wsl.sh`      |
| Linux    | Planned   | No bootstrap script or manifest in this repo yet |
| macOS    | Planned   | No bootstrap script or manifest in this repo yet |

## Windows Setup

Run the bootstrap from Windows PowerShell 5.1 as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\bootstrap.ps1
```

Useful options:

```powershell
.\scripts\bootstrap.ps1 -DevDrive "D:"
.\scripts\bootstrap.ps1 -ChezmoiRepo "https://github.com/yourname/dotfiles"
```

What the bootstrap handles:

- Installs the current winget packages, PowerShell modules, and VS Code extensions from `manifests/windows.packages.json`
- Sets Dev Drive environment variables and PATH entries needed by the shell and toolchain
- Initializes and applies `chezmoi` from this repo by default, with backup steps for older local state
- Runs `.\scripts\sync-mise.ps1` after apply so managed CLI tools are installed and shims are refreshed

First run notes:

- You may be prompted for your git name and email if local `chezmoi` data does not exist yet
- If `DEV_DRIVE` is not already set, the script can prompt for a drive letter unless you pass `-DevDrive`
- Existing `chezmoi` source state or local editor settings can be backed up before the script switches to the current repo
- If you launch from `pwsh`, the script skips self-upgrading the active PowerShell session

After bootstrap, open a new shell and run a few quick checks:

```powershell
echo $PROFILE.CurrentUserCurrentHost
chezmoi source-path
mise --version
code --list-extensions
```

Optional first-login commands:

```powershell
gh auth login
doppler login
gopass setup
```

## WSL Ubuntu Setup

Run the bootstrap from inside Ubuntu on WSL:

```bash
bash ./scripts/bootstrap-wsl.sh
```

Useful option:

```bash
bash ./scripts/bootstrap-wsl.sh --chezmoi-repo "https://github.com/yourname/dotfiles"
```

What the bootstrap handles:

- Installs the current Ubuntu bootstrap packages from `manifests/wsl.packages.json`
- Installs `mise` and bootstraps `chezmoi` if they are not already available
- Initializes and applies `chezmoi` from this repo by default
- Runs `./scripts/sync-mise.sh` so managed CLI tools are installed and shims are refreshed
- Changes the login shell to `zsh` when needed

First run notes:

- You may be prompted for your git name and email if local `chezmoi` data does not exist yet
- VS Code and Nerd Fonts are intentionally not installed in WSL; this repo expects you to use the Windows host copies
- The shell prompt stays on the shared `starship` config, while `zinit` manages `fzf-tab`, `zsh-completions`, `zsh-autosuggestions`, and `zsh-syntax-highlighting`

After bootstrap, open a new Ubuntu shell and run a few quick checks:

```bash
echo "$SHELL"
chezmoi source-path
mise --version
zsh -lic 'command -v zsh starship mise zoxide fzf opencode'
```

Optional first-login commands:

```bash
gh auth login
doppler login
gopass setup
```

## What's Managed Here

- `scripts/bootstrap.ps1`: current bootstrap entry point for Windows
- `scripts/bootstrap-wsl.sh`: bootstrap entry point for Ubuntu on WSL
- `scripts/sync-mise.ps1`: installs and validates the current managed `mise` toolset
- `scripts/sync-mise.sh`: Linux `mise` sync companion for WSL/Linux applies
- `manifests/windows.packages.json`: winget packages, PowerShell modules, and VS Code extensions
- `manifests/wsl.packages.json`: Ubuntu bootstrap packages used by the WSL setup
- `home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`: PowerShell profile, aliases, helper functions, and shell environment defaults
- `home/dot_zshrc`: WSL/Linux shell profile managed as `~/.zshrc`
- `home/AppData/Roaming/Code/User/settings.json`: VS Code settings applied through `chezmoi`
- `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`: Windows Terminal settings applied through `chezmoi`

Right now this repo manages:

- Shell behavior in PowerShell, including editor selection and helper commands such as `edit` and `Show-Help`
- Shell behavior in WSL `zsh`, including `zinit`, `fzf-tab`, shared prompt config, and Linux-friendly aliases
- VS Code defaults, extensions, and document-authoring settings
- Windows Terminal profiles and keybindings
- Installed CLI tools and runtimes through the bootstrap plus `mise`

## Daily Workflow

Common `chezmoi` commands:

```powershell
chezmoi diff
chezmoi status
chezmoi apply
```

When you change managed tooling and want to resync it:

```powershell
.\scripts\sync-mise.ps1
```

```bash
./scripts/sync-mise.sh
```

When you edit a destination file directly and want to backport it into source state:

```powershell
chezmoi status
chezmoi re-add "<destination-path>"
chezmoi diff
chezmoi apply
```

If the backported change belongs in this repo, follow up with normal `git add`, `git commit`, and `git push`.

## Files You'll Actually Edit

- `manifests/windows.packages.json` when you want to add or remove winget packages, modules, or VS Code extensions
- `manifests/wsl.packages.json` when you want to change the Ubuntu bootstrap packages
- `home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` when you want to adjust aliases, prompt behavior, PATH-related setup, or helper commands
- `home/dot_zshrc` when you want to adjust WSL shell behavior, plugin loading, aliases, or prompt initialization
- `home/AppData/Roaming/Code/User/settings.json` when you want to change editor defaults or extension behavior
- `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` when you want to change terminal profiles, appearance, or keybindings

If you change managed files, re-apply with:

```powershell
chezmoi apply
```
