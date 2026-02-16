#!/usr/bin/env bash
# ============================================================================
# Linux Developer Environment Bootstrap Script
# ============================================================================
# Installs and configures a Linux dev environment from manifest JSON files.
#
# Supported targets:
#   - Ubuntu / Debian-family (apt)
#   - Arch / Arch-family (pacman)
#
# Usage:
#   ./scripts/bootstrap-linux.sh
#   ./scripts/bootstrap-linux.sh --dry-run
#   ./scripts/bootstrap-linux.sh --skip-runtimes
#   ./scripts/bootstrap-linux.sh --manifest manifests/linux.ubuntu.packages.json

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
Usage: ./scripts/bootstrap-linux.sh [options]

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

# --- Detect distro and manifest ---------------------------------------------

detect_manifest_path() {
  if [[ -n "$MANIFEST_OVERRIDE" ]]; then
    if [[ -f "$MANIFEST_OVERRIDE" ]]; then
      printf "%s\n" "$MANIFEST_OVERRIDE"
      return
    fi
    if [[ -f "$REPO_ROOT/$MANIFEST_OVERRIDE" ]]; then
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
    arch|manjaro|endeavouros)
      printf "%s/manifests/linux.arch.packages.json\n" "$REPO_ROOT"
      return
      ;;
  esac

  # Fallback to ID_LIKE when ID is not one of our direct matches.
  if [[ "$distro_like" == *"debian"* ]]; then
    printf "%s/manifests/linux.ubuntu.packages.json\n" "$REPO_ROOT"
    return
  fi
  if [[ "$distro_like" == *"arch"* ]]; then
    printf "%s/manifests/linux.arch.packages.json\n" "$REPO_ROOT"
    return
  fi

  err "Unsupported distro (ID='$distro_id', ID_LIKE='$distro_like')."
  err "Pass --manifest <path> to force a manifest."
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

install_with_pacman() {
  local -a packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    warn "No pacman packages listed in manifest."
    return
  fi

  run_cmd sudo pacman -Sy --noconfirm
  run_cmd sudo pacman -S --noconfirm --needed "${packages[@]}"
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

mapfile -t MISE_RUNTIMES < <(manifest_get_list "$MANIFEST_PATH" "miseRuntimes")

if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
  step "Installing system packages"
  case "$PACKAGE_MANAGER" in
    apt)
      require_cmd sudo
      require_cmd apt-get
      install_with_apt "${SYSTEM_PACKAGES[@]}"
      ;;
    pacman)
      require_cmd sudo
      require_cmd pacman
      install_with_pacman "${SYSTEM_PACKAGES[@]}"
      ;;
    *)
      err "Unsupported package manager in manifest: $PACKAGE_MANAGER"
      exit 1
      ;;
  esac
else
  warn "Skipping package installation (--skip-packages)."
fi

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

step "Done"
ok "Linux bootstrap completed."
