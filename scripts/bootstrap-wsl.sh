#!/usr/bin/env bash
# ============================================================================
# WSL2 Ubuntu Developer Environment Bootstrap Script
# ============================================================================
# Installs and configures a WSL2 Ubuntu dev environment from manifest JSON files.
#
# Supported targets:
#   - Ubuntu / Debian-family under WSL2 (apt)
#
# Usage:
#   ./scripts/bootstrap-wsl.sh
#   ./scripts/bootstrap-wsl.sh --dry-run
#   ./scripts/bootstrap-wsl.sh --skip-runtimes
#   ./scripts/bootstrap-wsl.sh --manifest manifests/linux.ubuntu.packages.json

set -euo pipefail

# --- CLI flags ---------------------------------------------------------------

DRY_RUN=0
SKIP_PACKAGES=0
SKIP_RUNTIMES=0
MANIFEST_OVERRIDE=""
SHELL_CHANGE_PENDING=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-packages)
      SKIP_PACKAGES=1
      shift
      ;;
    --skip-runtimes)
      SKIP_RUNTIMES=1
      shift
      ;;
    --manifest)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --manifest requires a path argument."
        exit 1
      fi
      MANIFEST_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/bootstrap-wsl.sh [options]

Options:
  --manifest <path>   Use a specific manifest file.
  --skip-packages     Skip package manager installs.
  --skip-runtimes     Skip mise runtime installs.
  --dry-run           Print planned actions without executing them.
  -h, --help          Show this help text.
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument '$1'. Use --help."
      exit 1
      ;;
  esac
done

# --- Paths ------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Logging helpers ---------------------------------------------------------

step() { printf "\n=== %s ===\n" "$1"; }
ok()   { printf "  [ok] %s\n" "$1"; }
warn() { printf "  [warn] %s\n" "$1"; }
err()  { printf "  [error] %s\n" "$1" >&2; }

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] %s\n" "$*"
  else
    "$@"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command not found: $1"
    exit 1
  fi
}

is_path_in_session() {
  local path_entry="$1"
  case ":${PATH}:" in
    *":${path_entry}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

refresh_session_path() {
  local -a candidate_paths=(
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    "$HOME/.npm-global/bin"
  )

  local added_count=0
  local path_entry
  for path_entry in "${candidate_paths[@]}"; do
    if [[ ! -d "$path_entry" ]]; then
      continue
    fi
    if is_path_in_session "$path_entry"; then
      continue
    fi

    PATH="$path_entry:$PATH"
    added_count=$((added_count + 1))
  done

  export PATH
  if [[ "$added_count" -gt 0 ]]; then
    ok "Session PATH refreshed (added $added_count entries)."
  else
    ok "Session PATH already up to date."
  fi
}

get_mise_runtime_command() {
  local runtime_spec="$1"
  local runtime_name
  runtime_name="${runtime_spec%%@*}"
  runtime_name="${runtime_name,,}"

  case "$runtime_name" in
    rust)
      printf "rustc\n"
      ;;
    python)
      printf "python\n"
      ;;
    *)
      printf "%s\n" "$runtime_name"
      ;;
  esac
}

test_mise_runtime_installed() {
  local runtime_spec="$1"
  if ! command -v mise >/dev/null 2>&1; then
    return 1
  fi
  mise where "$runtime_spec" >/dev/null 2>&1
}

ensure_mise_runtime_installed() {
  local runtime_spec="$1"

  if test_mise_runtime_installed "$runtime_spec"; then
    ok "$runtime_spec already installed"
    return
  fi

  run_cmd mise use --global "$runtime_spec"
  ok "$runtime_spec installed"
}

test_mise_runtime_commands() {
  local -a runtime_specs=("$@")
  local -a missing_entries=()
  local runtime_spec command_name resolved_path

  for runtime_spec in "${runtime_specs[@]}"; do
    command_name="$(get_mise_runtime_command "$runtime_spec")"
    if command -v "$command_name" >/dev/null 2>&1; then
      continue
    fi

    resolved_path="$(mise which "$command_name" 2>/dev/null || true)"
    if [[ -z "$resolved_path" ]]; then
      resolved_path="<not found by mise which>"
    fi

    missing_entries+=("runtime=$runtime_spec command=$command_name miseWhich=$resolved_path")
  done

  if [[ "${#missing_entries[@]}" -gt 0 ]]; then
    err "mise runtime validation failed. Commands missing from PATH:"
    local missing_entry
    for missing_entry in "${missing_entries[@]}"; do
      err "  $missing_entry"
    done
    err "Run 'mise reshim' and verify PATH includes mise shims, then retry."
    exit 1
  fi

  ok "Validated runtime commands on PATH"
}

# --- Manifest helpers --------------------------------------------------------

