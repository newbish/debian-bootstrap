#!/usr/bin/env bash
set -euo pipefail
repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$repo_root/bin/bootstrap-debian.sh"
bash -n "$repo_root/bin/install.sh"
bash -n "$repo_root/bin/enable-passwordless-sudo.sh"
bash -n "$repo_root/bin/add-disk.sh"
tic -x -c "$repo_root/terminfo/xterm-ghostty.terminfo" >/dev/null
grep -q 'Ghostty terminfo already installed; skipping.' "$repo_root/bin/bootstrap-debian.sh"
grep -q 'infocmp -x xterm-ghostty' "$repo_root/bin/bootstrap-debian.sh"

root="$(mktemp -d)"
custom_root=""
config_root=""
password_root=""
installer_root=""
custom_config=""
stub_dir=""
installer_archive=""
path_root=""
nopasswd_root=""
disk_root=""
disk_stub_dir=""
trap 'rm -rf "$root" ${custom_root:+"$custom_root"} ${config_root:+"$config_root"} ${password_root:+"$password_root"} ${installer_root:+"$installer_root"} ${custom_config:+"$custom_config"} ${stub_dir:+"$stub_dir"} ${installer_archive:+"$installer_archive"} ${path_root:+"$path_root"} ${nopasswd_root:+"$nopasswd_root"} ${disk_root:+"$disk_root"} ${disk_stub_dir:+"$disk_stub_dir"}' EXIT
mkdir -p "$root/etc" "$root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$root/etc/shadow"
printf 'root:x:0:\n' > "$root/etc/group"

"$repo_root/bin/bootstrap-debian.sh" --target-root "$root" --skip-packages
"$repo_root/bin/bootstrap-debian.sh" --target-root "$root" --skip-packages

grep -q '^debian:' "$root/etc/passwd"
grep -q '^sudo:.*debian' "$root/etc/group"
test "$(grep '^sudo:' "$root/etc/group" | grep -o 'debian' | wc -l)" -eq 1
grep -q '^Defaults editor=/usr/bin/vim$' "$root/etc/sudoers.d/00-editor-vim"
grep -q '/usr/sbin' "$root/etc/profile.d/00-sbin-path.sh"
grep -q '/sbin' "$root/etc/environment"
test -f "$root/usr/local/share/terminfo-src/xterm-ghostty.terminfo"

custom_root="$(mktemp -d)"
mkdir -p "$custom_root/etc" "$custom_root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$custom_root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$custom_root/etc/shadow"
printf 'root:x:0:\n' > "$custom_root/etc/group"

"$repo_root/bin/bootstrap-debian.sh" --target-root "$custom_root" --skip-packages --user alice
CONFIG_USER=bob "$repo_root/bin/bootstrap-debian.sh" --target-root "$custom_root" --skip-packages

grep -q '^alice:' "$custom_root/etc/passwd"
grep -q '^bob:' "$custom_root/etc/passwd"
grep -q '^sudo:.*alice' "$custom_root/etc/group"
grep -q '^sudo:.*bob' "$custom_root/etc/group"

config_root="$(mktemp -d)"
custom_config="$(mktemp)"
mkdir -p "$config_root/etc" "$config_root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$config_root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$config_root/etc/shadow"
printf 'root:x:0:\n' > "$config_root/etc/group"
printf 'CONFIG_USER=carol\n' > "$custom_config"

"$repo_root/bin/bootstrap-debian.sh" --config "$custom_config" --target-root "$config_root" --skip-packages
"$repo_root/bin/bootstrap-debian.sh" --config "$custom_config" --target-root "$config_root" --skip-packages --user dave

grep -q '^carol:' "$config_root/etc/passwd"
grep -q '^dave:' "$config_root/etc/passwd"
grep -q '^sudo:.*carol' "$config_root/etc/group"
grep -q '^sudo:.*dave' "$config_root/etc/group"

password_root="$(mktemp -d)"
stub_dir="$(mktemp -d)"
mkdir -p "$password_root/etc" "$password_root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$password_root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$password_root/etc/shadow"
printf 'root:x:0:\n' > "$password_root/etc/group"
cat > "$stub_dir/passwd" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${PASSWD_STUB_LOG:?}"
STUB
chmod +x "$stub_dir/passwd"

set +e
PASSWD_STUB_LOG="$password_root/passwd.log" PATH="$stub_dir:$PATH" "$repo_root/bin/bootstrap-debian.sh" --target-root "$password_root" --skip-packages --set-password --user erin
password_status=$?
set -e
test "$password_status" -eq 0
grep -q '^erin$' "$password_root/passwd.log"

set +e
"$repo_root/bin/bootstrap-debian.sh" --target-root "$password_root" --skip-packages --set-password --no-create-user --user missing >"$password_root/missing.out" 2>"$password_root/missing.err"
missing_status=$?
set -e
test "$missing_status" -ne 0
grep -q "User 'missing' does not exist" "$password_root/missing.err"

