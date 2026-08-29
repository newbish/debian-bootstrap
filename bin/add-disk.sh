#!/usr/bin/env bash
set -euo pipefail

# Minimal Debian/root shells may omit administrative paths. Commands like
# sfdisk, mkfs, lsblk, blkid, and mount may live outside a stripped PATH.
export PATH="${PATH:+$PATH:}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

usage() {
  cat <<'USAGE'
Usage: add-disk.sh [options]

Partition an available disk, create a filesystem, and mount it persistently.
Defaults are intentionally agent-friendly for disposable/admin VMs:
  device:      /dev/sdb
  mount point: /home/agent
  filesystem:  ext4

Options:
  --device DEVICE          disk device to prepare (default: /dev/sdb)
  --mount-point DIR        mount point inside the target system (default: /home/agent)
  --filesystem TYPE        filesystem to create on the first partition (default: ext4)
  --fstab-options OPTIONS  fstab options (default: defaults,nofail)
  --target-root DIR        root filesystem to modify (default: /)
  --force                  allow partitioning even if DEVICE/partition appears mounted
  --no-format              fail instead of formatting when the partition has no filesystem
  --no-mount               update fstab but do not mount now
  -h, --help               show this help

Safety behavior:
  - allows /dev/sda when requested; do not assume the OS is always installed there
  - warns before rewriting the disk partition table
  - refuses to partition an already-mounted device unless --force is supplied
  - exits successfully without changes if DEVICE, partition, UUID, or MOUNT_POINT is already in fstab
  - writes fstab using UUID=... instead of the raw device path
USAGE
}

DEVICE="${DISK_DEVICE:-/dev/sdb}"
MOUNT_POINT="${DISK_MOUNT_POINT:-/home/agent}"
FILESYSTEM="${DISK_FILESYSTEM:-ext4}"
FSTAB_OPTIONS="${DISK_FSTAB_OPTIONS:-defaults,nofail}"
TARGET_ROOT="${TARGET_ROOT:-/}"
FORMAT_IF_EMPTY="${FORMAT_IF_EMPTY:-1}"
MOUNT_NOW="${MOUNT_NOW:-1}"
FORCE="${FORCE:-0}"
MOUNTS_FILE="${MOUNTS_FILE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="${2:?--device requires a value}"; shift 2 ;;
    --mount-point) MOUNT_POINT="${2:?--mount-point requires a value}"; shift 2 ;;
    --filesystem) FILESYSTEM="${2:?--filesystem requires a value}"; shift 2 ;;
    --fstab-options) FSTAB_OPTIONS="${2:?--fstab-options requires a value}"; shift 2 ;;
    --target-root) TARGET_ROOT="${2:?--target-root requires a value}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --no-format) FORMAT_IF_EMPTY=0; shift ;;
    --no-mount) MOUNT_NOW=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$DEVICE" =~ ^/dev/[A-Za-z0-9._/-]+$ ]]; then
  echo "Invalid device path: $DEVICE" >&2
  exit 2
fi

if [[ ! "$MOUNT_POINT" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
  echo "Invalid mount point: $MOUNT_POINT" >&2
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

map_device_for_target() {
  local dev="$1"
  if [[ "$TARGET_ROOT" == "/" ]]; then
    printf '%s' "$dev"
  else
    printf '%s' "$(in_target "$dev")"
  fi
}

partition_name() {
  local dev="$1"
  case "$dev" in
    *[0-9]) printf '%sp1' "$dev" ;;
    *) printf '%s1' "$dev" ;;
  esac
}

need_root_for_live_changes() {
  if [[ "$TARGET_ROOT" == "/" && "$(id -u)" -ne 0 ]]; then
    echo "This script must run as root when modifying a live Debian system." >&2
    exit 1
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 1; }
}

