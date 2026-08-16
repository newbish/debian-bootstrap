#!/usr/bin/env bash
set -euo pipefail

export PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

usage() {
  cat <<'USAGE'
Usage: enable-passwordless-sudo.sh --user USER [options]

Enable passwordless sudo for a specific existing user by writing a dedicated
sudoers drop-in:
  /etc/sudoers.d/90-USER-nopasswd

Options:
  --user USER          existing user to grant passwordless sudo
  --target-root DIR    root filesystem to modify (default: /)
  -h, --help           show this help

This grants:
  USER ALL=(ALL:ALL) NOPASSWD:ALL
USAGE
}

CONFIG_USER="${CONFIG_USER:-}"
TARGET_ROOT="${TARGET_ROOT:-/}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) CONFIG_USER="${2:?--user requires a value}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?--target-root requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$CONFIG_USER" ]]; then
  echo "--user USER is required" >&2
  usage >&2
  exit 2
fi

if [[ ! "$CONFIG_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  echo "Invalid Unix username: $CONFIG_USER" >&2
  exit 2
fi

if [[ ! -d "$TARGET_ROOT" ]]; then
  echo "Target root does not exist: $TARGET_ROOT" >&2
  exit 2
fi

TARGET_ROOT="${TARGET_ROOT%/}"
[[ -n "$TARGET_ROOT" ]] || TARGET_ROOT="/"

in_target() {
  local rel="$1"
  if [[ "$TARGET_ROOT" == "/" ]]; then
    printf '/%s' "${rel#/}"
  else
    printf '%s/%s' "$TARGET_ROOT" "${rel#/}"
  fi
}

need_root_for_live_changes() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "This script must run as root when modifying a Debian system." >&2
    exit 1
  fi
}

user_exists() {
  if [[ "$TARGET_ROOT" == "/" ]]; then
    id "$CONFIG_USER" >/dev/null 2>&1
  else
    grep -qE "^${CONFIG_USER}:" "$(in_target /etc/passwd)"
  fi
}

validate_sudoers_file() {
  local sudoers_file="$1"
  if [[ "$TARGET_ROOT" == "/" ]] && command -v visudo >/dev/null 2>&1; then
    visudo -cf "$sudoers_file" >/dev/null
  fi
}

main() {
  [[ "$TARGET_ROOT" == "/" ]] && need_root_for_live_changes

  if ! user_exists; then
    echo "User '$CONFIG_USER' does not exist; create it first." >&2
    exit 1
  fi

  local sudoers_dir sudoers_file tmp_file
  sudoers_dir="$(in_target /etc/sudoers.d)"
  sudoers_file="$sudoers_dir/90-${CONFIG_USER}-nopasswd"
  tmp_file="${sudoers_file}.tmp.$$"

  mkdir -p "$sudoers_dir"
  printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$CONFIG_USER" > "$tmp_file"
  chmod 0440 "$tmp_file"
  validate_sudoers_file "$tmp_file"
  mv "$tmp_file" "$sudoers_file"
  chmod 0440 "$sudoers_file"

  echo "Passwordless sudo enabled for user '$CONFIG_USER'."
}

main "$@"
