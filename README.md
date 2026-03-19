# Dotfiles

Dotfile setup to easily get a development environment started on multiple machines with `chezmoi`.

## What's Managed Here

This repo rebuilds the day-to-day development environment for Windows, WSL Ubuntu, and macOS with `chezmoi`, platform bootstrap scripts, and shared manifests.

It currently manages:

- Shell behavior in PowerShell and `zsh`, including prompt, completions, aliases, and PATH setup
- Editor and terminal defaults for VS Code, Windows Terminal, and Ghostty
- SSH config, Git signing setup, and first-apply bootstrap behavior
- CLI tools, runtimes, fonts, and VS Code extensions installed through platform manifests plus `mise`

Most changes land in `manifests/`, `scripts/`, or `home/` depending on whether you are changing installed tools, bootstrap behavior, or the managed dotfiles themselves.

## Platform Support

| Platform   | Status    | Notes                                            |
| ---------- | --------- | ------------------------------------------------ |
| 🪟 Windows | Supported | Bootstrapped via `scripts/bootstrap.ps1`         |
| 🧩 WSL     | Supported | Bootstrapped via `scripts/bootstrap-wsl.sh`      |
| 🐧 Linux   | Planned   | No bootstrap script or manifest in this repo yet |
| 🍎 macOS   | Supported | Bootstrapped via `scripts/bootstrap-macos.sh`    |

## Tools

These tables show what this repo installs or syncs after running the platform bootstrap. They are grouped by workflow so related tools stay together.

<details>
<summary><strong>Shell and Terminal</strong></summary>

