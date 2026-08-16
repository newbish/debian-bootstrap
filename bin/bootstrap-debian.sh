#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bootstrap-debian.sh [options]

Configure a Debian system with Keith's baseline preferences:
  - install sudo, vim, and ncurses-bin
  - ensure the configured user exists and is in the sudo group
  - configure visudo to use vim
  - add /sbin and /usr/sbin to the default PATH for all users
  - install Ghostty terminfo globally

Configuration precedence:
  built-in defaults < config file < environment < command line

Options:
  --config FILE        config file to load (default: config/default.conf)
  --user USER          user to configure (default from config: debian)
  --target-root DIR    root filesystem to modify (default: /)
  --skip-packages      do not run apt-get; useful for tests or pre-baked images
  --no-create-user     fail if USER does not exist instead of creating it
  -h, --help           show this help

Environment overrides:
  CONFIG_USER=USER, TARGET_ROOT=DIR, SKIP_PACKAGES=1, CREATE_USER=0, CONFIG_FILE=FILE
USAGE
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TERMINFO_SOURCE="$REPO_ROOT/terminfo/xterm-ghostty.terminfo"

ENV_CONFIG_USER="${CONFIG_USER-}"
ENV_TARGET_ROOT="${TARGET_ROOT-}"
ENV_SKIP_PACKAGES="${SKIP_PACKAGES-}"
ENV_CREATE_USER="${CREATE_USER-}"

CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/config/default.conf}"
CONFIG_USER="debian"
TARGET_ROOT="/"
SKIP_PACKAGES="0"
CREATE_USER="1"

# Pre-parse --config and --help so config defaults can be loaded before final option parsing.
args=("$@")
idx=0
while [[ $idx -lt ${#args[@]} ]]; do
  case "${args[$idx]}" in
    --config)
      next=$((idx + 1))
      CONFIG_FILE="${args[$next]:?--config requires a value}"
      idx=$((idx + 2))
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) idx=$((idx + 1)) ;;
  esac
done

if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file does not exist: $CONFIG_FILE" >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

[[ -n "$ENV_CONFIG_USER" ]] && CONFIG_USER="$ENV_CONFIG_USER"
[[ -n "$ENV_TARGET_ROOT" ]] && TARGET_ROOT="$ENV_TARGET_ROOT"
[[ -n "$ENV_SKIP_PACKAGES" ]] && SKIP_PACKAGES="$ENV_SKIP_PACKAGES"
[[ -n "$ENV_CREATE_USER" ]] && CREATE_USER="$ENV_CREATE_USER"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="${2:?--config requires a value}"; shift 2 ;;
    --user) CONFIG_USER="${2:?--user requires a value}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?--target-root requires a value}"; shift 2 ;;
    --skip-packages) SKIP_PACKAGES=1; shift ;;
    --no-create-user) CREATE_USER=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$CONFIG_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  echo "Invalid Unix username: $CONFIG_USER" >&2
  exit 2
fi

if [[ ! -d "$TARGET_ROOT" ]]; then
  echo "Target root does not exist: $TARGET_ROOT" >&2
  exit 2
fi

# Normalize target root without requiring realpath inside stripped Debian environments.
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

install_packages() {
  [[ "$SKIP_PACKAGES" == "1" ]] && return 0
  if [[ "$TARGET_ROOT" != "/" ]]; then
    echo "Refusing to run apt-get against non-live target root '$TARGET_ROOT'. Use --skip-packages for staged roots." >&2
    exit 2
  fi
  need_root_for_live_changes
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends sudo vim ncurses-bin passwd
}

ensure_group() {
  local group_file
  group_file="$(in_target /etc/group)"
  if [[ "$TARGET_ROOT" == "/" ]]; then
    getent group sudo >/dev/null || groupadd --system sudo
  else
    mkdir -p "$(dirname "$group_file")"
    touch "$group_file"
    grep -qE '^sudo:' "$group_file" || printf 'sudo:x:27:\n' >> "$group_file"
  fi
}

