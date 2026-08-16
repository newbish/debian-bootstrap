# Debian Bootstrap

Personal baseline scripts for configuring Debian systems the way Keith likes them.

## What it configures

- Installs `sudo`, `vim`, `ncurses-bin`, and `passwd`.
- Ensures the configured user exists and belongs to the `sudo` group.
- Defaults to user `debian` from `config/default.conf`.
- The user remains overrideable with `--user USER` or `CONFIG_USER=USER`.
- Configures `visudo` to use `/usr/bin/vim`.
- Adds `/sbin` and `/usr/sbin` to default paths for all users via:
  - `/etc/profile.d/00-sbin-path.sh`
  - `/etc/environment`
- Installs Ghostty terminfo globally as `xterm-ghostty` / `ghostty`.

## Quick start on a Debian system

This repository is public, so it can be cloned directly onto the target system.

Fast path from a fresh Debian system:

```bash
apt-get update
apt-get install -y curl ca-certificates
curl -fsSL https://raw.githubusercontent.com/newbish/debian-bootstrap/main/bin/install.sh | bash
```

Pass normal bootstrap options after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/newbish/debian-bootstrap/main/bin/install.sh | bash -s -- --user alice --set-password
```

The installer downloads the full repository archive, so bundled files like Ghostty terminfo are available without installing `git`.

Clone path:

```bash
apt-get update
apt-get install -y git ca-certificates
cd /tmp
git clone https://github.com/newbish/debian-bootstrap.git
cd debian-bootstrap
./bin/bootstrap-debian.sh
```

If you are copying from the host instead:

```bash
cd /tmp/debian-bootstrap
./bin/bootstrap-debian.sh
```

## Options

```text
--config FILE        config file to load; default: config/default.conf
--user USER          user to configure; default: debian
--target-root DIR    root filesystem to modify; default: /
--skip-packages      skip apt-get package installation
--no-create-user     fail if USER does not exist instead of creating it
--set-password       run passwd for USER after account setup
```

Configuration precedence:

```text
built-in defaults < config file < environment < command line
```

The default config file is intentionally small:

```bash
CONFIG_USER=debian
```

For personal defaults, copy the example local config and edit it:

```bash
cp config/local.conf.example config/local.conf
$EDITOR config/local.conf
```

`config/local.conf` is ignored by git.

Examples:

```bash
# Configure a different user
./bin/bootstrap-debian.sh --user alice

# Same override via environment variable
CONFIG_USER=alice ./bin/bootstrap-debian.sh

# Use a different config file, still allowing command-line override
./bin/bootstrap-debian.sh --config ./my-bootstrap.conf --user alice

# Create/configure the user, then interactively set its password
./bin/bootstrap-debian.sh --user alice --set-password

# Validate file-writing behavior against a staged root without running apt
./bin/bootstrap-debian.sh --target-root /tmp/debian-root --skip-packages
```

## Notes

- Run as `root` inside the target Debian system for live configuration.
- Newly created users have locked passwords by default. Use `--set-password` or run
  `passwd USER` afterward when password login is desired.
- The script is idempotent: rerunning it should not duplicate sudo group membership or PATH entries.
- For non-live staged roots, the script writes the Ghostty terminfo source to
  `/usr/local/share/terminfo-src/xterm-ghostty.terminfo`; run the script live in
  the target system to compile it into `/usr/share/terminfo` with `tic`.
