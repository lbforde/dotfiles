# Dotfiles

Dotfiles and bootstrap scripts for rebuilding this dev environment with `chezmoi`.

## Platform Support

| Platform | Status    | Notes                                            |
| -------- | --------- | ------------------------------------------------ |
| Windows  | Supported | Bootstrapped via `scripts/bootstrap.ps1`         |
| WSL      | Supported | Bootstrapped via `scripts/bootstrap-wsl.sh`      |
| Linux    | Planned   | No bootstrap script or manifest in this repo yet |
| macOS    | Supported | Bootstrapped via `scripts/bootstrap-macos.sh`    |

## Windows Setup

Install the two explicit prerequisites first:

```powershell
winget install --exact --id Git.Git
winget install --exact --id twpayne.chezmoi
```

Then initialise and apply the dotfiles:

```powershell
chezmoi init --apply <github-repo-url>
```

Useful options:

```powershell
chezmoi init --apply yourname/dotfiles
chezmoi init --apply https://github.com/yourname/dotfiles
```

Fallback manual bootstrap from an existing local checkout:

```powershell
.\scripts\bootstrap.ps1 -DevDrive "D:"
.\scripts\bootstrap.ps1 -ChezmoiRepo "https://github.com/yourname/dotfiles"
```

What the bootstrap handles:

- Installs the current winget packages and PowerShell modules from `manifests/windows.packages.json`
- Installs the shared VS Code extension set from `manifests/vscode.extensions.json`
- Sets Dev Drive environment variables and PATH entries needed by the shell and toolchain
- Creates or reuses `~/.ssh/github_personal_key`, enables the Windows `ssh-agent` service, and loads the key for GitHub auth plus Git SSH signing
- Renders `~/.ssh/config` and `~/.ssh/allowed_signers` through `chezmoi`
- Runs during the first Windows `chezmoi` apply via a `read-source-state.pre` hook, then stays out of the way on later applies
- Runs `.\scripts\sync-mise.ps1` after apply so managed CLI tools are installed and shims are refreshed

First run notes:

- `chezmoi init` creates the local `~/.config/chezmoi/chezmoi.toml` from `home/.chezmoi.toml.tmpl` and prompts for your git name and email
- The first Windows apply can trigger a UAC prompt because `scripts/bootstrap.ps1` self-elevates when admin rights are needed
- If `~/.ssh/github_personal_key` does not exist yet, bootstrap prompts you to create it with a passphrase
- Bootstrap prints the public key after setup; add it to GitHub manually for both SSH auth and Git commit signing
- If `DEV_DRIVE` is not already set, the script can prompt for a drive letter unless you pass `-DevDrive`
- Running `.\scripts\bootstrap.ps1` manually still works for a checked-out repo and can switch `chezmoi` to a different source when needed
- If you launch from `pwsh`, the script skips self-upgrading the active PowerShell session

After bootstrap, open a new shell and run a few quick checks:

```powershell
echo $PROFILE.CurrentUserCurrentHost
chezmoi source-path
ssh-add -l
git config --global --get user.signingkey
mise --version
code --list-extensions
```

Optional first-login commands:

```powershell
gh auth login
doppler login
gopass setup
```

Register the generated SSH key with GitHub after `gh auth login`:

```powershell
gh auth status
gh ssh-key add "$env:USERPROFILE\.ssh\github_personal_key.pub" --type authentication --title "liam-windows-auth"
gh ssh-key add "$env:USERPROFILE\.ssh\github_personal_key.pub" --type signing --title "liam-windows-signing"
ssh -T git@github.com
```

If you want Git to prefer SSH over HTTPS for GitHub remotes after auth is working, set `github_use_ssh_instead_of_https = true` under `[data]` in your local `chezmoi.toml`.

## macOS Setup