fstab_has_value() {
  local value="$1" fstab_file="$2"
  [[ -f "$fstab_file" ]] || return 1
  awk -v value="$value" '
    /^[[:space:]]*#/ || NF == 0 { next }
    $1 == value || $2 == value { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$fstab_file"
}

mounts_have_device() {
  local dev="$1" mounts_file="$2"
  [[ -f "$mounts_file" ]] || return 1
  awk -v dev="$dev" '
    $1 == dev || index($1, dev) == 1 { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$mounts_file"
}

lsblk_has_mountpoint() {
  local dev="$1"
  lsblk -nr -o MOUNTPOINT "$dev" 2>/dev/null | awk 'NF { found = 1 } END { exit found ? 0 : 1 }'
}

refresh_partition_table() {
  local dev="$1"
  if command -v partprobe >/dev/null 2>&1; then
    partprobe "$dev" || true
  fi
  if command -v udevadm >/dev/null 2>&1; then
    udevadm settle || true
  fi
}

create_single_partition() {
  local dev="$1"
  echo "WARNING: rewriting partition table on $DEVICE; existing partition data on that disk can be destroyed." >&2
  printf ',,L,*\n' | sfdisk "$dev" >/dev/null
  refresh_partition_table "$dev"
}

format_partition_if_needed() {
  local part="$1" fs_type
  fs_type="$(lsblk -no FSTYPE "$part" | head -n 1 || true)"
  if [[ -n "$fs_type" ]]; then
    printf '%s' "$fs_type"
    return 0
  fi

  if [[ "$FORMAT_IF_EMPTY" != "1" ]]; then
    echo "$DEVICE partition has no filesystem and --no-format was requested." >&2
    exit 1
  fi

  case "$FILESYSTEM" in
    ext4)
      require_command mkfs.ext4
      mkfs.ext4 -F "$part"
      ;;
    *)
      require_command "mkfs.$FILESYSTEM"
      "mkfs.$FILESYSTEM" "$part"
      ;;
  esac
  printf '%s' "$FILESYSTEM"
}

main() {
  need_root_for_live_changes
  require_command lsblk
  require_command blkid
  require_command sfdisk
  [[ "$MOUNT_NOW" == "1" ]] && require_command mount

  local device_path partition partition_path fstab_file mount_dir mounts_file fs_type uuid source_spec
  device_path="$(map_device_for_target "$DEVICE")"
  partition="$(partition_name "$DEVICE")"
  partition_path="$(map_device_for_target "$partition")"
  fstab_file="$(in_target /etc/fstab)"
  mount_dir="$(in_target "$MOUNT_POINT")"
  mounts_file="${MOUNTS_FILE:-$(in_target /proc/mounts)}"

  if [[ ! -e "$device_path" ]]; then
    echo "Device does not exist: $DEVICE" >&2
    [[ "$TARGET_ROOT" != "/" ]] && echo "Checked staged path: $device_path" >&2
    exit 1
  fi

  if [[ "$(lsblk -no TYPE "$device_path" | head -n 1)" != "disk" ]]; then
    echo "Refusing to operate on non-disk device: $DEVICE" >&2
    exit 2
  fi

  mkdir -p "$(dirname "$fstab_file")"
  touch "$fstab_file"

  if fstab_has_value "$DEVICE" "$fstab_file" || fstab_has_value "$partition" "$fstab_file" || fstab_has_value "$MOUNT_POINT" "$fstab_file"; then
    echo "$DEVICE, $partition, or $MOUNT_POINT already has an fstab entry; leaving it unchanged."
    exit 0
  fi

  if [[ -e "$partition_path" ]]; then
    uuid="$(blkid -s UUID -o value "$partition_path" 2>/dev/null || true)"
    if [[ -n "$uuid" ]] && fstab_has_value "UUID=$uuid" "$fstab_file"; then
      echo "$partition UUID already has an fstab entry; leaving it unchanged."
      exit 0
    fi
  fi

  if { mounts_have_device "$DEVICE" "$mounts_file" || mounts_have_device "$partition" "$mounts_file" || lsblk_has_mountpoint "$device_path"; } && [[ "$FORCE" != "1" ]]; then
    echo "$DEVICE or one of its partitions already appears to be mounted; refusing to rewrite its partition table without --force." >&2
    exit 2
  fi

  create_single_partition "$device_path"

  if [[ ! -e "$partition_path" ]]; then
    echo "Expected partition was not created: $partition" >&2
    [[ "$TARGET_ROOT" != "/" ]] && echo "Checked staged path: $partition_path" >&2
    exit 1
  fi

  fs_type="$(format_partition_if_needed "$partition_path")"
  uuid="$(blkid -s UUID -o value "$partition_path")"
  if [[ -z "$uuid" ]]; then
    echo "Could not determine UUID for $partition after filesystem check." >&2
    exit 1
  fi

  mkdir -p "$mount_dir"
  source_spec="UUID=$uuid"
  printf '%s %s %s %s 0 2\n' "$source_spec" "$MOUNT_POINT" "$fs_type" "$FSTAB_OPTIONS" >> "$fstab_file"

  if [[ "$MOUNT_NOW" == "1" ]]; then
    if [[ "$TARGET_ROOT" == "/" ]]; then
      mount "$MOUNT_POINT"
    else
      mount "$mount_dir"
    fi
  fi

  echo "Partitioned $DEVICE, mounted $partition at $MOUNT_POINT, and added it to fstab."
}

main "$@"