| Name                                                                                                        | 🪟  | 🧩  | 🐧  | 🍎  | Description                          |
| ----------------------------------------------------------------------------------------------------------- | --- | --- | --- | --- | ------------------------------------ |
| [PowerShell](https://github.com/PowerShell/PowerShell)                                                      | ✅  | ❌  | ❌  | ❌  | Shell and scripting language         |
| [Zsh](https://www.zsh.org/)                                                                                 | ❌  | ✅  | ❌  | ❌  | Interactive Unix shell               |
| [Windows Terminal](https://github.com/microsoft/terminal)                                                   | ✅  | ❌  | ❌  | ❌  | Multi-tab Windows terminal           |
| [Ghostty](https://github.com/ghostty-org/ghostty)                                                           | ❌  | ❌  | ❌  | ✅  | GPU-accelerated terminal             |
| [JetBrains Mono Nerd Font](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/JetBrainsMono) | ✅  | ❌  | ❌  | ✅  | Patched developer font               |
| [starship](https://github.com/starship/starship)                                                            | ✅  | ✅  | ❌  | ✅  | Customizable shell prompt            |
| [atuin](https://github.com/atuinsh/atuin)                                                                   | ❌  | ✅  | ❌  | ✅  | Searchable shell history             |
| [zoxide](https://github.com/ajeetdsouza/zoxide)                                                             | ✅  | ✅  | ❌  | ✅  | Smarter `cd` command                 |
| [eza](https://github.com/eza-community/eza)                                                                 | ✅  | ✅  | ❌  | ✅  | Modern `ls` alternative              |
| [bat](https://github.com/sharkdp/bat)                                                                       | ✅  | ✅  | ❌  | ✅  | `cat` clone with syntax highlighting |
| [fd](https://github.com/sharkdp/fd)                                                                         | ✅  | ✅  | ❌  | ✅  | Fast, user-friendly `find`           |
| [fzf](https://github.com/junegunn/fzf)                                                                      | ✅  | ✅  | ❌  | ✅  | Command-line fuzzy finder            |
| [yazi](https://github.com/sxyazi/yazi)                                                                      | ✅  | ✅  | ❌  | ✅  | Fast terminal file manager           |
| [opencode](https://github.com/opencode-ai/opencode)                                                         | ❌  | ✅  | ❌  | ✅  | AI coding agent for the terminal     |
| [PSReadLine](https://github.com/PowerShell/PSReadLine)                                                      | ✅  | ❌  | ❌  | ❌  | Readline for PowerShell              |
| [PSFzf](https://github.com/kelleyma49/PSFzf)                                                                | ✅  | ❌  | ❌  | ❌  | `fzf` wrapper for PowerShell         |
| [Terminal-Icons](https://github.com/devblackops/Terminal-Icons)                                             | ✅  | ❌  | ❌  | ❌  | File and folder icons                |
| [posh-git](https://github.com/dahlbyk/posh-git)                                                             | ✅  | ❌  | ❌  | ❌  | Git prompt for PowerShell            |

</details>

<details>
<summary><strong>Visual Studio Code and Extensions</strong></summary>

In WSL, `🔗` means this repo reuses the Windows host install and extension set instead of installing a separate Linux-side copy.

| Name                                                                                                                           | 🪟  | 🧩  | 🐧  | 🍎  | Description                           |
| ------------------------------------------------------------------------------------------------------------------------------ | --- | --- | --- | --- | ------------------------------------- |
| [Visual Studio Code](https://github.com/microsoft/vscode)                                                                      | ✅  | 🔗  | ❌  | ✅  | Code editor                           |
| [One Dark Pro](https://marketplace.visualstudio.com/items?itemName=zhuangtongfa.Material-theme)                                | ✅  | 🔗  | ❌  | ✅  | One Dark theme for VS Code            |
| [Error Lens](https://marketplace.visualstudio.com/items?itemName=usernamehw.errorlens)                                         | ✅  | 🔗  | ❌  | ✅  | Highlights diagnostics inline         |
| [GitLens - Git supercharged](https://marketplace.visualstudio.com/items?itemName=eamodio.gitlens)                              | ✅  | 🔗  | ❌  | ✅  | Git insights and blame                |
| [Codex - OpenAI's coding agent](https://marketplace.visualstudio.com/items?itemName=openai.chatgpt)                            | ✅  | 🔗  | ❌  | ✅  | Coding agent for VS Code              |
| [Prettier - Code formatter](https://marketplace.visualstudio.com/items?itemName=esbenp.prettier-vscode)                        | ✅  | 🔗  | ❌  | ✅  | Formats code with Prettier            |
| [Todo Tree](https://marketplace.visualstudio.com/items?itemName=Gruntfuggly.todo-tree)                                         | ✅  | 🔗  | ❌  | ✅  | Shows TODO and FIXME tags             |
| [Pretty TypeScript Errors](https://marketplace.visualstudio.com/items?itemName=yoavbls.pretty-ts-errors)                       | ✅  | 🔗  | ❌  | ✅  | Improves TypeScript errors            |
| [Version Lens](https://marketplace.visualstudio.com/items?itemName=pflannery.vscode-versionlens)                               | ✅  | 🔗  | ❌  | ✅  | Shows latest package versions         |
| [Console Ninja](https://marketplace.visualstudio.com/items?itemName=WallabyJs.console-ninja)                                   | ✅  | 🔗  | ❌  | ✅  | Shows logs beside code                |
| [ESLint](https://marketplace.visualstudio.com/items?itemName=dbaeumer.vscode-eslint)                                           | ✅  | 🔗  | ❌  | ✅  | Integrates ESLint                     |
| [Nilesoft Shell File Formatter](https://marketplace.visualstudio.com/items?itemName=code-nature.nilesoft-shell-file-formatter) | ✅  | 🔗  | ❌  | ✅  | Nilesoft Shell syntax support         |
| [Python](https://marketplace.visualstudio.com/items?itemName=ms-python.python)                                                 | ✅  | 🔗  | ❌  | ✅  | Python language support               |
| [Ruff](https://marketplace.visualstudio.com/items?itemName=charliermarsh.ruff)                                                 | ✅  | 🔗  | ❌  | ✅  | Python linter and formatter           |
| [autoDocstring - Python Docstring Generator](https://marketplace.visualstudio.com/items?itemName=njpwerner.autodocstring)      | ✅  | 🔗  | ❌  | ✅  | Generates Python docstrings           |
| [rust-analyzer](https://marketplace.visualstudio.com/items?itemName=rust-lang.rust-analyzer)                                   | ✅  | 🔗  | ❌  | ✅  | Rust language server                  |
| [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb)                                            | ✅  | 🔗  | ❌  | ✅  | LLDB debugger for native code         |
| [Dependi](https://marketplace.visualstudio.com/items?itemName=fill-labs.dependi)                                               | ✅  | 🔗  | ❌  | ✅  | Dependency and vulnerability insights |
| [Even Better TOML](https://marketplace.visualstudio.com/items?itemName=tamasfe.even-better-toml)                               | ✅  | 🔗  | ❌  | ✅  | TOML language support                 |
| [Go](https://marketplace.visualstudio.com/items?itemName=golang.go)                                                            | ✅  | 🔗  | ❌  | ✅  | Go language support                   |
| [Lua](https://marketplace.visualstudio.com/items?itemName=sumneko.lua)                                                         | ✅  | 🔗  | ❌  | ✅  | Lua language server                   |
| [Zig Language](https://marketplace.visualstudio.com/items?itemName=ziglang.vscode-zig)                                         | ✅  | 🔗  | ❌  | ✅  | Zig language support                  |
| [clangd](https://marketplace.visualstudio.com/items?itemName=llvm-vs-code-extensions.vscode-clangd)                            | ✅  | 🔗  | ❌  | ✅  | C/C++ completion and navigation       |
| [CMake Tools](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cmake-tools)                                       | ✅  | 🔗  | ❌  | ✅  | Extended CMake support                |
| [Remote Development](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.vscode-remote-extensionpack)         | ✅  | 🔗  | ❌  | ✅  | Remote, WSL, and container access     |
| [Container Tools](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-containers)                         | ✅  | 🔗  | ❌  | ✅  | Manage and debug containers           |
| [LaTeX Workshop](https://marketplace.visualstudio.com/items?itemName=james-yu.latex-workshop)                                  | ✅  | 🔗  | ❌  | ✅  | LaTeX editing and preview             |
| [LTeX+](https://marketplace.visualstudio.com/items?itemName=ltex-plus.vscode-ltex-plus)                                        | ✅  | 🔗  | ❌  | ✅  | Grammar and spell checking            |
| [Print](https://marketplace.visualstudio.com/items?itemName=pdconsec.vscode-print)                                             | ✅  | 🔗  | ❌  | ✅  | Rendered Markdown and code            |
| [YAML](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml)                                                 | ✅  | 🔗  | ❌  | ✅  | YAML support with Kubernetes schemas  |
| [PowerShell](https://marketplace.visualstudio.com/items?itemName=ms-vscode.powershell)                                         | ✅  | 🔗  | ❌  | ✅  | PowerShell language support           |

</details>

<details>
<summary><strong>Languages and Toolchains</strong></summary>

| Name                                                                 | �   | �🧩 | 🐧  | 🍎  | Description                    |
| -------------------------------------------------------------------- | --- | --- | --- | --- | ------------------------------ |
| [mise](https://github.com/jdx/mise)                                  | ✅  | ✅  | ❌  | ✅  | Dev tools, env vars, and tasks |
| [Bun](https://github.com/oven-sh/bun)                                | ✅  | ✅  | ❌  | ✅  | JS runtime and package manager |
| [Node.js](https://github.com/nodejs/node)                            | ✅  | ✅  | ❌  | ✅  | JavaScript runtime             |
| [pnpm](https://github.com/pnpm/pnpm)                                 | ✅  | ✅  | ❌  | ✅  | Disk-efficient package manager |
| [Python](https://github.com/python/cpython)                          | ✅  | ✅  | ❌  | ✅  | Python programming language    |
| [Go](https://github.com/golang/go)                                   | ✅  | ✅  | ❌  | ✅  | Go programming language        |
| [Rust](https://github.com/rust-lang/rust)                            | ✅  | ✅  | ❌  | ✅  | Reliable systems language      |
| [Eclipse Temurin 21](https://github.com/adoptium/temurin21-binaries) | ✅  | ✅  | ❌  | ✅  | OpenJDK 21 distribution        |
| [Zig](https://github.com/ziglang/zig)                                | ✅  | ✅  | ❌  | ✅  | Zig programming language       |
| [CMake](https://github.com/Kitware/CMake)                            | ✅  | ✅  | ❌  | ✅  | Cross-platform build system    |

</details>

<details>
<summary><strong>Git, SSH, and Secrets</strong></summary>

| Name                                                   | 🪟  | 🧩  | 🐧  | 🍎  | Description                |
| ------------------------------------------------------ | --- | --- | --- | --- | -------------------------- |
| [GitHub CLI](https://github.com/cli/cli)               | ✅  | ✅  | ❌  | ✅  | GitHub's official CLI      |
| [lazygit](https://github.com/jesseduffield/lazygit)    | ✅  | ✅  | ❌  | ✅  | Terminal UI for Git        |
| [gopass](https://github.com/gopasspw/gopass)           | ✅  | ✅  | ❌  | ✅  | Password manager for teams |
| [Doppler CLI](https://github.com/DopplerHQ/cli)        | ✅  | ✅  | ❌  | ✅  | CLI for Doppler secrets    |
| [OpenSSH](https://github.com/openssh/openssh-portable) | ❌  | ✅  | ❌  | ❌  | Portable SSH client tools  |
| [keychain](https://github.com/funtoo/keychain)         | ❌  | ✅  | ❌  | ❌  | Manages SSH and GPG agents |

</details>

<details>
<summary><strong>Document Authoring and LaTeX</strong></summary>

| Name                                       | 🪟  | 🧩  | 🐧  | 🍎  | Description                  |
| ------------------------------------------ | --- | --- | --- | --- | ---------------------------- |
| [MiKTeX](https://github.com/MiKTeX/miktex) | ✅  | ❌  | ❌  | ❌  | TeX distribution for Windows |
| [TeX Live](https://tug.org/texlive/)       | ❌  | ✅  | ❌  | ❌  | TeX distribution             |
| [MacTeX](https://www.tug.org/mactex/)      | ❌  | ❌  | ❌  | ✅  | TeX Live for macOS           |

</details>

<details>
<summary><strong>Utilities</strong></summary>

| Name                                                | 🪟  | 🧩  | 🐧  | 🍎  | Description                   |
| --------------------------------------------------- | --- | --- | --- | --- | ----------------------------- |
| [curl](https://github.com/curl/curl)                | ❌  | ✅  | ❌  | ❌  | Transfers data with URLs      |
| [croc](https://github.com/schollz/croc)             | ✅  | ✅  | ❌  | ✅  | Secure file transfer          |
| [grex](https://github.com/pemistahl/grex)           | ✅  | ✅  | ❌  | ✅  | Generates regex from examples |
| [jq](https://github.com/jqlang/jq)                  | ✅  | ✅  | ❌  | ✅  | Command-line JSON processor   |
| [ripgrep](https://github.com/BurntSushi/ripgrep)    | ✅  | ✅  | ❌  | ✅  | Recursive regex search        |
| [unzip](https://infozip.sourceforge.net/UnZip.html) | ❌  | ✅  | ❌  | ❌  | Extracts ZIP archives         |

</details>

## Setup

<details>
<summary><strong>Windows</strong></summary>

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

</details>

<details>
<summary><strong>macOS</strong></summary>

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

</details>

<details>
<summary><strong>WSL Ubuntu</strong></summary>

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

</details>
