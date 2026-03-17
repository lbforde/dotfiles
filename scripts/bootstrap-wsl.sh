#!/usr/bin/env bash

set -euo pipefail

chezmoi_repo=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --chezmoi-repo)
      if [[ $# -lt 2 ]]; then
        printf 'Missing value for --chezmoi-repo\n' >&2
        exit 1
      fi
      chezmoi_repo="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash ./scripts/bootstrap-wsl.sh [--chezmoi-repo <source>]

Bootstraps the Ubuntu/WSL environment for this dotfiles repo.
EOF
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="$repo_root/manifests/wsl.packages.json"
chezmoi_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"
chezmoi_config_path="$chezmoi_config_dir/chezmoi.toml"
mise_bin_dir="${HOME}/.local/bin"

write_step() {
  printf '\n=== %s ===\n' "$1"
}

write_ok() {
  printf '  [ok] %s\n' "$1"
}

write_warn() {
  printf '  [warn] %s\n' "$1" >&2
}

write_info() {
  printf '  [info] %s\n' "$1"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

ensure_local_bin_on_path() {
  case ":$PATH:" in
    *":$mise_bin_dir:"*) ;;
    *) export PATH="$mise_bin_dir:$PATH" ;;
  esac
}

load_manifest_packages() {
  if [[ ! -f "$manifest_path" ]]; then
    printf 'WSL package manifest not found: %s\n' "$manifest_path" >&2
    exit 1
  fi

  require_command python3

  python3 - <<'PY' "$manifest_path"
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
for package in manifest.get("aptPackages", []):
    print(package)
PY
}

get_editor_command() {
  if command -v code >/dev/null 2>&1; then
    printf 'code'
    return
  fi
  if command -v nano >/dev/null 2>&1; then
    printf 'nano'
    return
  fi
  printf 'vi'
}

create_local_chezmoi_config() {
  local default_name default_email editor_command name_input email_input
  default_name="$(git config --global user.name 2>/dev/null || true)"
  default_email="$(git config --global user.email 2>/dev/null || true)"
  editor_command="$(get_editor_command)"

  if [[ -z "$default_name" ]]; then
    read -rp "  Git user.name: " default_name
  else
    read -rp "  Git user.name [$default_name]: " name_input
    default_name="${name_input:-$default_name}"
  fi

  if [[ -z "$default_email" ]]; then
    read -rp "  Git user.email: " default_email
  else
    read -rp "  Git user.email [$default_email]: " email_input
    default_email="${email_input:-$default_email}"
  fi

  if [[ -z "$default_name" || -z "$default_email" ]]; then
    printf 'Git user.name and user.email are required for local chezmoi config.\n' >&2
    exit 1
  fi

  mkdir -p "$chezmoi_config_dir"
  cat >"$chezmoi_config_path" <<EOF
# Local Chezmoi runtime config (machine-specific)
[data]
    name  = "$(printf '%s' "$default_name" | sed 's/"/\\"/g')"
    email = "$(printf '%s' "$default_email" | sed 's/"/\\"/g')"

[edit]
    command = "$editor_command"
EOF

  if [[ "$editor_command" == "code" ]]; then
    cat >>"$chezmoi_config_path" <<'EOF'
    args    = ["--wait"]

[merge]
    command = "code"
    args    = ["--wait", "--merge", "{{ .Destination }}", "{{ .Source }}", "{{ .Base }}", "{{ .Destination }}"]

[diff]
    command = "code"
    args    = ["--wait", "--diff", "{{ .Destination }}", "{{ .Target }}"]
EOF
  fi

  cat >>"$chezmoi_config_path" <<'EOF'

[git]
    autoCommit = false
    autoPush   = false

[template]
    options = ["missingkey=default"]
EOF

  write_ok "Created local chezmoi config at $chezmoi_config_path"
}

ensure_local_chezmoi_config() {
  if [[ -f "$chezmoi_config_path" ]]; then
    write_ok "Local chezmoi config already present"
    return
  fi

  write_info "No local chezmoi config found. Enter machine-specific identity values."
  create_local_chezmoi_config
}

set_local_chezmoi_source_dir() {
  local source_dir normalized_source escaped_source backup_path
  source_dir="$1"
  normalized_source="${source_dir//\\/\/}"
  escaped_source="${normalized_source//\"/\\\"}"

  if [[ ! -f "$chezmoi_config_path" ]]; then
    printf 'Local chezmoi config not found at %s\n' "$chezmoi_config_path" >&2
    exit 1
  fi

  if grep -q '^sourceDir = ' "$chezmoi_config_path"; then
    if grep -Fxq "sourceDir = \"$escaped_source\"" "$chezmoi_config_path"; then
      write_ok "Local chezmoi sourceDir already set to $source_dir"
      return
    fi
    backup_path="${chezmoi_config_path}.$(date +%Y%m%d-%H%M%S).bak"
    cp "$chezmoi_config_path" "$backup_path"
    python3 - <<'PY' "$chezmoi_config_path" "$escaped_source"
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source_dir = sys.argv[2]
content = path.read_text(encoding="utf-8")
updated = re.sub(r'(?m)^sourceDir\s*=.*$', f'sourceDir = "{source_dir}"', content)
path.write_text(updated, encoding="utf-8")
PY
    write_ok "Updated local chezmoi sourceDir to $source_dir (backup: $backup_path)"
    return
  fi

  backup_path="${chezmoi_config_path}.$(date +%Y%m%d-%H%M%S).bak"
  cp "$chezmoi_config_path" "$backup_path"
  python3 - <<'PY' "$chezmoi_config_path" "$escaped_source"
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
source_dir = sys.argv[2]
content = path.read_text(encoding="utf-8")
table_match = re.search(r'(?m)^\[', content)
line = f'sourceDir = "{source_dir}"\n\n'
if table_match:
    updated = content[:table_match.start()] + line + content[table_match.start():]
else:
    updated = line + content
path.write_text(updated, encoding="utf-8")
PY
  write_ok "Set local chezmoi sourceDir to $source_dir (backup: $backup_path)"
}

get_chezmoi_source_path() {
  chezmoi source-path 2>/dev/null || true
}

get_chezmoi_remote_origin() {
  chezmoi git -- remote get-url origin 2>/dev/null || true
}

has_chezmoi_managed_files() {
  local managed
  managed="$(chezmoi managed 2>/dev/null || true)"
  [[ -n "$managed" ]]
}

resolve_desired_chezmoi_source() {
  if [[ -n "$chezmoi_repo" ]]; then
    printf '%s\n' "$chezmoi_repo"
    return
  fi

  printf '%s\n' "$repo_root"
}

ensure_mise() {
  ensure_local_bin_on_path
  if command -v mise >/dev/null 2>&1; then
    write_ok "mise is available"
    return
  fi

  write_step "Installing mise"
  curl https://mise.run | sh
  ensure_local_bin_on_path

  if ! command -v mise >/dev/null 2>&1; then
    printf 'mise is still not available after installation.\n' >&2
    exit 1
  fi

  write_ok "mise installed"
}

ensure_chezmoi() {
  if command -v chezmoi >/dev/null 2>&1; then
    write_ok "chezmoi is available"
    return
  fi

  printf 'chezmoi is required but was not found on PATH.\n' >&2
  printf 'Install chezmoi first, then rerun this bootstrap.\n' >&2
  exit 1
}

apply_chezmoi() {
  local desired_source current_source current_origin
  desired_source="$1"

  if [[ "$desired_source" =~ ^(https?|ssh)://|^git@ ]]; then
    current_source="$(get_chezmoi_source_path)"
    if [[ -z "$current_source" ]] || ! has_chezmoi_managed_files; then
      chezmoi init --apply --exclude=scripts "$desired_source"
      write_ok "Chezmoi initialised and applied from $desired_source"
      return
    fi

    current_origin="$(get_chezmoi_remote_origin)"
    if [[ -n "$current_origin" && "$current_origin" != "$desired_source" ]]; then
      write_warn "Chezmoi source already uses a different origin: $current_origin"
      write_warn "Keeping the existing source and applying current state."
    fi

    chezmoi apply --exclude=scripts
    write_ok "Chezmoi apply complete"
    return
  fi

  desired_source="$(cd -- "$desired_source" && pwd)"
  set_local_chezmoi_source_dir "$desired_source"
  chezmoi apply --exclude=scripts
  write_ok "Chezmoi apply complete"
}

sync_mise() {
  local sync_script
  sync_script="$repo_root/scripts/sync-mise.sh"
  if [[ ! -f "$sync_script" ]]; then
    printf 'mise sync script not found at %s\n' "$sync_script" >&2
    exit 1
  fi

  bash "$sync_script"
}

ensure_login_shell() {
  local zsh_path current_shell
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"

  if [[ "$current_shell" == "$zsh_path" ]]; then
    write_ok "Login shell already set to zsh"
    return
  fi

  write_step "Configuring login shell"
  if chsh -s "$zsh_path"; then
    write_ok "Login shell changed to zsh"
  else
    write_warn "Could not change login shell automatically. Run: chsh -s $zsh_path"
  fi
}

write_step "Checking platform"
if ! command -v apt-get >/dev/null 2>&1; then
  printf 'This bootstrap currently supports Ubuntu/Debian environments with apt.\n' >&2
  exit 1
fi
write_ok "apt-get is available"

write_step "Installing apt packages"
mapfile -t apt_packages < <(load_manifest_packages)
if [[ "${#apt_packages[@]}" -eq 0 ]]; then
  printf 'No apt packages were defined in %s\n' "$manifest_path" >&2
  exit 1
fi
sudo apt-get update -y
sudo apt-get install -y "${apt_packages[@]}"
write_ok "Bootstrap packages installed"

ensure_mise
ensure_chezmoi

write_step "Configuring Chezmoi"
ensure_local_chezmoi_config
apply_chezmoi "$(resolve_desired_chezmoi_source)"

write_step "Syncing mise tools"
sync_mise

ensure_login_shell

cat <<'EOF'

Next steps:
  1. Open a new Ubuntu shell.
  2. Verify the shell loads with: zsh -lic 'command -v zsh starship mise zoxide fzf opencode'
  3. Verify chezmoi source state with: chezmoi source-path
  4. Authenticate any optional tools you use:
       gh auth login
       doppler login
       gopass setup
EOF
