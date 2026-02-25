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
#   ./scripts/bootstrap-wsl.sh --skip-packages
#   ./scripts/bootstrap-wsl.sh --skip-runtimes
#   ./scripts/bootstrap-wsl.sh --manifest manifests/linux.ubuntu.packages.json

set -euo pipefail

# --- CLI flags ---------------------------------------------------------------

DRY_RUN=0
SKIP_PACKAGES=0
SKIP_RUNTIMES=0
SKIP_CHEZMOI=0
MANIFEST_OVERRIDE=""
CHEZMOI_SOURCE_OVERRIDE=""
SHELL_CHANGE_PENDING=0
BOOTSTRAP_ARCH=""
BOOTSTRAP_APT_ARCH=""
UBUNTU_CODENAME=""
APT_REPOS_CHANGED=0

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
    --skip-chezmoi)
      SKIP_CHEZMOI=1
      shift
      ;;
    --chezmoi-source)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: --chezmoi-source requires a path or repo argument."
        exit 1
      fi
      CHEZMOI_SOURCE_OVERRIDE="$2"
      shift 2
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
  --chezmoi-source    Override chezmoi source path/repo for apply.
  --skip-packages     Skip package manager installs.
  --skip-runtimes     Skip mise runtime installs.
  --skip-chezmoi      Skip chezmoi config + apply.
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

UI_COLOR_ENABLED=0
UI_ICON_ENABLED=1
UI_SPINNER_ENABLED=0
UI_SPINNER_INTERVAL="${BOOTSTRAP_SPINNER_INTERVAL:-0.1}"
UI_SPINNER_STYLE="${BOOTSTRAP_SPINNER_STYLE:-1}"
UI_SPINNER_INDEX=0
UI_SPINNER_FRAMES=()

CLR_RESET=""
CLR_STEP=""
CLR_OK=""
CLR_WARN=""
CLR_ERR=""
CLR_SPIN=""
CLR_DIM=""
CLR_INFO=""

ICON_STEP="◆"
ICON_OK="✓"
ICON_WARN="⚠"
ICON_ERR="✗"
ICON_INFO="●"

set_spinner_frames() {
  local style="${1:-4}"
  case "$style" in
    1) UI_SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏") ;;
    2) UI_SPINNER_FRAMES=("◐" "◓" "◑" "◒") ;;
    3) UI_SPINNER_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷") ;;
    4) UI_SPINNER_FRAMES=("◰" "◳" "◲" "◱") ;;
    5) UI_SPINNER_FRAMES=("◜" "◠" "◝" "◞" "◡" "◟") ;;
    *) UI_SPINNER_FRAMES=("-" "\\" "|" "/") ;;
  esac
}

init_ui() {
  if [[ "${NO_COLOR:-}" != "" ]]; then
    UI_COLOR_ENABLED=0
  elif [[ -t 1 ]]; then
    UI_COLOR_ENABLED=1
  fi

  if [[ "${BOOTSTRAP_ASCII_ONLY:-0}" -eq 1 ]]; then
    UI_ICON_ENABLED=0
    UI_SPINNER_STYLE=0
  fi

  if [[ "$UI_COLOR_ENABLED" -eq 1 ]]; then
    CLR_RESET=$'\033[0m'
    CLR_STEP=$'\033[36m'
    CLR_OK=$'\033[32m'
    CLR_WARN=$'\033[33m'
    CLR_ERR=$'\033[31m'
    CLR_SPIN=$'\033[90m'
    CLR_DIM=$'\033[90m'
    CLR_INFO=$'\033[90m'
  fi

  if [[ "$UI_ICON_ENABLED" -eq 0 ]]; then
    ICON_STEP=">"
    ICON_OK="+"
    ICON_WARN="!"
    ICON_ERR="x"
    ICON_INFO="o"
  fi

  set_spinner_frames "$UI_SPINNER_STYLE"

  if [[ -t 1 && "${BOOTSTRAP_SPINNER:-1}" -eq 1 ]]; then
    UI_SPINNER_ENABLED=1
  fi
}