installer_root="$(mktemp -d)"
installer_archive="$(mktemp --suffix=.tar.gz)"
mkdir -p "$installer_root/etc" "$installer_root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$installer_root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$installer_root/etc/shadow"
printf 'root:x:0:\n' > "$installer_root/etc/group"
tar --exclude=.git --exclude=.agents --exclude=skills-lock.json -czf "$installer_archive" -C "$repo_root" .

REPO_ARCHIVE_URL="file://$installer_archive" "$repo_root/bin/install.sh" --target-root "$installer_root" --skip-packages --user frank

grep -q '^frank:' "$installer_root/etc/passwd"
grep -q '^sudo:.*frank' "$installer_root/etc/group"
test -f "$installer_root/usr/local/share/terminfo-src/xterm-ghostty.terminfo"

rm -rf "$installer_root"
installer_root="$(mktemp -d)"
rm -f "$installer_archive"
installer_archive="$(mktemp --suffix=.tar.gz)"
mkdir -p "$installer_root/etc" "$installer_root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$installer_root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$installer_root/etc/shadow"
printf 'root:x:0:\n' > "$installer_root/etc/group"
github_archive_root="$(mktemp -d)"
mkdir -p "$github_archive_root/debian-bootstrap-main"
tar --exclude=.git --exclude=.agents --exclude=skills-lock.json -C "$repo_root" -cf - . | tar -C "$github_archive_root/debian-bootstrap-main" -xf -
tar -czf "$installer_archive" -C "$github_archive_root" debian-bootstrap-main
rm -rf "$github_archive_root"

REPO_ARCHIVE_URL="file://$installer_archive" "$repo_root/bin/install.sh" --target-root "$installer_root" --skip-packages --user grace

grep -q '^grace:' "$installer_root/etc/passwd"
grep -q '^sudo:.*grace' "$installer_root/etc/group"

grep -q '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "$repo_root/bin/bootstrap-debian.sh"
path_root="$(mktemp -d)"
mkdir -p "$path_root/etc" "$path_root/home"
printf 'root:x:0:0:root:/root:/bin/bash\n' > "$path_root/etc/passwd"
printf 'root:*:19000:0:99999:7:::\n' > "$path_root/etc/shadow"
printf 'root:x:0:\n' > "$path_root/etc/group"
PATH="/usr/bin:/bin" "$repo_root/bin/bootstrap-debian.sh" --target-root "$path_root" --skip-packages --user heidi
grep -q '^heidi:' "$path_root/etc/passwd"
grep -q '^sudo:.*heidi' "$path_root/etc/group"

nopasswd_root="$(mktemp -d)"
mkdir -p "$nopasswd_root/etc/sudoers.d" "$nopasswd_root/etc"
printf 'ivan:x:1000:1000:ivan:/home/ivan:/bin/bash\n' > "$nopasswd_root/etc/passwd"
printf 'root:x:0:\nsudo:x:27:\n' > "$nopasswd_root/etc/group"

"$repo_root/bin/enable-passwordless-sudo.sh" --target-root "$nopasswd_root" --user ivan
"$repo_root/bin/enable-passwordless-sudo.sh" --target-root "$nopasswd_root" --user ivan

grep -q '^ivan ALL=(ALL:ALL) NOPASSWD:ALL$' "$nopasswd_root/etc/sudoers.d/90-ivan-nopasswd"
test "$(grep -c '^ivan ALL=(ALL:ALL) NOPASSWD:ALL$' "$nopasswd_root/etc/sudoers.d/90-ivan-nopasswd")" -eq 1
test "$(stat -c '%a' "$nopasswd_root/etc/sudoers.d/90-ivan-nopasswd")" = "440"

set +e
"$repo_root/bin/enable-passwordless-sudo.sh" --target-root "$nopasswd_root" --user missing >"$nopasswd_root/nopasswd-missing.out" 2>"$nopasswd_root/nopasswd-missing.err"
nopasswd_missing_status=$?
set -e
test "$nopasswd_missing_status" -ne 0
grep -q "User 'missing' does not exist" "$nopasswd_root/nopasswd-missing.err"

disk_root="$(mktemp -d)"
disk_stub_dir="$(mktemp -d)"
mkdir -p "$disk_root/etc" "$disk_stub_dir" "$disk_root/dev"
: > "$disk_root/etc/fstab"
: > "$disk_root/dev/sdb"
cat > "$disk_stub_dir/lsblk" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"-no TYPE /tmp"*) printf 'disk\n' ;;
  *"-no FSTYPE /tmp"*) printf '\n' ;;
  *"-no MOUNTPOINT /tmp"*) printf '\n' ;;
  *) printf 'unexpected lsblk args: %s\n' "$*" >&2; exit 9 ;;
