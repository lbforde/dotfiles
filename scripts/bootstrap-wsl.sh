#!/usr/bin/env bash

set -euo pipefail

chezmoi_repo=""
from_chezmoi_hook=0

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
    --from-chezmoi-hook)
      from_chezmoi_hook=1
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage: bash ./scripts/bootstrap-wsl.sh [--chezmoi-repo <source>] [--from-chezmoi-hook]

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
wsl_bootstrap_marker_path="$chezmoi_config_dir/wsl-bootstrap-complete"
local_bin_dir="${HOME}/.local/bin"
home_bin_dir="${HOME}/bin"
profile_path="${HOME}/.profile"
ssh_dir="${HOME}/.ssh"
default_github_key_name="github_personal_key"

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

test_wsl_bootstrap_complete() {
  [[ -f "$wsl_bootstrap_marker_path" ]]
}

set_wsl_bootstrap_complete() {
  mkdir -p "$chezmoi_config_dir"
  : >"$wsl_bootstrap_marker_path"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

ensure_user_bin_dirs_on_path() {
  local bin_dir

  for bin_dir in "$local_bin_dir" "$home_bin_dir"; do
    if [[ ! -d "$bin_dir" ]]; then
      continue
    fi

    case ":$PATH:" in
      *":$bin_dir:"*) ;;
      *) export PATH="$bin_dir:$PATH" ;;
    esac
  done
}

