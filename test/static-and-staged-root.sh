#!/usr/bin/env bash
set -euo pipefail
repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$repo_root/bin/bootstrap-debian.sh"
bash -n "$repo_root/bin/install.sh"
tic -x -c "$repo_root/terminfo/xterm-ghostty.terminfo" >/dev/null

root="$(mktemp -d)"
custom_root=""
config_root=""
password_root=""
installer_root=""
custom_config=""
stub_dir=""
installer_archive=""
trap 'rm -rf "$root" ${custom_root:+"$custom_root"} ${config_root:+"$config_root"} ${password_root:+"$password_root"} ${installer_root:+"$installer_root"} ${custom_config:+"$custom_config"} ${stub_dir:+"$stub_dir"} ${installer_archive:+"$installer_archive"}' EXIT
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

echo "static and staged-root tests passed"