detect_json_parser() {
  require_cmd jq
  ok "Manifest parser: jq"
}

ensure_jq_installed() {
  if command -v jq >/dev/null 2>&1; then
    ok "jq already installed."
    return
  fi

  step "Installing jq (bootstrap dependency)"
  require_cmd sudo
  require_cmd apt-get
  run_cmd sudo apt-get install -y jq
}

load_array_from_command() {
  local array_name="$1"
  shift

  local tmp_file
  tmp_file="$(mktemp)"

  if ! "$@" >"$tmp_file"; then
    rm -f "$tmp_file"
    exit 1
  fi

  mapfile -t "$array_name" < "$tmp_file"
  rm -f "$tmp_file"
}

manifest_get_scalar() {
  local manifest_path="$1"
  local key="$2"
  jq -r --arg key "$key" '.[$key] // "" | tostring' "$manifest_path"
}

manifest_get_list() {
  local manifest_path="$1"
  local key="$2"
  if ! jq -e --arg key "$key" '(.[$key] // []) | type == "array"' "$manifest_path" >/dev/null; then
    err "Manifest key '$key' must be a JSON array."
    exit 1
  fi
  if ! jq -e --arg key "$key" '(.[$key] // []) | all(.[]; type == "string")' "$manifest_path" >/dev/null; then
    err "Manifest key '$key' must contain only strings."
    exit 1
  fi
  jq -r --arg key "$key" '(.[$key] // [])[]' "$manifest_path"
}

