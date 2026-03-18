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
Usage: bash ./scripts/bootstrap-macos.sh [--chezmoi-repo <source>] [--from-chezmoi-hook]

Bootstraps the macOS environment for this dotfiles repo.
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
manifest_path="$repo_root/manifests/macos.packages.json"
vscode_manifest_path="$repo_root/manifests/vscode.extensions.json"
chezmoi_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi"
chezmoi_config_path="$chezmoi_config_dir/chezmoi.toml"
macos_bootstrap_marker_path="$chezmoi_config_dir/macos-bootstrap-complete"
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

test_macos_bootstrap_complete() {
  [[ -f "$macos_bootstrap_marker_path" ]]
}

set_macos_bootstrap_complete() {
  mkdir -p "$chezmoi_config_dir"
  : >"$macos_bootstrap_marker_path"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

ensure_homebrew_on_path() {
  local brew_bin

  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_bin="/usr/local/bin/brew"
  else
    printf 'Homebrew is required but was not found on PATH.\n' >&2
    printf 'Install it from https://brew.sh, then rerun this bootstrap.\n' >&2
    exit 1
  fi

  eval "$("$brew_bin" shellenv)"
  hash -r
}

load_json_string_array() {
  local json_path json_key
  json_path="$1"
  json_key="$2"

  if [[ ! -f "$json_path" ]]; then
    printf 'Manifest not found: %s\n' "$json_path" >&2
    exit 1
  fi

  awk -v key="\"${json_key}\"" '
    $0 ~ key"[[:space:]]*:[[:space:]]*\\[" { in_array = 1; next }
    in_array {
      if ($0 ~ /^[[:space:]]*]/) {
        exit
      }

      line = $0
      sub(/^[[:space:]]*"/, "", line)
      sub(/",[[:space:]]*$/, "", line)
      sub(/"[[:space:]]*$/, "", line)

      if (line != "") {
        print line
      }
    }
  ' "$json_path"
}

array_contains() {
  local needle item
  needle="$1"
  shift

  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
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
  local key data_block line value
  key="$1"

  if [[ ! -f "$chezmoi_config_path" ]]; then
    return
  fi

  data_block="$(awk '
    /^\[data\]/ { in_data = 1; next }
    /^\[/ && in_data { exit }
    in_data { print }
  ' "$chezmoi_config_path")"

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$ ]]; then
      value="${BASH_REMATCH[1]}"
      value="${value%\"}"
      value="${value#\"}"
      printf '%s\n' "${value//\\\"/\"}"
      return
    fi
  done <<<"$data_block"
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

  if awk \
    -v git_signing_key_value="\"${ssh_dir}/${key_name}.pub\"" \
    -v git_allowed_signers_file_value="\"${ssh_dir}/allowed_signers\"" \
    -v ssh_github_key_name_value="\"${key_name}\"" \
    -v ssh_github_key_comment_value="\"${key_comment}\"" '
    BEGIN {
      desired_count = 7
      desired_keys[1] = "github_use_ssh_instead_of_https"
      desired_keys[2] = "git_signing_key"
      desired_keys[3] = "git_gpg_format"
      desired_keys[4] = "git_commit_gpgsign"
      desired_keys[5] = "git_allowed_signers_file"
      desired_keys[6] = "ssh_github_key_name"
      desired_keys[7] = "ssh_github_key_comment"

      desired_values["github_use_ssh_instead_of_https"] = "false"
      desired_values["git_signing_key"] = git_signing_key_value
      desired_values["git_gpg_format"] = "\"ssh\""
      desired_values["git_commit_gpgsign"] = "true"
      desired_values["git_allowed_signers_file"] = git_allowed_signers_file_value
      desired_values["ssh_github_key_name"] = ssh_github_key_name_value
      desired_values["ssh_github_key_comment"] = ssh_github_key_comment_value
    }

    function flush_missing(    idx, key) {
      for (idx = 1; idx <= desired_count; idx++) {
        key = desired_keys[idx]
        if (!(key in seen)) {
          print "    " key " = " desired_values[key]
          changed = 1
        }
      }
    }

    /^\[data\]/ {
      in_data = 1
      data_seen = 1
      print
      next
    }

    /^\[/ && in_data {
      flush_missing()
      in_data = 0
      print
      next
    }

    {
      if (in_data) {
        print
        if (match($0, /^[[:space:]]*([A-Za-z0-9_]+)[[:space:]]*=/)) {
          key = substr($0, RSTART, RLENGTH)
          sub(/^[[:space:]]*/, "", key)
          sub(/[[:space:]]*=.*/, "", key)
          seen[key] = 1
        }
        next
      }

      print
    }

    END {
      if (in_data) {
        flush_missing()
      }

      if (!data_seen) {
        print "[data]"
        flush_missing()
      }

      if (changed) {
        exit 10
      }
    }
  ' "$chezmoi_config_path" >"${chezmoi_config_path}.tmp"
  then
    update_status=0
  else
    update_status=$?
  fi

  case "$update_status" in
    0)
      rm -f "${chezmoi_config_path}.tmp"
      rm -f "$backup_path"
      write_ok "Local chezmoi SSH config data already present"
      ;;
    10)
      mv "${chezmoi_config_path}.tmp" "$chezmoi_config_path"
      write_ok "Backfilled local chezmoi SSH config data (backup: $backup_path)"
      ;;
    *)
      rm -f "${chezmoi_config_path}.tmp"
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
    awk -v source_dir="$escaped_source" '
      BEGIN { replaced = 0 }
      /^sourceDir[[:space:]]*=/ {
        print "sourceDir = \"" source_dir "\""
        replaced = 1
        next
      }
      { print }
      END {
        if (!replaced) {
          print "sourceDir = \"" source_dir "\""
        }
      }
    ' "$chezmoi_config_path" >"${chezmoi_config_path}.tmp"
    mv "${chezmoi_config_path}.tmp" "$chezmoi_config_path"
    write_ok "Updated local chezmoi sourceDir to $source_dir (backup: $backup_path)"
    return
  fi

  backup_path="${chezmoi_config_path}.$(date +%Y%m%d-%H%M%S).bak"
  cp "$chezmoi_config_path" "$backup_path"
  awk -v source_dir="$escaped_source" '
    BEGIN { inserted = 0 }
    /^\[/ && !inserted {
      print "sourceDir = \"" source_dir "\""
      print ""
      inserted = 1
    }
    { print }
    END {
      if (!inserted) {
        print "sourceDir = \"" source_dir "\""
      }
    }
  ' "$chezmoi_config_path" >"${chezmoi_config_path}.tmp"
  mv "${chezmoi_config_path}.tmp" "$chezmoi_config_path"
  write_ok "Set local chezmoi sourceDir to $source_dir (backup: $backup_path)"
}

get_chezmoi_source_path() {
  if [[ "$from_chezmoi_hook" -eq 1 ]]; then
    printf '%s\n' "$repo_root"
    return
  fi

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

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    write_ok "git is available"
    return
  fi

  printf 'git is required but was not found on PATH.\n' >&2
  printf 'Install it first with: brew install git\n' >&2
  exit 1
}

ensure_chezmoi() {
  if command -v chezmoi >/dev/null 2>&1; then
    write_ok "chezmoi is available"
    return
  fi

  printf 'chezmoi is required but was not found on PATH.\n' >&2
  printf 'Install it first with: brew install chezmoi\n' >&2
  exit 1
}

install_homebrew_packages() {
  local package
  local -a formulae casks

  mapfile -t formulae < <(load_json_string_array "$manifest_path" "formulae")
  mapfile -t casks < <(load_json_string_array "$manifest_path" "casks")

  if [[ "${#formulae[@]}" -eq 0 && "${#casks[@]}" -eq 0 ]]; then
    printf 'No Homebrew packages were defined in %s\n' "$manifest_path" >&2
    exit 1
  fi

  if [[ "${#formulae[@]}" -gt 0 ]]; then
    write_step "Installing Homebrew formulae"
    for package in "${formulae[@]}"; do
      if brew list --versions "$package" >/dev/null 2>&1; then
        write_ok "$package already installed"
        continue
      fi

      brew install "$package"
      write_ok "$package installed"
    done
  fi

  if [[ "${#casks[@]}" -gt 0 ]]; then
    write_step "Installing Homebrew casks"
    for package in "${casks[@]}"; do
      if brew list --cask --versions "$package" >/dev/null 2>&1; then
        write_ok "$package already installed"
        continue
      fi

      brew install --cask "$package"
      write_ok "$package installed"
    done
  fi

  hash -r
}

ensure_ssh_agent() {
  local ssh_add_status

  if ssh-add -l >/dev/null 2>&1; then
    return
  fi

  ssh_add_status=$?
  if [[ "$ssh_add_status" -eq 1 ]]; then
    return
  fi

  eval "$(ssh-agent -s)" >/dev/null
  write_ok "Started ssh-agent"
}

ensure_macos_ssh_setup() {
  local key_name key_comment private_key_path public_key_path public_key_contents

  write_step "Configuring macOS SSH"
  require_command ssh-keygen
  require_command ssh-add

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

  ensure_ssh_agent

  if ssh-add --apple-use-keychain "$private_key_path" >/dev/null 2>&1; then
    write_ok "Loaded SSH key into ssh-agent and macOS Keychain"
  elif ssh-add "$private_key_path" >/dev/null 2>&1; then
    write_warn "ssh-add does not support --apple-use-keychain on this system; loaded key into ssh-agent only"
    write_ok "Loaded SSH key into ssh-agent"
  else
    printf "ssh-add failed while loading '%s'.\n" "$private_key_path" >&2
    exit 1
  fi

  update_local_chezmoi_ssh_config "$key_name" "$key_comment"

  public_key_contents="$(cat "$public_key_path")"
  if [[ -z "$public_key_contents" ]]; then
    printf "SSH public key at '%s' is empty or unreadable.\n" "$public_key_path" >&2
    exit 1
  fi

  printf '\nAdd this public key to GitHub for auth and SSH signing:\n'
  printf '  %s\n' "$public_key_contents"
}

install_vscode_extensions() {
  local ext legacy_ltex_extension installed_count skipped_count
  local -a extensions installed failed

  if ! command -v code >/dev/null 2>&1; then
    write_warn "VS Code 'code' CLI not on PATH yet - restart your shell and rerun:"
    write_warn "  ./scripts/bootstrap-macos.sh"
    return
  fi

  mapfile -t extensions < <(load_json_string_array "$vscode_manifest_path" "extensions")
  mapfile -t installed < <(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')
  legacy_ltex_extension="valentjn.vscode-ltex"

  if array_contains "$legacy_ltex_extension" "${installed[@]}"; then
    write_step "Migrating legacy LTeX extension"
    if code --uninstall-extension "$legacy_ltex_extension" --force >/dev/null 2>&1; then
      write_ok "Removed legacy extension: $legacy_ltex_extension"
      mapfile -t installed < <(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')
    else
      write_warn "Failed to uninstall legacy extension: $legacy_ltex_extension"
    fi
  fi

  write_step "Installing VS Code Extensions (${#extensions[@]} total)"

  installed_count=0
  skipped_count=0
  failed=()

  for ext in "${extensions[@]}"; do
    if array_contains "${ext,,}" "${installed[@]}"; then
      printf '  - %s (already installed)\n' "$ext"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    if code --install-extension "$ext" --force >/dev/null 2>&1; then
      write_ok "$ext"
      installed_count=$((installed_count + 1))
      installed+=("${ext,,}")
    else
      write_warn "Failed to install: $ext"
      failed+=("$ext")
    fi
  done

  printf '\n  ---------------------------------\n'
  write_ok "Installed : $installed_count"
  printf '  - Skipped  : %s (already present)\n' "$skipped_count"

  if [[ "${#failed[@]}" -gt 0 ]]; then
    printf '\n' >&2
    write_warn "Failed to install ${#failed[@]} extension(s):"
    printf '  - %s\n' "${failed[@]}" >&2
  fi
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
  current_shell="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"

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
  write_step "Checking macOS bootstrap hook"
  if test_macos_bootstrap_complete; then
    write_ok "macOS bootstrap already completed for this machine"
    exit 0
  fi

  write_ok "Running bootstrap from chezmoi hook"
fi

write_step "Checking platform"
if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'This bootstrap only supports macOS.\n' >&2
  exit 1
fi
write_ok "macOS detected"

write_step "Checking Homebrew"
ensure_homebrew_on_path
write_ok "Homebrew is available"

install_homebrew_packages

write_step "Checking prerequisites"
ensure_git
ensure_chezmoi

write_step "Configuring Chezmoi"
ensure_local_chezmoi_config
ensure_macos_ssh_setup

if [[ "$from_chezmoi_hook" -eq 1 ]]; then
  write_ok "Chezmoi source apply is managed by the calling chezmoi command"
else
  apply_chezmoi "$(resolve_desired_chezmoi_source)"
fi

install_vscode_extensions

write_step "Syncing mise tools"
sync_mise

ensure_login_shell

if [[ "$from_chezmoi_hook" -eq 1 ]]; then
  set_macos_bootstrap_complete
fi

cat <<'EOF'

Next steps:
  1. Open Ghostty and start a new macOS shell session.
  2. Verify the shell loads with: zsh -lic 'command -v brew code zsh starship mise zoxide fzf yazi'
  3. Verify SSH agent state with: ssh-add -l
  4. Verify chezmoi source state with: chezmoi source-path
  5. Authenticate any optional tools you use:
       gh auth login
       doppler login
       gopass setup
EOF