Install Homebrew first, then the two explicit prerequisites:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install git chezmoi
```

Then initialise and apply the dotfiles:

```bash
chezmoi init --apply yourname/dotfiles
```

Useful options:

```bash
chezmoi init --apply https://github.com/yourname/dotfiles
```

Fallback manual bootstrap from an existing local checkout:

```bash
bash ./scripts/bootstrap-macos.sh
bash ./scripts/bootstrap-macos.sh --chezmoi-repo "https://github.com/yourname/dotfiles"
```

What the bootstrap handles:

- Installs the current macOS Homebrew formulae and casks from `manifests/macos.packages.json`
- Installs Ghostty as the intended macOS terminal emulator
- Installs VS Code plus the shared VS Code extension set from `manifests/vscode.extensions.json`
- Installs JetBrains Mono Nerd Font so the managed terminal and editor font settings render correctly
- Creates or reuses `~/.ssh/github_personal_key`, loads it into `ssh-agent`, and uses the macOS Keychain flow when available
- Renders `~/.ssh/config` and `~/.ssh/allowed_signers` through `chezmoi`
- Applies Ghostty config at `~/.config/ghostty/config.ghostty` using Ghostty's supported XDG config path on macOS
- Applies macOS VS Code settings at `~/Library/Application Support/Code/User/settings.json`
- Runs during the first macOS `chezmoi apply` via a `read-source-state.pre` hook, then stays out of the way on later applies
- Runs `./scripts/sync-mise.sh` so managed CLI tools are installed and shims are refreshed
- Changes the login shell to `zsh` when needed
- Makes `atuin` available through the shared `mise` toolchain, with shell initialization handled from the shared `zsh` profile

First run notes:

- `chezmoi init` creates the local `~/.config/chezmoi/chezmoi.toml` from `home/.chezmoi.toml.tmpl` and prompts for your git name and email
- The Homebrew VS Code cask provides the `code` CLI used for editor integration and extension installation
- If `~/.ssh/github_personal_key` does not exist yet, bootstrap prompts you to create it with a passphrase
- Bootstrap prints the public key after setup; add it to GitHub manually for both SSH auth and Git commit signing
- `~/.zshrc` now initializes Homebrew early so brew-installed tools are available in new shells on both Apple Silicon and Intel Macs
- Run `atuin import auto` once after bootstrap if you want to import existing shell history

After bootstrap, open Ghostty and run a few quick checks:

```bash
echo "$SHELL"
brew --prefix
chezmoi source-path
git config --global --get user.signingkey
mise --version
code --list-extensions
zsh -lic 'command -v brew code zsh starship mise atuin zoxide fzf yazi'
ssh-add -l
```

Optional first-login commands:

```bash
gh auth login
doppler login
gopass setup
```

Optional Atuin sync setup:

```bash
atuin import auto
atuin register -u <username> -e <email>
atuin sync
```

If you already registered Atuin on another machine, use `atuin login -u <username>` instead of `atuin register`, then run `atuin sync`.

Register the generated SSH key with GitHub after `gh auth login`:

```bash
gh auth status
gh ssh-key add ~/.ssh/github_personal_key.pub --type authentication --title "liam-mac-auth"
gh ssh-key add ~/.ssh/github_personal_key.pub --type signing --title "liam-mac-signing"
ssh -T git@github.com
```

If you want Git to prefer SSH over HTTPS for GitHub remotes after auth is working, set `github_use_ssh_instead_of_https = true` under `[data]` in your local `chezmoi.toml`.

## WSL Ubuntu Setup

Install the two explicit prerequisites first inside Ubuntu on WSL using your preferred method:

- `git`
- `chezmoi`

One straightforward path is:

```bash
sudo apt update
sudo apt install -y git curl
sh -c "$(curl -fsLS get.chezmoi.io)"
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
chezmoi init --apply yourname/dotfiles
```

Before you rely on Linux-side `mise` and other WSL-managed tools, disable automatic Windows PATH injection:

```bash
sudo nano /etc/wsl.conf
```

Add or merge:

```ini
[interop]
appendWindowsPath=false
```

Then restart WSL from Windows:

```powershell
wsl --shutdown
```

Then run the bootstrap from inside Ubuntu on WSL:

```bash
bash ./scripts/bootstrap-wsl.sh
```

Useful option:

```bash
bash ./scripts/bootstrap-wsl.sh --chezmoi-repo "https://github.com/yourname/dotfiles"
```

What the bootstrap handles:

- Installs the current Ubuntu bootstrap packages from `manifests/wsl.packages.json`
- Requires existing `git` and `chezmoi` installs, then initialises or applies this repo
- Runs automatically during the first WSL `chezmoi apply` via a `read-source-state.pre` hook, then stays out of the way on later applies
- Installs `keychain` and the WSL SSH tooling from the managed apt package list
- Creates or reuses `~/.ssh/github_personal_key` for GitHub auth and Git SSH signing
- Initializes and applies `chezmoi` from this repo by default
- Runs `./scripts/sync-mise.sh` so managed CLI tools are installed and shims are refreshed
- Changes the login shell to `zsh` when needed
- Makes `atuin` available through the shared `mise` toolchain, with shell initialization handled from the shared `zsh` profile

First run notes:

- `chezmoi init --apply` in WSL can now prompt for your git name and email through the first-apply bootstrap path when local `chezmoi` data does not exist yet
- `/etc/wsl.conf` should include `[interop]` with `appendWindowsPath=false` so WSL does not inherit the Windows toolchain PATH by default
- `bootstrap-wsl.sh` ensures `~/.local/bin` and `~/bin` are available in later login shells by appending a small PATH block to `~/.profile`
- If `~/.ssh/github_personal_key` does not exist yet, bootstrap prompts you to create it with a passphrase
- Bootstrap prints the public key after setup; add it to GitHub manually for both SSH auth and Git commit signing
- `keychain` is initialized from the shared `zsh` profile and restores the Linux-side `github_personal_key` in new shells
- VS Code and Nerd Fonts are intentionally not installed in WSL; this repo expects you to use the Windows host copies, with the VS Code CLI added back explicitly in `~/.zshrc` via `wslvar LOCALAPPDATA` plus `wslpath`
- The shell prompt stays on the shared `starship` config, while `zinit` manages `fzf-tab`, `zsh-completions`, `zsh-autosuggestions`, and `zsh-syntax-highlighting`
- Run `atuin import auto` once after bootstrap if you want to import existing shell history

After bootstrap, open a new Ubuntu shell and run a few quick checks:

```bash
echo "$SHELL"
chezmoi source-path
git config --global --get user.signingkey
mise --version
zsh -lic 'command -v zsh starship mise atuin zoxide fzf opencode keychain'
zsh -lic 'ssh-add -l'
```

Optional first-login commands:

```bash
gh auth login
doppler login
gopass setup
```

Optional Atuin sync setup:

```bash
atuin import auto
atuin register -u <username> -e <email>
atuin sync
```

If you already registered Atuin on another machine, use `atuin login -u <username>` instead of `atuin register`, then run `atuin sync`.

Register the generated SSH key with GitHub after `gh auth login`:

```bash
gh auth status
gh ssh-key add ~/.ssh/github_personal_key.pub --type authentication --title "liam-wsl-auth"
gh ssh-key add ~/.ssh/github_personal_key.pub --type signing --title "liam-wsl-signing"
ssh -T git@github.com
```

If you want Git to prefer SSH over HTTPS for GitHub remotes after auth is working, set `github_use_ssh_instead_of_https = true` under `[data]` in your local `chezmoi.toml`.

## What's Managed Here

- `home/.chezmoi.toml.tmpl`: init-time local config template and Windows/WSL/macOS first-apply hook wiring
- `scripts/bootstrap.ps1`: current bootstrap entry point for Windows
- `scripts/bootstrap-wsl.sh`: bootstrap entry point for Ubuntu on WSL
- `scripts/bootstrap-macos.sh`: bootstrap entry point for macOS
- `scripts/sync-mise.ps1`: installs and validates the current managed `mise` toolset
- `scripts/sync-mise.sh`: Linux `mise` sync companion for WSL/Linux applies
- `manifests/windows.packages.json`: winget packages and PowerShell modules
- `manifests/macos.packages.json`: Homebrew formulae and casks used by the macOS setup
- `manifests/vscode.extensions.json`: shared VS Code extensions installed on Windows and macOS
- `manifests/wsl.packages.json`: Ubuntu bootstrap packages used by the WSL setup
- `home/dot_ssh/config.tmpl`: shared SSH host config, including the GitHub identity stanza
- `home/dot_ssh/allowed_signers.tmpl`: shared Git SSH allowed signers file rendered from the local public key
- `home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`: PowerShell profile, aliases, helper functions, and shell environment defaults
- `home/dot_zshrc`: macOS/WSL/Linux shell profile managed as `~/.zshrc`
- `home/dot_config/ghostty/config.ghostty`: Ghostty config applied through the XDG config path
- `home/AppData/Roaming/Code/User/settings.json`: Windows VS Code settings applied through `chezmoi`
- `home/Library/Application Support/Code/User/settings.json`: macOS VS Code settings applied through `chezmoi`
- `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json`: Windows Terminal settings applied through `chezmoi`

Right now this repo manages:

- Shell behavior in PowerShell, including editor selection and helper commands such as `edit` and `Show-Help`
- Shell behavior in macOS/WSL `zsh`, including `zinit`, `fzf-tab`, shared prompt config, and Linux-friendly aliases
- Ghostty defaults on macOS, including font, padding, and background styling
- VS Code defaults, extensions, and document-authoring settings on Windows and macOS
- Windows Terminal profiles and keybindings
- Installed CLI tools and runtimes through the platform bootstrap plus `mise`

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

- `manifests/windows.packages.json` when you want to add or remove winget packages or PowerShell modules
- `manifests/macos.packages.json` when you want to change the macOS Homebrew bootstrap packages
- `manifests/vscode.extensions.json` when you want to change the shared VS Code extension set
- `manifests/wsl.packages.json` when you want to change the Ubuntu bootstrap packages
- `home/.chezmoi.toml.tmpl` when you want to change local `chezmoi` prompts, editor integration, or first-apply hook behavior
- `home/dot_ssh/config.tmpl` when you want to change the shared SSH host config for GitHub or other identities
- `home/dot_ssh/allowed_signers.tmpl` when you want to change how Git SSH signing trust is rendered from the local public key
- `home/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` when you want to adjust aliases, prompt behavior, PATH-related setup, or helper commands
- `home/dot_zshrc` when you want to adjust macOS/WSL shell behavior, plugin loading, aliases, or prompt initialization
- `home/dot_config/ghostty/config.ghostty` when you want to change macOS terminal font, padding, opacity, or colors
- `home/AppData/Roaming/Code/User/settings.json` when you want to change Windows editor defaults or extension behavior
- `home/Library/Application Support/Code/User/settings.json` when you want to change macOS editor defaults or extension behavior
- `home/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json` when you want to change terminal profiles, appearance, or keybindings

If you change managed files, re-apply with:

```powershell
chezmoi apply
```