manifest_get_repo_lines() {
  local manifest_path="$1"
  local key="$2"
  jq -r --arg key "$key" '
    (.[$key] // []) as $repos
    | if ($repos | type) != "array" then
        error("Manifest key \($key) must be a JSON array.")
      else
        $repos[]
      end
    | if (type != "object") then
        error("Manifest key \($key) must contain only objects.")
      else
        .
      end
    | [.name, .keyUrl, .keyringPath, .sourceLine, .listPath] as $fields
    | if any($fields[]; . == null or (tostring | gsub("^\\s+|\\s+$"; "") == "")) then
        error("Repo entries in \($key) require name, keyUrl, keyringPath, sourceLine, and listPath.")
      else
        ($fields | map(tostring) | @tsv)
      end
  ' "$manifest_path"
}

manifest_get_script_lines() {
  local manifest_path="$1"
  local key="$2"
  jq -r --arg key "$key" '
    (.[$key] // []) as $items
    | if ($items | type) != "array" then
        error("Manifest key \($key) must be a JSON array.")
      else
        $items[]
      end
    | if (type != "object") then
        error("Manifest key \($key) must contain only objects.")
      else
        .
      end
    | [.name, .checkCommand, .installCommand] as $fields
    | if any($fields[]; . == null or (tostring | gsub("^\\s+|\\s+$"; "") == "")) then
        error("Script install entries in \($key) require name, checkCommand, and installCommand.")
      else
        ($fields | map(tostring) | @tsv)
      end
  ' "$manifest_path"
}

# --- Detect distro and manifest ---------------------------------------------

detect_manifest_path() {
  if [[ -n "$MANIFEST_OVERRIDE" ]]; then
    if [[ -f "$MANIFEST_OVERRIDE" ]]; then
      if [[ "$MANIFEST_OVERRIDE" == *"linux.arch.packages.json" ]]; then
        err "bootstrap-wsl.sh is Ubuntu-only. Use manifests/linux.ubuntu.packages.json."
        exit 1
      fi
      printf "%s\n" "$MANIFEST_OVERRIDE"
      return
    fi
    if [[ -f "$REPO_ROOT/$MANIFEST_OVERRIDE" ]]; then
      if [[ "$MANIFEST_OVERRIDE" == *"linux.arch.packages.json" ]]; then
        err "bootstrap-wsl.sh is Ubuntu-only. Use manifests/linux.ubuntu.packages.json."
        exit 1
      fi
      printf "%s\n" "$REPO_ROOT/$MANIFEST_OVERRIDE"
      return
    fi
    err "Manifest not found: $MANIFEST_OVERRIDE"
    exit 1
  fi

  if [[ ! -f /etc/os-release ]]; then
    err "/etc/os-release not found; cannot detect Linux distro."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  local distro_id="${ID:-}"
  local distro_like="${ID_LIKE:-}"

  case "$distro_id" in
    ubuntu|debian|linuxmint|pop)
      printf "%s/manifests/linux.ubuntu.packages.json\n" "$REPO_ROOT"
      return
      ;;
  esac

  # Fallback to ID_LIKE when ID is not one of our direct matches.
  if [[ "$distro_like" == *"debian"* ]]; then
    printf "%s/manifests/linux.ubuntu.packages.json\n" "$REPO_ROOT"
    return
  fi

  err "Unsupported distro for bootstrap-wsl.sh (ID='$distro_id', ID_LIKE='$distro_like')."
  err "This script targets Ubuntu/Debian on WSL2."
  exit 1
}

require_wsl_environment() {
  if [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]; then
    ok "WSL environment detected."
    return
  fi

  if grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease 2>/dev/null; then
    ok "WSL environment detected."
    return
  fi

  err "bootstrap-wsl.sh is intended for WSL2."
  err "Run this script inside Ubuntu on WSL."
  exit 1
}

# --- Package manager install routines ---------------------------------------

install_with_apt() {
  local -a packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    warn "No apt packages listed in manifest."
    return
  fi

  run_cmd sudo apt-get install -y "${packages[@]}"
}

configure_apt_repositories() {
  local -a repo_lines=("$@")
  if [[ ${#repo_lines[@]} -eq 0 ]]; then
    ok "No additional apt repositories configured."
    return
  fi

  run_cmd sudo install -m 0755 -d /etc/apt/keyrings

  local line
  for line in "${repo_lines[@]}"; do
    IFS=$'\t' read -r repo_name key_url keyring_path source_line list_path <<< "$line"
    local keyring_exists=0
    local list_has_source=0

    if [[ -f "$keyring_path" ]]; then
      keyring_exists=1
    fi

    if [[ -f "$list_path" ]] && grep -Fqx "$source_line" "$list_path" 2>/dev/null; then
      list_has_source=1
    fi

    if [[ "$keyring_exists" -eq 1 && "$list_has_source" -eq 1 ]]; then
      ok "Apt repo already configured: $repo_name"
      continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf "  [dry-run] Configure apt repo '%s'\n" "$repo_name"
      if [[ "$keyring_exists" -eq 0 ]]; then
        printf "  [dry-run] curl -fsSL %s | sudo gpg --dearmor -o %s\n" "$key_url" "$keyring_path"
      else
        printf "  [dry-run] keyring already present: %s\n" "$keyring_path"
      fi
      if [[ "$list_has_source" -eq 0 ]]; then
        printf "  [dry-run] printf '%%s\n' \"%s\" | sudo tee %s\n" "$source_line" "$list_path"
      else
        printf "  [dry-run] source line already present in: %s\n" "$list_path"
      fi
      continue
    fi

    if [[ "$keyring_exists" -eq 0 ]]; then
      curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring_path"
      sudo chmod a+r "$keyring_path"
    fi

    if [[ "$list_has_source" -eq 0 ]]; then
      sudo install -m 0755 -d "$(dirname "$list_path")"
      printf "%s\n" "$source_line" | sudo tee "$list_path" >/dev/null
    fi

    ok "Configured apt repo: $repo_name"
  done
}

run_script_installs() {
  local -a script_lines=("$@")
  if [[ ${#script_lines[@]} -eq 0 ]]; then
    ok "No script installs configured."
    return
  fi

  local line
  for line in "${script_lines[@]}"; do
    IFS=$'\t' read -r install_name check_cmd install_cmd <<< "$line"

    if bash -lc "$check_cmd" >/dev/null 2>&1; then
      ok "Already installed: $install_name"
      continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf "  [dry-run] %s\n" "$install_cmd"
      continue
    fi

    bash -lc "$install_cmd"
    ok "Installed via script: $install_name"
  done
}

ensure_zsh_default_shell() {
  if ! command -v zsh >/dev/null 2>&1; then
    warn "zsh not found; cannot set default shell."
    return
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"
  local current_shell
  current_shell="${SHELL:-}"

  if [[ "$current_shell" == "$zsh_path" ]]; then
    ok "Default shell already set to zsh."
    return
  fi

  if ! command -v chsh >/dev/null 2>&1; then
    warn "chsh not found. Set shell manually: chsh -s $zsh_path \"$USER\""
    return
  fi

  step "Configuring default shell"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] chsh -s %s %s\n" "$zsh_path" "$USER"
    warn "Dry-run mode: default shell was not changed."
    return
  fi

  chsh -s "$zsh_path" "$USER"
  SHELL_CHANGE_PENDING=1
  warn "Log out and back in for default shell change to take effect."
}

# --- Main -------------------------------------------------------------------

step "Pre-flight checks"
require_wsl_environment
if ! command -v jq >/dev/null 2>&1 || [[ "$SKIP_PACKAGES" -eq 0 ]]; then
  step "Refreshing apt package index"
  require_cmd sudo
  require_cmd apt-get
  run_cmd sudo apt-get update
fi
ensure_jq_installed
detect_json_parser

step "Manifest loading"
MANIFEST_PATH="$(detect_manifest_path)"
ok "Using manifest: $MANIFEST_PATH"

PACKAGE_MANAGER="$(manifest_get_scalar "$MANIFEST_PATH" "packageManager")"
if [[ -z "$PACKAGE_MANAGER" ]]; then
  err "Manifest key 'packageManager' is required."
  exit 1
fi
ok "Package manager: $PACKAGE_MANAGER"

# `systemPackages` is the primary key; `packages` is retained for backward compatibility.
load_array_from_command SYSTEM_PACKAGES manifest_get_list "$MANIFEST_PATH" "systemPackages"
if [[ ${#SYSTEM_PACKAGES[@]} -eq 0 ]]; then
  load_array_from_command SYSTEM_PACKAGES manifest_get_list "$MANIFEST_PATH" "packages"
fi

load_array_from_command OPTIONAL_PACKAGES manifest_get_list "$MANIFEST_PATH" "optionalPackages"
load_array_from_command MISE_RUNTIMES manifest_get_list "$MANIFEST_PATH" "miseRuntimes"
load_array_from_command APT_REPOS manifest_get_repo_lines "$MANIFEST_PATH" "aptRepositories"
load_array_from_command SCRIPT_INSTALLS manifest_get_script_lines "$MANIFEST_PATH" "scriptInstalls"
ok "Loaded system packages: ${#SYSTEM_PACKAGES[@]}"
ok "Loaded optional packages: ${#OPTIONAL_PACKAGES[@]}"
ok "Loaded apt repositories: ${#APT_REPOS[@]}"
ok "Loaded script installs: ${#SCRIPT_INSTALLS[@]}"
ok "Loaded mise runtimes: ${#MISE_RUNTIMES[@]}"

step "Package install"
if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
  case "$PACKAGE_MANAGER" in
    apt)
      require_cmd sudo
      require_cmd apt-get
      require_cmd curl
      require_cmd gpg
      step "Configuring apt repositories"
      configure_apt_repositories "${APT_REPOS[@]}"
      step "Installing system packages"
      install_with_apt "${SYSTEM_PACKAGES[@]}"
      if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
        step "Installing optional packages"
        for package_name in "${OPTIONAL_PACKAGES[@]}"; do
          if [[ "$DRY_RUN" -eq 1 ]]; then
            printf "  [dry-run] sudo apt-get install -y %s\n" "$package_name"
            continue
          fi
          if sudo apt-get install -y "$package_name"; then
            ok "Optional package installed: $package_name"
          else
            warn "Optional package unavailable: $package_name"
          fi
        done
      else
        ok "No optional packages listed in manifest."
      fi
      ;;
    *)
      err "Unsupported package manager for bootstrap-wsl.sh: $PACKAGE_MANAGER"
      err "Use manifests/linux.ubuntu.packages.json with packageManager set to 'apt'."
      exit 1
      ;;
  esac
else
  warn "Skipping package installation (--skip-packages)."
fi

step "Script installs"
run_script_installs "${SCRIPT_INSTALLS[@]}"
refresh_session_path

step "Runtime install"
if [[ "$SKIP_RUNTIMES" -eq 0 ]]; then
  if [[ ${#MISE_RUNTIMES[@]} -eq 0 ]]; then
    warn "No mise runtimes listed in manifest."
  elif command -v mise >/dev/null 2>&1; then
    for runtime in "${MISE_RUNTIMES[@]}"; do
      ensure_mise_runtime_installed "$runtime"
    done

    run_cmd mise reshim
    ok "mise shims refreshed"
    refresh_session_path

    if [[ "$DRY_RUN" -eq 1 ]]; then
      warn "Dry-run mode: runtime command validation skipped."
    else
      test_mise_runtime_commands "${MISE_RUNTIMES[@]}"
    fi
  else
    warn "mise is not installed or not on PATH; skipping runtimes."
    warn "Install mise first, then re-run this script or use --skip-runtimes."
  fi
else
  warn "Skipping runtime installation (--skip-runtimes)."
fi

step "Shell config"
ensure_zsh_default_shell

step "Done"
ok "WSL bootstrap completed."

printf "\nNext steps:\n"
printf "  1. Open a new shell session.\n"
if [[ "$SHELL_CHANGE_PENDING" -eq 1 ]]; then
  printf "  2. Log out and back in to apply default shell changes.\n"
else
  printf "  2. If needed, set default shell manually: chsh -s \"$(command -v zsh 2>/dev/null || printf '/usr/bin/zsh')\" \"$USER\"\n"
fi
printf "  3. Verify toolchain versions:\n"
printf "       zsh --version\n"
printf "       gh --version\n"
printf "       doppler --version\n"
printf "       mise --version\n"
printf "       starship --version\n"
printf "       opencode --version\n"
printf "       gopass version\n"