step() { printf "\n%s━━━ %s ━━━%s\n" "$CLR_STEP" "$1" "$CLR_RESET"; }
ok()   { printf "  %s%s %s%s\n" "$CLR_OK" "$ICON_OK" "$1" "$CLR_RESET"; }
warn() { printf "  %s%s %s%s\n" "$CLR_WARN" "$ICON_WARN" "$1" "$CLR_RESET"; }
err()  { printf "  %s%s %s%s\n" "$CLR_ERR" "$ICON_ERR" "$1" "$CLR_RESET" >&2; }
info() { printf "  %s%s %s%s\n" "$CLR_INFO" "$ICON_INFO" "$1" "$CLR_RESET"; }

next_spinner_frame() {
  local frame_count="${#UI_SPINNER_FRAMES[@]}"
  if [[ "$frame_count" -eq 0 ]]; then
    printf "."
    return
  fi

  local frame="${UI_SPINNER_FRAMES[$UI_SPINNER_INDEX]}"
  UI_SPINNER_INDEX=$(( (UI_SPINNER_INDEX + 1) % frame_count ))
  printf "%s" "$frame"
}

should_spin_command() {
  local command_name="${1:-}"
  case "$command_name" in
    sudo|apt-get|dpkg|chsh|chezmoi)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

run_cmd_with_spinner() {
  local cmd_display="$*"
  local output_file pid status frame

  output_file="$(mktemp)"
  "$@" >"$output_file" 2>&1 &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    frame="$(next_spinner_frame)"
    printf "\r\033[K  %s%s%s %s%s%s" "$CLR_SPIN" "$frame" "$CLR_RESET" "$CLR_DIM" "$cmd_display" "$CLR_RESET"
    sleep "$UI_SPINNER_INTERVAL"
  done

  if wait "$pid"; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -eq 0 ]]; then
    printf "\r\033[K"
  else
    printf "\r\033[K" >&2
    err "Command failed: $cmd_display"
    if [[ -s "$output_file" ]]; then
      cat "$output_file" >&2
    fi
  fi

  rm -f "$output_file"
  return "$status"
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  %s[dry-run]%s %s\n" "$CLR_DIM" "$CLR_RESET" "$*"
  else
    if [[ "$UI_SPINNER_ENABLED" -eq 1 ]] && should_spin_command "${1:-}"; then
      run_cmd_with_spinner "$@"
    else
      "$@"
    fi
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
    "$HOME/go/bin"
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

ensure_projects_directory() {
  local projects_dir="${PROJECTS:-$HOME/projects}"

  if [[ -d "$projects_dir" ]]; then
    ok "Projects directory already exists: $projects_dir"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] mkdir -p %s\n" "$projects_dir"
    return
  fi

  mkdir -p "$projects_dir"
  ok "Projects directory ready: $projects_dir"
}

normalize_shell_path() {
  local shell_path="$1"
  if [[ -z "$shell_path" ]]; then
    printf "\n"
    return
  fi

  if command -v readlink >/dev/null 2>&1; then
    local resolved_path
    resolved_path="$(readlink -f "$shell_path" 2>/dev/null || true)"
    if [[ -n "$resolved_path" ]]; then
      printf "%s\n" "$resolved_path"
      return
    fi
  fi

  printf "%s\n" "$shell_path"
}

get_login_shell() {
  local user_name="${1:-${USER:-}}"
  if [[ -z "$user_name" ]] && command -v id >/dev/null 2>&1; then
    user_name="$(id -un 2>/dev/null || true)"
  fi

  local passwd_entry=""
  if [[ -n "$user_name" ]] && command -v getent >/dev/null 2>&1; then
    passwd_entry="$(getent passwd "$user_name" 2>/dev/null || true)"
  fi

  if [[ -z "$passwd_entry" ]] && [[ -n "$user_name" ]]; then
    passwd_entry="$(awk -F: -v user="$user_name" '$1 == user { print; exit }' /etc/passwd 2>/dev/null || true)"
  fi

  if [[ -z "$passwd_entry" ]]; then
    printf "%s\n" "${SHELL:-}"
    return
  fi

  printf "%s\n" "${passwd_entry##*:}"
}