ensure_user() {
  if [[ "$TARGET_ROOT" == "/" ]]; then
    if ! id "$CONFIG_USER" >/dev/null 2>&1; then
      if [[ "$CREATE_USER" != "1" ]]; then
        echo "User '$CONFIG_USER' does not exist; rerun without --no-create-user or create it first." >&2
        exit 1
      fi
      useradd --create-home --shell /bin/bash "$CONFIG_USER"
    fi
    usermod -aG sudo "$CONFIG_USER"
    return 0
  fi

  local passwd_file shadow_file group_file home_dir
  passwd_file="$(in_target /etc/passwd)"
  shadow_file="$(in_target /etc/shadow)"
  group_file="$(in_target /etc/group)"
  home_dir="$(in_target /home/$CONFIG_USER)"
  mkdir -p "$(dirname "$passwd_file")" "$(dirname "$shadow_file")" "$home_dir"
  touch "$passwd_file" "$shadow_file" "$group_file"

  if ! grep -qE "^${CONFIG_USER}:" "$passwd_file"; then
    if [[ "$CREATE_USER" != "1" ]]; then
      echo "User '$CONFIG_USER' does not exist in target root." >&2
      exit 1
    fi
    local uid gid
    uid=1000
    while grep -qE "^[^:]*:[^:]*:${uid}:" "$passwd_file"; do uid=$((uid + 1)); done
    gid="$uid"
    printf '%s:x:%s:%s:%s:/home/%s:/bin/bash\n' "$CONFIG_USER" "$uid" "$gid" "$CONFIG_USER" "$CONFIG_USER" >> "$passwd_file"
    printf '%s:!:19000:0:99999:7:::\n' "$CONFIG_USER" >> "$shadow_file"
    grep -qE "^${CONFIG_USER}:" "$group_file" || printf '%s:x:%s:\n' "$CONFIG_USER" "$gid" >> "$group_file"
  fi

  local tmp_group
  tmp_group="${group_file}.tmp.$$"
  local seen_sudo=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == sudo:* ]]; then
      seen_sudo=1
      IFS=':' read -r name password gid members extra <<< "$line"
      if [[ ",$members," != *",$CONFIG_USER,"* ]]; then
        if [[ -n "$members" ]]; then
          members="$members,$CONFIG_USER"
        else
          members="$CONFIG_USER"
        fi
      fi
      printf '%s:%s:%s:%s\n' "$name" "$password" "$gid" "$members" >> "$tmp_group"
    else
      printf '%s\n' "$line" >> "$tmp_group"
    fi
  done < "$group_file"
  if [[ "$seen_sudo" == "0" ]]; then
    printf 'sudo:x:27:%s\n' "$CONFIG_USER" >> "$tmp_group"
  fi
  mv "$tmp_group" "$group_file"
}

configure_visudo_editor() {
  local sudoers_dir sudoers_file
  sudoers_dir="$(in_target /etc/sudoers.d)"
  sudoers_file="$sudoers_dir/00-editor-vim"
  mkdir -p "$sudoers_dir"
  [[ -f "$sudoers_file" ]] && chmod u+w "$sudoers_file"
  printf 'Defaults editor=/usr/bin/vim\n' > "$sudoers_file"
  chmod 0440 "$sudoers_file"

  if [[ "$TARGET_ROOT" == "/" ]] && command -v visudo >/dev/null 2>&1; then
    visudo -cf "$sudoers_file" >/dev/null
  fi
}

configure_global_sbin_path() {
  local profile_file environment_file
  profile_file="$(in_target /etc/profile.d/00-sbin-path.sh)"
  environment_file="$(in_target /etc/environment)"
  mkdir -p "$(dirname "$profile_file")" "$(dirname "$environment_file")"

  cat > "$profile_file" <<'PROFILE'
# Ensure administrative sbin paths are available to all interactive shell users.
case ":$PATH:" in
  *:/usr/sbin:*) ;;
  *) PATH="/usr/sbin:$PATH" ;;
esac
case ":$PATH:" in
  *:/sbin:*) ;;
  *) PATH="/sbin:$PATH" ;;
esac
export PATH
PROFILE
  chmod 0644 "$profile_file"

  if [[ ! -f "$environment_file" ]] || ! grep -q '^PATH=' "$environment_file"; then
    printf 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' > "$environment_file"
  else
    local tmp_environment
    tmp_environment="${environment_file}.tmp.$$"
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == PATH=* ]]; then
        local raw_path
        raw_path="${line#PATH=}"
        raw_path="${raw_path%\"}"
        raw_path="${raw_path#\"}"
        case ":$raw_path:" in *:/usr/local/sbin:*) ;; *) raw_path="/usr/local/sbin:$raw_path" ;; esac
        case ":$raw_path:" in *:/usr/sbin:*) ;; *) raw_path="$raw_path:/usr/sbin" ;; esac
        case ":$raw_path:" in *:/sbin:*) ;; *) raw_path="$raw_path:/sbin" ;; esac
        printf 'PATH="%s"\n' "$raw_path" >> "$tmp_environment"
      else
        printf '%s\n' "$line" >> "$tmp_environment"
      fi
    done < "$environment_file"
    mv "$tmp_environment" "$environment_file"
  fi
}

install_ghostty_terminfo() {
  if [[ ! -f "$TERMINFO_SOURCE" ]]; then
    echo "Missing Ghostty terminfo source: $TERMINFO_SOURCE" >&2
    exit 1
  fi

  if [[ "$TARGET_ROOT" == "/" ]]; then
    need_root_for_live_changes
    command -v tic >/dev/null 2>&1 || { echo "tic is required; install ncurses-bin." >&2; exit 1; }
    tic -x -o /usr/share/terminfo "$TERMINFO_SOURCE"
    return 0
  fi

  # Staged-root fallback: preserve the canonical terminfo source where the live
  # script can compile it later. Compiled terminfo is architecture-sensitive enough
  # that pretending otherwise is how tiny gremlins get tenure.
  local dest_dir
  dest_dir="$(in_target /usr/local/share/terminfo-src)"
  mkdir -p "$dest_dir"
  cp "$TERMINFO_SOURCE" "$dest_dir/xterm-ghostty.terminfo"
  chmod 0644 "$dest_dir/xterm-ghostty.terminfo"
}

main() {
  install_packages
  ensure_group
  ensure_user
  configure_visudo_editor
  configure_global_sbin_path
  install_ghostty_terminfo
  echo "Debian system bootstrap complete for user '$CONFIG_USER'."
}

main "$@"