esac
STUB
cat > "$disk_stub_dir/blkid" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"-s UUID -o value /tmp"*sdb1) printf '1111-2222\n' ;;
  *"-s UUID -o value /tmp"*sda1) printf '3333-4444\n' ;;
  *"-s UUID -o value /tmp"*) printf '\n' ;;
  *) printf 'unexpected blkid args: %s\n' "$*" >&2; exit 9 ;;
esac
STUB
cat > "$disk_stub_dir/sfdisk" <<'STUB'
#!/usr/bin/env bash
printf 'sfdisk %s\n' "$*" >> "${DISK_STUB_LOG:?}"
cat >/dev/null
: > "${1}1"
STUB
cat > "$disk_stub_dir/partprobe" <<'STUB'
#!/usr/bin/env bash
printf 'partprobe %s\n' "$*" >> "${DISK_STUB_LOG:?}"
STUB
cat > "$disk_stub_dir/udevadm" <<'STUB'
#!/usr/bin/env bash
printf 'udevadm %s\n' "$*" >> "${DISK_STUB_LOG:?}"
STUB
cat > "$disk_stub_dir/mkfs.ext4" <<'STUB'
#!/usr/bin/env bash
printf 'mkfs.ext4 %s\n' "$*" >> "${DISK_STUB_LOG:?}"
STUB
cat > "$disk_stub_dir/mount" <<'STUB'
#!/usr/bin/env bash
printf 'mount %s\n' "$*" >> "${DISK_STUB_LOG:?}"
STUB
chmod +x "$disk_stub_dir/lsblk" "$disk_stub_dir/blkid" "$disk_stub_dir/sfdisk" "$disk_stub_dir/partprobe" "$disk_stub_dir/udevadm" "$disk_stub_dir/mkfs.ext4" "$disk_stub_dir/mount"

DISK_STUB_LOG="$disk_root/disk.log" PATH="$disk_stub_dir:$PATH" "$repo_root/bin/add-disk.sh" --target-root "$disk_root"
grep -q '^UUID=1111-2222 /home/agent ext4 defaults,nofail 0 2$' "$disk_root/etc/fstab"
test -e "$disk_root/dev/sdb1"
test -d "$disk_root/home/agent"
grep -q '^sfdisk /tmp/.*/dev/sdb$' "$disk_root/disk.log"
grep -q -- 'mkfs.ext4 -F /tmp/.*/dev/sdb1' "$disk_root/disk.log"
grep -q '^mount /tmp/.*/home/agent$' "$disk_root/disk.log"

set +e
DISK_STUB_LOG="$disk_root/disk.log" PATH="$disk_stub_dir:$PATH" "$repo_root/bin/add-disk.sh" --target-root "$disk_root" >"$disk_root/disk-existing.out" 2>"$disk_root/disk-existing.err"
disk_existing_status=$?
set -e
test "$disk_existing_status" -eq 0
grep -q 'already has an fstab entry' "$disk_root/disk-existing.out"
test "$(grep -c '^UUID=1111-2222 /home/agent ext4 defaults,nofail 0 2$' "$disk_root/etc/fstab")" -eq 1

: > "$disk_root/dev/sda"
DISK_STUB_LOG="$disk_root/disk.log" PATH="$disk_stub_dir:$PATH" "$repo_root/bin/add-disk.sh" --target-root "$disk_root" --device /dev/sda --mount-point /srv/data
grep -q '^UUID=3333-4444 /srv/data ext4 defaults,nofail 0 2$' "$disk_root/etc/fstab"
test -e "$disk_root/dev/sda1"
grep -q '^sfdisk /tmp/.*/dev/sda$' "$disk_root/disk.log"

mounted_root="$(mktemp -d)"
mkdir -p "$mounted_root/etc" "$mounted_root/dev"
: > "$mounted_root/etc/fstab"
: > "$mounted_root/dev/sdb"
cat > "$mounted_root/mounts" <<MOUNTS
/dev/sdb1 /old ext4 rw 0 0
MOUNTS
set +e
DISK_STUB_LOG="$mounted_root/disk.log" MOUNTS_FILE="$mounted_root/mounts" PATH="$disk_stub_dir:$PATH" "$repo_root/bin/add-disk.sh" --target-root "$mounted_root" >"$mounted_root/disk-mounted.out" 2>"$mounted_root/disk-mounted.err"
disk_mounted_status=$?
set -e
test "$disk_mounted_status" -ne 0
grep -q 'already appears to be mounted' "$mounted_root/disk-mounted.err"
test ! -e "$mounted_root/dev/sdb1"

DISK_STUB_LOG="$mounted_root/disk.log" MOUNTS_FILE="$mounted_root/mounts" PATH="$disk_stub_dir:$PATH" "$repo_root/bin/add-disk.sh" --target-root "$mounted_root" --force --mount-point /srv/forced
grep -q '^UUID=1111-2222 /srv/forced ext4 defaults,nofail 0 2$' "$mounted_root/etc/fstab"

echo "static and staged-root tests passed"