normalize_release_arch() {
  local raw_arch="${1:-}"
  case "$raw_arch" in
    x86_64|amd64)
      printf "x86_64\n"
      ;;
    aarch64|arm64)
      printf "aarch64\n"
      ;;
    *)
      err "Unsupported architecture '$raw_arch'."
      err "Supported architectures: x86_64, aarch64."
      exit 1
      ;;
  esac
}

detect_bootstrap_arch() {
  local uname_arch
  uname_arch="$(uname -m 2>/dev/null || true)"
  if [[ -z "$uname_arch" ]]; then
    err "Unable to determine architecture from uname -m."
    exit 1
  fi

  normalize_release_arch "$uname_arch"
}

detect_apt_architecture() {
  if command -v dpkg >/dev/null 2>&1; then
    dpkg --print-architecture
    return
  fi

  # Fallback used only when dpkg is not yet available in PATH.
  case "$BOOTSTRAP_ARCH" in
    x86_64) printf "amd64\n" ;;
    aarch64) printf "arm64\n" ;;
    *) printf "amd64\n" ;;
  esac
}

detect_ubuntu_codename() {
  if [[ ! -f /etc/os-release ]]; then
    err "/etc/os-release not found; cannot determine Ubuntu codename."
    exit 1
  fi

  local version_codename=""
  local ubuntu_codename=""

  # shellcheck disable=SC1091
  source /etc/os-release
  version_codename="${VERSION_CODENAME:-}"
  ubuntu_codename="${UBUNTU_CODENAME:-}"

  if [[ -n "$version_codename" ]]; then
    printf "%s\n" "$version_codename"
    return
  fi

  if [[ -n "$ubuntu_codename" ]]; then
    printf "%s\n" "$ubuntu_codename"
    return
  fi

  err "Could not determine Ubuntu codename from /etc/os-release."
  exit 1
}

render_source_line() {
  local source_line="$1"

  source_line="${source_line//\$\{APT_ARCH\}/$BOOTSTRAP_APT_ARCH}"
  source_line="${source_line//\$\{UBUNTU_CODENAME\}/$UBUNTU_CODENAME}"
  printf "%s\n" "$source_line"
}

