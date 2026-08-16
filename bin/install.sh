#!/usr/bin/env bash
set -euo pipefail

REPO_ARCHIVE_URL="${REPO_ARCHIVE_URL:-https://github.com/newbish/debian-bootstrap/archive/refs/heads/main.tar.gz}"
WORK_DIR=""
ARCHIVE_FILE=""

usage() {
  cat <<'USAGE'
Usage: install.sh [bootstrap-debian.sh options]

Download the full Debian bootstrap repository archive, then run:
  ./bin/bootstrap-debian.sh [options]

This is intended for curl/bash one-liners on fresh Debian systems:
  curl -fsSL https://raw.githubusercontent.com/newbish/debian-bootstrap/main/bin/install.sh | bash -s -- --user alice

Environment overrides:
  REPO_ARCHIVE_URL=URL  archive to download; defaults to GitHub main branch tarball
USAGE
}

cleanup() {
  rm -rf ${WORK_DIR:+"$WORK_DIR"} ${ARCHIVE_FILE:+"$ARCHIVE_FILE"}
}
trap cleanup EXIT

need_command() {
  command -v "$1" >/dev/null 2>&1
}

install_missing_download_tools() {
  local missing=()
  need_command tar || missing+=(tar)
  need_command gzip || missing+=(gzip)

  if ! need_command curl && ! need_command wget; then
    missing+=(curl ca-certificates)
  fi

  [[ ${#missing[@]} -eq 0 ]] && return 0

  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Missing required command(s): ${missing[*]}" >&2
    echo "Install them first, or run this installer as root on Debian so apt-get can install them." >&2
    exit 1
  fi

  need_command apt-get || { echo "apt-get is required to install missing command(s): ${missing[*]}" >&2; exit 1; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends "${missing[@]}"
}

download_archive() {
  ARCHIVE_FILE="$(mktemp --suffix=.tar.gz)"

  case "$REPO_ARCHIVE_URL" in
    file://*)
      cp "${REPO_ARCHIVE_URL#file://}" "$ARCHIVE_FILE"
      ;;
    *)
      if need_command curl; then
        curl -fsSL "$REPO_ARCHIVE_URL" -o "$ARCHIVE_FILE"
      elif need_command wget; then
        wget -qO "$ARCHIVE_FILE" "$REPO_ARCHIVE_URL"
      else
        echo "curl or wget is required to download $REPO_ARCHIVE_URL" >&2
        exit 1
      fi
      ;;
  esac
}

extract_archive() {
  WORK_DIR="$(mktemp -d)"
  tar -xzf "$ARCHIVE_FILE" -C "$WORK_DIR"
}

find_repo_root() {
  local candidate
  candidate="$(find "$WORK_DIR" -type f -path '*/bin/bootstrap-debian.sh' -print -quit)"
  [[ -n "$candidate" ]] || { echo "Downloaded archive did not contain bin/bootstrap-debian.sh" >&2; exit 1; }
  dirname "$(dirname "$candidate")"
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  install_missing_download_tools
  download_archive
  extract_archive

  local repo_root
  repo_root="$(find_repo_root)"
  exec "$repo_root/bin/bootstrap-debian.sh" "$@"
}

main "$@"
