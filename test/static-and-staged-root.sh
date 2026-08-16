#!/usr/bin/env bash
set -euo pipefail
repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$repo_root/bin/bootstrap-debian.sh"
tic -x -c "$repo_root/terminfo/xterm-ghostty.terminfo" >/dev/null

root="$(mktemp -d)"
custom_root=""
config_root=""
custom_config=""
trap 'rm -rf "$root" ${custom_root:+"$custom_root"} ${config_root:+"$config_root"} ${custom_config:+"$custom_config"}' EXIT
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

echo "static and staged-root tests passed"