ensure_user_bin_dirs_in_profile() {
  local marker_start marker_end
  marker_start="# Added by dotfiles bootstrap"
  marker_end="# End dotfiles bootstrap"

  if [[ -f "$profile_path" ]] && grep -Fq "$marker_start" "$profile_path"; then
    write_ok "User bin PATH block already present in $profile_path"
    return
  fi

  cat >>"$profile_path" <<'EOF'

# Added by dotfiles bootstrap
export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
# End dotfiles bootstrap
EOF

  write_ok "Ensured user bin directories are added from $profile_path"
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

read_lines_into_array() {
  local array_name line quoted_line
  array_name="$1"

  eval "$array_name=()"

  while IFS= read -r line; do
    printf -v quoted_line '%q' "$line"
    eval "$array_name+=( $quoted_line )"
  done
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
  local default_name default_email editor_command name_input email_input ssh_public_key_path allowed_signers_path
  default_name="$(git config --global user.name 2>/dev/null || true)"
  default_email="$(git config --global user.email 2>/dev/null || true)"
  editor_command="$(get_editor_command)"
  ssh_public_key_path="${ssh_dir}/${default_github_key_name}.pub"
  allowed_signers_path="${ssh_dir}/allowed_signers"

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
    github_use_ssh_instead_of_https = false
    git_signing_key          = "$(printf '%s' "$ssh_public_key_path" | sed 's/"/\\"/g')"
    git_gpg_format           = "ssh"
    git_commit_gpgsign       = true
    git_allowed_signers_file = "$(printf '%s' "$allowed_signers_path" | sed 's/"/\\"/g')"
    ssh_github_key_name      = "${default_github_key_name}"
    ssh_github_key_comment   = "$(printf '%s' "$default_email" | sed 's/"/\\"/g')"

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

get_local_chezmoi_data_value() {
  local key
  key="$1"

  if [[ ! -f "$chezmoi_config_path" ]]; then
    return
  fi

  python3 - <<'PY' "$chezmoi_config_path" "$key"
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
content = path.read_text(encoding="utf-8")
section_match = re.search(r'(?ms)^\[data\]\s*(.*?)(?=^\[|\Z)', content)
if not section_match:
    sys.exit(0)

value_match = re.search(r'(?m)^\s*' + re.escape(key) + r'\s*=\s*(.+?)\s*$', section_match.group(1))
if not value_match:
    sys.exit(0)

value = value_match.group(1).strip()
if len(value) >= 2 and value[0] == value[-1] == '"':
    value = value[1:-1].replace(r'\"', '"').replace(r'\\', '\\')

print(value)
PY
}

update_local_chezmoi_ssh_config() {
  local key_name key_comment backup_path update_status
  key_name="$1"
  key_comment="$2"

  if [[ ! -f "$chezmoi_config_path" ]]; then
    return
  fi

  backup_path="${chezmoi_config_path}.$(date +%Y%m%d-%H%M%S).bak"
  cp "$chezmoi_config_path" "$backup_path"

  if python3 - <<'PY' "$chezmoi_config_path" "$ssh_dir" "$key_name" "$key_comment"
from collections import OrderedDict
from pathlib import Path
import re
import sys

config_path = Path(sys.argv[1])
ssh_dir = sys.argv[2]
key_name = sys.argv[3]
key_comment = sys.argv[4]

def toml_string(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'

content = config_path.read_text(encoding="utf-8")
section_pattern = re.compile(r'(?ms)^\[data\]\s*(?P<body>.*?)(?=^\[|\Z)')
section_match = section_pattern.search(content)

lines = []
if section_match:
    body = section_match.group('body').rstrip('\r\n')
    if body.strip():
        lines = body.splitlines()

desired = OrderedDict([
    ("github_use_ssh_instead_of_https", "false"),
    ("git_signing_key", toml_string(f"{ssh_dir}/{key_name}.pub")),
    ("git_gpg_format", toml_string("ssh")),
    ("git_commit_gpgsign", "true"),
    ("git_allowed_signers_file", toml_string(f"{ssh_dir}/allowed_signers")),
    ("ssh_github_key_name", toml_string(key_name)),
    ("ssh_github_key_comment", toml_string(key_comment)),
])

changed = False
for key, value in desired.items():
    pattern = re.compile(r'^\s*' + re.escape(key) + r'\s*=')
    if any(pattern.match(line) for line in lines):
        continue
    lines.append(f"    {key} = {value}")
    changed = True

if not changed:
    sys.exit(0)

replacement = "[data]\n" + ("\n".join(lines) + "\n" if lines else "")
if section_match:
    updated = content[:section_match.start()] + replacement + content[section_match.end():]
else:
    trimmed = content.rstrip("\r\n")
    updated = replacement if not trimmed else replacement + "\n" + trimmed + "\n"

config_path.write_text(updated, encoding="utf-8")
sys.exit(10)
PY
  then
    update_status=0
  else
    update_status=$?
  fi

  case "$update_status" in
    0)
      rm -f "$backup_path"
      write_ok "Local chezmoi SSH config data already present"
      ;;
    10)
      write_ok "Backfilled local chezmoi SSH config data (backup: $backup_path)"
      ;;
    *)
      printf 'Failed to backfill local chezmoi SSH config data.\n' >&2
      exit 1
      ;;
  esac
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
  ensure_user_bin_dirs_on_path
  if command -v mise >/dev/null 2>&1; then
    write_ok "mise is available"
    return
  fi

  write_step "Installing mise"
  curl https://mise.run | sh
  ensure_user_bin_dirs_on_path

  if ! command -v mise >/dev/null 2>&1; then
    printf 'mise is still not available after installation.\n' >&2
    exit 1
  fi

  write_ok "mise installed"
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    write_ok "git is available"
    return
  fi

  printf 'git is required but was not found on PATH.\n' >&2
  printf 'Install git first, then rerun this bootstrap.\n' >&2
  exit 1
}

ensure_chezmoi() {
  ensure_user_bin_dirs_on_path
  if command -v chezmoi >/dev/null 2>&1; then
    write_ok "chezmoi is available"
    return
  fi

  printf 'chezmoi is required but was not found on PATH.\n' >&2
  printf 'Install it with: sh -c "$(curl -fsLS get.chezmoi.io)"\n' >&2
  printf 'Then run: export PATH="$HOME/.local/bin:$HOME/bin:$PATH"\n' >&2
  printf 'Then rerun this bootstrap.\n' >&2
  exit 1
}

