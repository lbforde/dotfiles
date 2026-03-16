#!/usr/bin/env bash

set -euo pipefail

write_step() {
  printf '\n=== %s ===\n' "$1"
}

write_ok() {
  printf '  [ok] %s\n' "$1"
}

write_warn() {
  printf '  [warn] %s\n' "$1" >&2
}

if ! command -v mise >/dev/null 2>&1; then
  printf 'mise is not available on PATH. Install it first, then rerun this script.\n' >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 is required to validate the mise JSON output.\n' >&2
  exit 1
fi

mise_config_path="${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml"
if [[ ! -f "$mise_config_path" ]]; then
  printf 'Managed mise config not found at %s\n' "$mise_config_path" >&2
  exit 1
fi

write_step "Syncing mise tools"

mise install -y
write_ok "mise tools installed"

mise reshim
write_ok "mise shims refreshed"

missing_raw="$(mise ls --current --missing --json)"
if [[ -z "$missing_raw" ]]; then
  missing_raw='{}'
fi

missing_tools="$(python3 -c 'import json, sys; data = json.load(sys.stdin); print(",".join(data.keys()))' <<<"$missing_raw")"
if [[ -n "$missing_tools" ]]; then
  printf 'mise still reports missing current tools: %s\n' "$missing_tools" >&2
  exit 1
fi

write_ok "Validated current mise tools"
