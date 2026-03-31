#!/usr/bin/env bash

set -euo pipefail

tpm_dir="${HOME}/.tmux/plugins/tpm"
tpm_parent_dir="${HOME}/.tmux/plugins"
tpm_repo_url="https://github.com/tmux-plugins/tpm"

is_expected_tpm_remote() {
  local remote_url="$1"

  case "$remote_url" in
    https://github.com/tmux-plugins/tpm|https://github.com/tmux-plugins/tpm.git|git@github.com:tmux-plugins/tpm|git@github.com:tmux-plugins/tpm.git)
      return 0
      ;;
  esac

  return 1
}

if ! command -v git >/dev/null 2>&1; then
  printf 'git is required to install TPM\n' >&2
  exit 1
fi

mkdir -p "$tpm_parent_dir"

if [[ -e "$tpm_dir" ]]; then
  if [[ ! -d "$tpm_dir" ]]; then
    printf 'TPM path exists but is not a directory: %s\n' "$tpm_dir" >&2
    exit 1
  fi

  if ! git -C "$tpm_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'TPM directory exists but is not a git checkout: %s\n' "$tpm_dir" >&2
    exit 1
  fi

  remote_url="$(git -C "$tpm_dir" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    printf 'TPM checkout is missing an origin remote: %s\n' "$tpm_dir" >&2
    exit 1
  fi

  if ! is_expected_tpm_remote "$remote_url"; then
    printf 'TPM checkout points to an unexpected remote: %s\n' "$remote_url" >&2
    exit 1
  fi

  if [[ ! -f "$tpm_dir/tpm" || ! -f "$tpm_dir/bin/install_plugins" ]]; then
    printf 'TPM checkout looks incomplete at %s\n' "$tpm_dir" >&2
    exit 1
  fi

  printf 'TPM already installed at %s\n' "$tpm_dir"
  exit 0
fi

git clone "$tpm_repo_url" "$tpm_dir"
printf 'Installed TPM to %s\n' "$tpm_dir"