ensure_wsl_ssh_setup() {
  local key_name key_comment private_key_path public_key_path public_key_contents

  write_step "Configuring WSL SSH"
  require_command ssh-keygen

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  key_name="$(get_local_chezmoi_data_value "ssh_github_key_name")"
  if [[ -z "$key_name" ]]; then
    key_name="$default_github_key_name"
  fi

  key_comment="$(get_local_chezmoi_data_value "ssh_github_key_comment")"
  if [[ -z "$key_comment" ]]; then
    key_comment="$(get_local_chezmoi_data_value "email")"
  fi
  if [[ -z "$key_comment" ]]; then
    key_comment="$(git config --global --get user.email 2>/dev/null || true)"
  fi
  if [[ -z "$key_comment" ]]; then
    printf 'Could not determine the SSH key comment. Set your git email first, then rerun bootstrap.\n' >&2
    exit 1
  fi

  private_key_path="${ssh_dir}/${key_name}"
  public_key_path="${private_key_path}.pub"

  if [[ ! -f "$private_key_path" ]]; then
    write_info "Generating SSH key '${key_name}' for GitHub auth and Git signing..."
    ssh-keygen -t ed25519 -f "$private_key_path" -C "$key_comment"
    write_ok "Created SSH key: $private_key_path"
  else
    write_ok "SSH private key already present: $private_key_path"
  fi

  chmod 600 "$private_key_path"

  if [[ ! -f "$public_key_path" ]]; then
    printf "SSH private key exists at '%s' but the matching public key '%s' is missing.\n" "$private_key_path" "$public_key_path" >&2
    printf 'Repair the keypair or remove the private key and rerun bootstrap.\n' >&2
    exit 1
  fi

  chmod 644 "$public_key_path"
  write_ok "SSH public key available: $public_key_path"

  update_local_chezmoi_ssh_config "$key_name" "$key_comment"

  public_key_contents="$(cat "$public_key_path")"
  if [[ -z "$public_key_contents" ]]; then
    printf "SSH public key at '%s' is empty or unreadable.\n" "$public_key_path" >&2
    exit 1
  fi

  printf '\nAdd this public key to GitHub for auth and SSH signing:\n'
  printf '  %s\n' "$public_key_contents"
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

if [[ "$from_chezmoi_hook" -eq 1 && "${DOTFILES_BOOTSTRAP_ACTIVE:-}" == "1" ]]; then
  exit 0
fi

export DOTFILES_BOOTSTRAP_ACTIVE=1

if [[ "$from_chezmoi_hook" -eq 1 ]]; then
  write_step "Checking WSL bootstrap hook"
  if test_wsl_bootstrap_complete; then
    write_ok "WSL bootstrap already completed for this machine"
    exit 0
  fi

  write_ok "Running bootstrap from chezmoi hook"
fi

write_step "Checking platform"
if ! command -v apt-get >/dev/null 2>&1; then
  printf 'This bootstrap currently supports Ubuntu/Debian environments with apt.\n' >&2
  exit 1
fi
write_ok "apt-get is available"

write_step "Checking prerequisites"
ensure_git
ensure_chezmoi
ensure_user_bin_dirs_in_profile

write_step "Installing apt packages"
read_lines_into_array apt_packages < <(load_manifest_packages)
if [[ "${#apt_packages[@]}" -eq 0 ]]; then
  printf 'No apt packages were defined in %s\n' "$manifest_path" >&2
  exit 1
fi
sudo apt-get update -y
sudo apt-get install -y "${apt_packages[@]}"
write_ok "Bootstrap packages installed"

ensure_mise

write_step "Configuring Chezmoi"
ensure_local_chezmoi_config
ensure_wsl_ssh_setup
if [[ "$from_chezmoi_hook" -eq 1 ]]; then
  write_ok "Chezmoi source apply is managed by the calling chezmoi command"
else
  apply_chezmoi "$(resolve_desired_chezmoi_source)"
fi

if [[ "$from_chezmoi_hook" -eq 1 ]]; then
  write_ok "Mise sync is deferred until after chezmoi apply"
else
  write_step "Syncing mise tools"
  sync_mise
fi

ensure_login_shell

if [[ "$from_chezmoi_hook" -eq 1 ]]; then
  set_wsl_bootstrap_complete
fi

cat <<'EOF'

Next steps:
  1. Open a new Ubuntu shell.
  2. Verify the shell loads with: zsh -lic 'command -v zsh starship mise atuin zoxide fzf opencode keychain'
  3. Optionally import shell history once with: atuin import auto
  4. Verify SSH agent state with: zsh -lic 'ssh-add -l'
  5. Verify chezmoi source state with: chezmoi source-path
  6. Authenticate any optional tools you use:
       gh auth login
       doppler login
       gopass setup
EOF