csv_contains_value() {
  local csv="$1"
  local needle="$2"
  local item

  if [[ -z "$csv" ]]; then
    return 1
  fi

  IFS=',' read -r -a items <<< "$csv"
  for item in "${items[@]}"; do
    if [[ "${item,,}" == "${needle,,}" ]]; then
      return 0
    fi
  done

  return 1
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
    info "$runtime_spec already installed"
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
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "Dry-run mode still installs jq because manifest parsing requires it."
    sudo apt-get update
  fi
  sudo apt-get install -y jq
  ok "jq installed."
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
    | (.codenameAllowList // []) as $codename_allow_list
    | if ($codename_allow_list | type) != "array" then
        error("Repo entries in \($key) require codenameAllowList to be an array when provided.")
      elif ($codename_allow_list | all(.[]; type == "string")) | not then
        error("Repo entries in \($key) require codenameAllowList values to be strings.")
      else
        .
      end
    | [.name, .keyUrl, .keyringPath, .sourceLine, .listPath] as $fields
    | if any($fields[]; . == null or (tostring | gsub("^\\s+|\\s+$"; "") == "")) then
        error("Repo entries in \($key) require name, keyUrl, keyringPath, sourceLine, and listPath.")
      else
        (($fields + [($codename_allow_list | join(","))]) | map(tostring) | @tsv)
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
    | .phase = ((.phase // "pre-runtime") | tostring | ascii_downcase)
    | if (.phase | test("^(pre-runtime|post-runtime)$")) | not then
        error("Script install entries in \($key) require phase to be pre-runtime or post-runtime.")
      else
        .
      end
    | [.name, .checkCommand, .installCommand] as $fields
    | if any($fields[]; . == null or (tostring | gsub("^\\s+|\\s+$"; "") == "")) then
        error("Script install entries in \($key) require name, checkCommand, and installCommand.")
      else
        (($fields + [.phase]) | map(tostring) | @tsv)
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

is_apt_package_installed() {
  local package_name="$1"
  local package_status
  package_status="$(dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null || true)"
  [[ "$package_status" == "install ok installed" ]]
}

install_with_apt() {
  local -a packages=("$@")
  if [[ ${#packages[@]} -eq 0 ]]; then
    warn "No apt packages listed in manifest."
    return
  fi

  local -a missing_packages=()
  local package_name
  for package_name in "${packages[@]}"; do
    if is_apt_package_installed "$package_name"; then
      info "System package already installed: $package_name"
      continue
    fi

    missing_packages+=("$package_name")
  done

  if [[ ${#missing_packages[@]} -eq 0 ]]; then
    ok "All system packages already installed."
    return
  fi

  run_cmd sudo apt-get install -y "${missing_packages[@]}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "Dry-run: would install ${#missing_packages[@]} missing system packages."
  else
    ok "Installed ${#missing_packages[@]} missing system packages."
  fi
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
    IFS=$'\t' read -r repo_name key_url keyring_path source_line list_path codename_allow_list <<< "$line"
    local rendered_source_line
    rendered_source_line="$(render_source_line "$source_line")"
    local keyring_exists=0
    local list_has_source=0

    if [[ -n "$codename_allow_list" ]] && ! csv_contains_value "$codename_allow_list" "$UBUNTU_CODENAME"; then
      warn "Skipping apt repo '$repo_name' for unsupported codename '$UBUNTU_CODENAME' (allowed: $codename_allow_list)."
      continue
    fi

    if [[ -f "$keyring_path" ]]; then
      keyring_exists=1
    fi

    if [[ -f "$list_path" ]] && grep -Fqx "$rendered_source_line" "$list_path" 2>/dev/null; then
      list_has_source=1
    fi

    if [[ "$keyring_exists" -eq 1 && "$list_has_source" -eq 1 ]]; then
      ok "Apt repo already configured: $repo_name"
      continue
    fi
    APT_REPOS_CHANGED=1

    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf "  [dry-run] Configure apt repo '%s'\n" "$repo_name"
      if [[ "$keyring_exists" -eq 0 ]]; then
        printf "  [dry-run] curl -fsSL %s | sudo gpg --dearmor -o %s\n" "$key_url" "$keyring_path"
      else
        printf "  [dry-run] keyring already present: %s\n" "$keyring_path"
      fi
      if [[ "$list_has_source" -eq 0 ]]; then
        printf "  [dry-run] printf '%%s\n' \"%s\" | sudo tee %s\n" "$rendered_source_line" "$list_path"
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
      printf "%s\n" "$rendered_source_line" | sudo tee "$list_path" >/dev/null
    fi

    ok "Configured apt repo: $repo_name"
  done
}

run_script_installs() {
  local target_phase="$1"
  shift
  local -a script_lines=("$@")
  if [[ ${#script_lines[@]} -eq 0 ]]; then
    ok "No script installs configured."
    return
  fi

  local matched_phase=0
  local line
  for line in "${script_lines[@]}"; do
    IFS=$'\t' read -r install_name check_cmd install_cmd install_phase <<< "$line"
    if [[ "$install_phase" != "$target_phase" ]]; then
      continue
    fi
    matched_phase=1

    if bash -lc "$check_cmd" >/dev/null 2>&1; then
      info "Already installed: $install_name"
      continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf "  [dry-run] %s\n" "$install_cmd"
      continue
    fi

    if ! bash -lc "$install_cmd"; then
      err "Failed script install: $install_name"
      exit 1
    fi
    ok "Installed via script: $install_name"
  done

  if [[ "$matched_phase" -eq 0 ]]; then
    ok "No script installs configured for phase '$target_phase'."
  fi
}

prompt_with_default() {
  local prompt_text="$1"
  local default_value="${2:-}"
  local input_value=""

  if [[ -n "$default_value" ]]; then
    read -r -p "  ${prompt_text} [${default_value}]: " input_value
    input_value="${input_value:-$default_value}"
  else
    read -r -p "  ${prompt_text}: " input_value
  fi

  printf "%s\n" "$input_value"
}

toml_escape() {
  local raw_value="$1"
  raw_value="${raw_value//\\/\\\\}"
  raw_value="${raw_value//\"/\\\"}"
  printf "%s\n" "$raw_value"
}

get_chezmoi_source_path() {
  if ! command -v chezmoi >/dev/null 2>&1; then
    printf "\n"
    return
  fi

  chezmoi source-path 2>/dev/null || true
}

get_chezmoi_remote_origin() {
  if ! command -v chezmoi >/dev/null 2>&1; then
    printf "\n"
    return
  fi

  chezmoi git -- remote get-url origin 2>/dev/null || true
}

test_chezmoi_has_managed_files() {
  if ! command -v chezmoi >/dev/null 2>&1; then
    return 1
  fi

  local managed_output
  managed_output="$(chezmoi managed 2>/dev/null || true)"
  [[ -n "${managed_output//[[:space:]]/}" ]]
}

resolve_path_or_keep() {
  local input_path="$1"
  if [[ -z "$input_path" ]]; then
    printf "\n"
    return
  fi

  if command -v readlink >/dev/null 2>&1; then
    local resolved_path
    resolved_path="$(readlink -f "$input_path" 2>/dev/null || true)"
    if [[ -n "$resolved_path" ]]; then
      printf "%s\n" "$resolved_path"
      return
    fi
  fi

  printf "%s\n" "$input_path"
}

get_chezmoi_source_root_path() {
  local source_path="$1"
  if [[ -z "$source_path" ]]; then
    printf "\n"
    return
  fi

  local resolved_source
  resolved_source="$(resolve_path_or_keep "$source_path")"
  local source_parent
  source_parent="$(dirname "$resolved_source")"
  local root_marker="$source_parent/.chezmoiroot"

  if [[ -f "$root_marker" ]]; then
    local root_dir_name
    root_dir_name="$(tr -d '\r\n' < "$root_marker")"
    local source_leaf
    source_leaf="$(basename "$resolved_source")"
    if [[ -n "$root_dir_name" && "$source_leaf" == "$root_dir_name" ]]; then
      resolve_path_or_keep "$source_parent"
      return
    fi
  fi

  printf "%s\n" "$resolved_source"
}

get_default_chezmoi_source_root() {
  resolve_path_or_keep "$HOME/.local/share/chezmoi"
}

backup_chezmoi_source_root() {
  local source_root="$1"
  if [[ ! -e "$source_root" ]]; then
    warn "Chezmoi source backup skipped; source root not found: $source_root"
    return
  fi

  local timestamp backup_path
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_path="${source_root}.backup-${timestamp}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] cp -a %s %s\n" "$source_root" "$backup_path"
    return
  fi

  cp -a "$source_root" "$backup_path"
  ok "Backed up current chezmoi source to $backup_path"
}

initialize_local_chezmoi_config() {
  local config_dir="$HOME/.config/chezmoi"
  local config_path="$config_dir/chezmoi.toml"

  if [[ -f "$config_path" ]]; then
    if grep -Eq 'Your Name|your@email\.com' "$config_path"; then
      warn "Local chezmoi config still has placeholder identity values: $config_path"
    else
      ok "Local chezmoi config already present"
    fi
    return
  fi

  local default_name default_email user_name user_email
  default_name="$(git config --global user.name 2>/dev/null || true)"
  default_email="$(git config --global user.email 2>/dev/null || true)"
  user_name="$default_name"
  user_email="$default_email"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] create local chezmoi config at %s\n" "$config_path"
    return
  fi

  if [[ -z "$user_name" || -z "$user_email" ]]; then
    if [[ -t 0 ]]; then
      if [[ -z "$user_name" ]]; then
        user_name="$(prompt_with_default "Git user.name" "$default_name")"
      fi
      if [[ -z "$user_email" ]]; then
        user_email="$(prompt_with_default "Git user.email" "$default_email")"
      fi
    fi
  fi

  if [[ -z "$user_name" || -z "$user_email" ]]; then
    err "Git identity is required for local chezmoi config."
    err "Set git config values first (git config --global user.name / user.email) or re-run interactively."
    exit 1
  fi

  mkdir -p "$config_dir"
  user_name="$(toml_escape "$user_name")"
  user_email="$(toml_escape "$user_email")"

  cat >"$config_path" <<EOF
# Local Chezmoi runtime config (machine-specific)
[data]
    name  = "$user_name"
    email = "$user_email"

[git]
    autoCommit = false
    autoPush   = false

[template]
    # Valid options are default/invalid, zero, or error.
    options = ["missingkey=default"]
EOF

  ok "Created local chezmoi config at $config_path"
}

set_local_chezmoi_source_dir() {
  local source_dir="$1"
  local config_path="$HOME/.config/chezmoi/chezmoi.toml"

  if [[ ! -f "$config_path" ]]; then
    err "Local chezmoi config not found at $config_path"
    exit 1
  fi

  local normalized_source
  normalized_source="$(resolve_path_or_keep "$source_dir")"
  local source_line
  source_line="sourceDir = \"${normalized_source}\""

  if grep -Fqx "$source_line" "$config_path" 2>/dev/null; then
    ok "Local chezmoi sourceDir already set to $normalized_source"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] set local chezmoi sourceDir to %s in %s\n" "$normalized_source" "$config_path"
    return
  fi

  local tmp_config
  tmp_config="$(mktemp)"
  {
    printf "%s\n\n" "$source_line"
    grep -Ev '^[[:space:]]*sourceDir[[:space:]]*=' "$config_path" || true
  } >"$tmp_config"

  if cmp -s "$tmp_config" "$config_path"; then
    rm -f "$tmp_config"
    ok "Local chezmoi sourceDir already set to $normalized_source"
    return
  fi

  local timestamp backup_path
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_path="${config_path}.${timestamp}.bak"
  cp "$config_path" "$backup_path"
  mv "$tmp_config" "$config_path"
  ok "Set local chezmoi sourceDir to $normalized_source (backup: $backup_path)"
}

resolve_desired_chezmoi_source() {
  if [[ -n "$CHEZMOI_SOURCE_OVERRIDE" ]]; then
    printf "%s\n" "$CHEZMOI_SOURCE_OVERRIDE"
    return
  fi

  printf "%s\n" "$REPO_ROOT"
}

invoke_chezmoi_apply() {
  local desired_source="$1"

  if ! command -v chezmoi >/dev/null 2>&1; then
    warn "chezmoi is not available on PATH; skipping dotfile apply."
    return
  fi

  local desired_is_remote=0
  if [[ "$desired_source" =~ ^(https?|ssh):// ]] || [[ "$desired_source" =~ ^git@ ]]; then
    desired_is_remote=1
  fi

  if [[ "$desired_is_remote" -eq 0 ]]; then
    local desired_path
    desired_path="$(resolve_path_or_keep "$desired_source")"
    local current_source current_source_root default_source_root
    current_source="$(get_chezmoi_source_path)"
    current_source_root="$(get_chezmoi_source_root_path "$current_source")"
    default_source_root="$(get_default_chezmoi_source_root)"

    info "Chezmoi source mode: direct-path"
    info "Desired source root: $desired_path"

    if test_chezmoi_has_managed_files && [[ -n "$current_source_root" && "$current_source_root" != "$desired_path" && "$current_source_root" == "$default_source_root" ]]; then
      backup_chezmoi_source_root "$current_source_root"
    elif test_chezmoi_has_managed_files && [[ -n "$current_source_root" && "$current_source_root" != "$desired_path" && "$current_source_root" != "$default_source_root" ]]; then
      warn "Chezmoi source is already direct-path from a different local path."
      warn "Current source root: $current_source_root"
      warn "Desired source root: $desired_path"
      warn "Keeping existing source and applying current state."
      run_cmd chezmoi apply
      if [[ "$DRY_RUN" -eq 0 ]]; then
        ok "Chezmoi apply complete"
      fi
      return
    fi

    set_local_chezmoi_source_dir "$desired_path"
    run_cmd chezmoi apply
    if [[ "$DRY_RUN" -eq 0 ]]; then
      local final_source
      final_source="$(get_chezmoi_source_path)"
      ok "Chezmoi apply complete"
      info "Final chezmoi source-path: $final_source"
    fi
    return
  fi

  local current_source
  current_source="$(get_chezmoi_source_path)"
  if [[ -z "$current_source" ]] || ! test_chezmoi_has_managed_files; then
    run_cmd chezmoi init --apply "$desired_source"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      ok "Chezmoi initialised and applied from $desired_source"
    fi
    return
  fi

  local current_origin
  current_origin="$(get_chezmoi_remote_origin)"
  if [[ -n "$current_origin" && "$current_origin" != "$desired_source" ]]; then
    warn "Chezmoi source is already initialised from a different origin."
    warn "Current origin: $current_origin"
    warn "Desired origin: $desired_source"
    warn "Keeping existing source and applying current state."
  elif [[ -z "$current_origin" ]]; then
    warn "Could not determine current chezmoi origin; keeping existing source and applying current state."
  fi

  run_cmd chezmoi apply
  if [[ "$DRY_RUN" -eq 0 ]]; then
    ok "Chezmoi apply complete"
  fi
}

configure_chezmoi() {
  if ! command -v chezmoi >/dev/null 2>&1; then
    warn "chezmoi is not available on PATH; skipping dotfile apply."
    return
  fi

  initialize_local_chezmoi_config
  local desired_source
  desired_source="$(resolve_desired_chezmoi_source)"
  invoke_chezmoi_apply "$desired_source"
}

ensure_zsh_default_shell() {
  if ! command -v zsh >/dev/null 2>&1; then
    warn "zsh not found; cannot set default shell."
    return
  fi

  local zsh_path
  zsh_path="$(command -v zsh)"
  local user_name
  user_name="${USER:-$(id -un 2>/dev/null || true)}"
  if [[ -z "$user_name" ]]; then
    warn "Could not determine current user; cannot set default shell."
    return
  fi
  local login_shell
  login_shell="$(get_login_shell "$user_name")"
  local normalized_zsh_path
  normalized_zsh_path="$(normalize_shell_path "$zsh_path")"
  local normalized_login_shell
  normalized_login_shell="$(normalize_shell_path "$login_shell")"

  if [[ -n "$normalized_login_shell" && "$normalized_login_shell" == "$normalized_zsh_path" ]]; then
    ok "Default shell already set to zsh (login shell: $login_shell)."
    return
  fi

  if ! command -v chsh >/dev/null 2>&1; then
    warn "chsh not found. Set shell manually: chsh -s $zsh_path \"$user_name\""
    return
  fi

  step "Configuring default shell"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] chsh -s %s %s\n" "$zsh_path" "$user_name"
    warn "Dry-run mode: default shell was not changed."
    return
  fi

  chsh -s "$zsh_path" "$user_name"

  local updated_login_shell
  updated_login_shell="$(get_login_shell "$user_name")"
  local normalized_updated_login_shell
  normalized_updated_login_shell="$(normalize_shell_path "$updated_login_shell")"

  if [[ -n "$normalized_updated_login_shell" && "$normalized_updated_login_shell" == "$normalized_zsh_path" ]]; then
    SHELL_CHANGE_PENDING=1
    warn "Log out and back in for default shell change to take effect."
    return
  fi

  warn "chsh completed but login shell still reports '$updated_login_shell'. Verify /etc/passwd and retry."
}

ensure_zinit_installed() {
  local zinit_home="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
  local zinit_parent
  zinit_parent="$(dirname "$zinit_home")"

  if [[ -d "$zinit_home/.git" ]]; then
    ok "Zinit already installed: $zinit_home"
    return
  fi

  if [[ -e "$zinit_home" ]]; then
    warn "Zinit path exists but is not a git clone: $zinit_home"
    warn "Remove it and rerun bootstrap to reinstall Zinit."
    return
  fi

  step "Installing Zinit"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf "  [dry-run] mkdir -p %s\n" "$zinit_parent"
    printf "  [dry-run] git clone %s %s\n" "https://github.com/zdharma-continuum/zinit.git" "$zinit_home"
    return
  fi

  require_cmd git
  mkdir -p "$zinit_parent"
  run_cmd git clone "https://github.com/zdharma-continuum/zinit.git" "$zinit_home"
  ok "Installed Zinit: $zinit_home"
}

# --- Main -------------------------------------------------------------------

init_ui
step "Pre-flight checks"
require_wsl_environment
BOOTSTRAP_ARCH="$(detect_bootstrap_arch)"
BOOTSTRAP_APT_ARCH="$(detect_apt_architecture)"
UBUNTU_CODENAME="$(detect_ubuntu_codename)"
export BOOTSTRAP_ARCH BOOTSTRAP_APT_ARCH UBUNTU_CODENAME
info "Release architecture: $BOOTSTRAP_ARCH (apt: $BOOTSTRAP_APT_ARCH)"
info "Ubuntu codename: $UBUNTU_CODENAME"
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
      require_cmd dpkg-query
      require_cmd curl
      require_cmd gpg
      step "Configuring apt repositories"
      configure_apt_repositories "${APT_REPOS[@]}"
      if [[ "$APT_REPOS_CHANGED" -eq 1 ]]; then
        step "Refreshing apt package index (post-repo changes)"
        run_cmd sudo apt-get update
      fi
      step "Installing system packages"
      install_with_apt "${SYSTEM_PACKAGES[@]}"
      if [[ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]]; then
        step "Installing optional packages"
        for package_name in "${OPTIONAL_PACKAGES[@]}"; do
          if is_apt_package_installed "$package_name"; then
            info "Optional package already installed: $package_name"
            continue
          fi

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
        info "No optional packages listed in manifest."
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

step "Script installs (pre-runtime)"
run_script_installs "pre-runtime" "${SCRIPT_INSTALLS[@]}"
refresh_session_path

step "Chezmoi apply"
if [[ "$SKIP_CHEZMOI" -eq 1 ]]; then
  warn "Skipping chezmoi config/apply (--skip-chezmoi)."
else
  configure_chezmoi
fi

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

step "Script installs (post-runtime)"
if [[ "$SKIP_RUNTIMES" -eq 1 ]]; then
  warn "Skipping post-runtime script installs because runtimes were skipped (--skip-runtimes)."
else
  run_script_installs "post-runtime" "${SCRIPT_INSTALLS[@]}"
  refresh_session_path
fi

step "Workspace setup"
ensure_projects_directory

step "Shell config"
ensure_zsh_default_shell
ensure_zinit_installed

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
printf "       zsh -ic 'zi --version'\n"
printf "       gh --version\n"
printf "       doppler --version\n"
printf "       chezmoi --version\n"
printf "       mise --version\n"
printf "       zsh -ic 'starship --version'\n"
printf "       opencode --version\n"
printf "       zoxide --version\n"
printf "       yazi --version\n"
printf "       ya --version\n"
printf "       eza --version\n"
printf "       lazygit --version\n"
printf "       croc --version\n"
printf "       grex --version\n"
printf "       cmake --version\n"
printf "       gopass version\n"
