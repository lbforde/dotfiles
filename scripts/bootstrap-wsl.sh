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

# --- Manifest helpers --------------------------------------------------------

manifest_get_scalar() {
  local manifest_path="$1"
  local key="$2"
  python3 - "$manifest_path" "$key" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

value = data.get(key, "")
if value is None:
    value = ""
print(str(value))
PY
}

manifest_get_list() {
  local manifest_path="$1"
  local key="$2"
  python3 - "$manifest_path" "$key" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

value = data.get(key, [])
if value is None:
    value = []

if not isinstance(value, list):
    raise SystemExit(f"Manifest key '{key}' must be a JSON array.")

for item in value:
    if not isinstance(item, str):
        raise SystemExit(f"Manifest key '{key}' must contain only strings.")
    print(item)
PY
}

manifest_get_repo_lines() {
  local manifest_path="$1"
  local key="$2"
  python3 - "$manifest_path" "$key" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

repos = data.get(key, [])
if repos is None:
    repos = []
if not isinstance(repos, list):
    raise SystemExit(f"Manifest key '{key}' must be a JSON array.")

for repo in repos:
    if not isinstance(repo, dict):
        raise SystemExit(f"Manifest key '{key}' must contain only objects.")
    name = str(repo.get("name", "")).strip()
    key_url = str(repo.get("keyUrl", "")).strip()
    keyring_path = str(repo.get("keyringPath", "")).strip()
    source_line = str(repo.get("sourceLine", "")).strip()
    list_path = str(repo.get("listPath", "")).strip()
    if not name or not key_url or not keyring_path or not source_line or not list_path:
        raise SystemExit(f"Repo entries in '{key}' require name, keyUrl, keyringPath, sourceLine, and listPath.")
    print("\t".join([name, key_url, keyring_path, source_line, list_path]))
PY
}

manifest_get_script_lines() {
  local manifest_path="$1"
  local key="$2"
  python3 - "$manifest_path" "$key" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

installs = data.get(key, [])
if installs is None:
    installs = []
if not isinstance(installs, list):
    raise SystemExit(f"Manifest key '{key}' must be a JSON array.")

for item in installs:
    if not isinstance(item, dict):
        raise SystemExit(f"Manifest key '{key}' must contain only objects.")
    name = str(item.get("name", "")).strip()
    check_cmd = str(item.get("checkCommand", "")).strip()
    install_cmd = str(item.get("installCommand", "")).strip()
    if not name or not check_cmd or not install_cmd:
        raise SystemExit(f"Script install entries in '{key}' require name, checkCommand, and installCommand.")
    print("\t".join([name, check_cmd, install_cmd]))
PY
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

# --- Package manager install routines ---------------------------------------

install_with_apt() {
  local -a packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    warn "No apt packages listed in manifest."
    return
  fi

  run_cmd sudo apt-get update
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

    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf "  [dry-run] Configure apt repo '%s'\n" "$repo_name"
      printf "  [dry-run] curl -fsSL %s | sudo gpg --dearmor -o %s\n" "$key_url" "$keyring_path"
      printf "  [dry-run] printf '%%s\n' \"%s\" | sudo tee %s\n" "$source_line" "$list_path"
      continue
    fi

    curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring_path"
    sudo chmod a+r "$keyring_path"
    printf "%s\n" "$source_line" | sudo tee "$list_path" >/dev/null
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
  run_cmd chsh -s "$zsh_path" "$USER"
  warn "Log out and back in for default shell change to take effect."
}

# --- Main -------------------------------------------------------------------

step "Pre-flight checks"
require_cmd python3

MANIFEST_PATH="$(detect_manifest_path)"
ok "Using manifest: $MANIFEST_PATH"

PACKAGE_MANAGER="$(manifest_get_scalar "$MANIFEST_PATH" "packageManager")"
if [[ -z "$PACKAGE_MANAGER" ]]; then
  err "Manifest key 'packageManager' is required."
  exit 1
fi
ok "Package manager: $PACKAGE_MANAGER"

# `systemPackages` is the primary key; `packages` is retained for backward compatibility.
mapfile -t SYSTEM_PACKAGES < <(manifest_get_list "$MANIFEST_PATH" "systemPackages")
if [[ ${#SYSTEM_PACKAGES[@]} -eq 0 ]]; then
  mapfile -t SYSTEM_PACKAGES < <(manifest_get_list "$MANIFEST_PATH" "packages")
fi

mapfile -t OPTIONAL_PACKAGES < <(manifest_get_list "$MANIFEST_PATH" "optionalPackages")
mapfile -t MISE_RUNTIMES < <(manifest_get_list "$MANIFEST_PATH" "miseRuntimes")
mapfile -t APT_REPOS < <(manifest_get_repo_lines "$MANIFEST_PATH" "aptRepositories")
mapfile -t SCRIPT_INSTALLS < <(manifest_get_script_lines "$MANIFEST_PATH" "scriptInstalls")

if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
  step "Installing system packages"
  case "$PACKAGE_MANAGER" in
    apt)
      require_cmd sudo
      require_cmd apt-get
      require_cmd curl
      require_cmd gpg
      step "Configuring apt repositories"
      configure_apt_repositories "${APT_REPOS[@]}"
      step "Refreshing apt package index"
      run_cmd sudo apt-get update
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

step "Running script-based installs"
run_script_installs "${SCRIPT_INSTALLS[@]}"

if [[ "$SKIP_RUNTIMES" -eq 0 ]]; then
  step "Installing runtimes via mise"
  if [[ ${#MISE_RUNTIMES[@]} -eq 0 ]]; then
    warn "No mise runtimes listed in manifest."
  elif command -v mise >/dev/null 2>&1; then
    for runtime in "${MISE_RUNTIMES[@]}"; do
      run_cmd mise use --global "$runtime"
      ok "Installed runtime: $runtime"
    done
  else
    warn "mise is not installed or not on PATH; skipping runtimes."
    warn "Install mise first, then re-run this script or use --skip-runtimes."
  fi
else
  warn "Skipping runtime installation (--skip-runtimes)."
fi

ensure_zsh_default_shell

step "Done"
ok "WSL bootstrap completed."
