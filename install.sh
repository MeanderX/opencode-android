#!/data/data/com.termux/files/usr/bin/bash
# install.sh — one-time setup for OpenCode on Android (Termux + proot-distro)
#
# What it does:
#   1. Updates Termux and installs proot-distro
#   2. Creates a Debian Linux environment inside Termux
#   3. Installs Node.js 22 + OpenCode inside that environment
#   4. Installs the `oc` launcher and an optional home-screen widget shortcut
#
# Safe to re-run: it skips what is already installed and updates OpenCode.
#
# Why the Linux environment? OpenCode's installers and npm check
# process.platform, which reports "android" inside plain Termux and breaks
# installation. Inside a proot-distro Debian environment it reports "linux",
# so OpenCode installs and runs normally.

set -euo pipefail

DISTRO="${OPENCODE_DISTRO:-debian}"
PROJECTS_DIR="$HOME/projects"
CONFIG_DIR="$HOME/.config/oc"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

log()  { printf '\033[1;36m[oc-install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[oc-install]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[oc-install] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v pkg >/dev/null 2>&1 \
    || die "This script must be run inside Termux."

# --- 1. Termux packages ------------------------------------------------------

log "Updating Termux packages (this can take a while)..."
pkg update -y || warn "pkg update had problems — trying to continue."
pkg upgrade -y || warn "pkg upgrade reported problems — continuing anyway."
pkg install -y proot-distro

# Ask for shared storage access so /sdcard is visible inside the Linux
# environment. Approve the Android dialog if it appears. Safe to re-run.
log "Requesting shared storage access (approve the dialog if it appears)..."
termux-setup-storage || true

# --- 2. Linux environment ----------------------------------------------------

if proot-distro list --quiet 2>/dev/null | grep -qx "$DISTRO"; then
    log "Linux environment '$DISTRO' already installed — skipping."
else
    log "Installing Debian inside Termux (downloads a few hundred MB)..."
    proot-distro install "$DISTRO"
fi

# --- 3. Node.js + OpenCode inside the environment ----------------------------

log "Installing Node.js and OpenCode inside the environment..."
# The npm shim is shipped as a repo file, but the work below happens inside
# the Linux environment. Pass it across as base64 on the environment rather
# than relying on the phone's directory layout being visible from inside.
if [ -f "$SCRIPT_DIR/npm-shim" ]; then
    NPM_SHIM_B64="$(base64 -w0 "$SCRIPT_DIR/npm-shim")"
else
    NPM_SHIM_B64=""
    warn "npm-shim not found next to install.sh — /update may report 'installation method not found'."
fi
proot-distro login "$DISTRO" --shared-tmp -e "NPM_SHIM_B64=$NPM_SHIM_B64" -- /bin/bash -s <<'GUEST'
set -euo pipefail

log() { printf '\033[1;36m[oc-install]\033[0m %s\n' "$*"; }

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends curl git xz-utils ca-certificates

# Node.js 22 from the official tarball — it bundles npm, and distro packages
# are often older than what OpenCode requires (Node 20+).
case "$(uname -m)" in
    aarch64|arm64) NARCH=arm64 ;;
    x86_64)        NARCH=x64  ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

log "Installing Node.js 22 (${NARCH})..."
ASSET="$(curl -fsSL "https://nodejs.org/dist/latest-v22.x/" \
    | grep -o "node-v[0-9.]*-linux-${NARCH}.tar.xz" | head -n1 || true)"
if [ -z "$ASSET" ]; then
    echo "Could not find a Node.js 22 tarball for ${NARCH}." >&2
    exit 1
fi
curl -fsSL "https://nodejs.org/dist/latest-v22.x/$ASSET" -o /var/tmp/node.tar.xz
mkdir -p /usr/local/lib/nodejs
tar -xJf /var/tmp/node.tar.xz -C /usr/local/lib/nodejs
BIN_DIR="/usr/local/lib/nodejs/${ASSET%.tar.xz}/bin"
ln -sf "$BIN_DIR/node" /usr/local/bin/node
ln -sf "$BIN_DIR/npx"  /usr/local/bin/npx
rm -f /var/tmp/node.tar.xz

# Install the npm shim *instead of* symlinking npm directly.
# OpenCode detects its install method by running `npm list -g` under a hard
# 10 second deadline, which the real npm cannot meet under proot. The shim
# answers that one query from disk and forwards everything else to the npm
# installed by the tarball above.
if [ -n "${NPM_SHIM_B64:-}" ]; then
    log "Installing the npm shim..."
    rm -f /usr/local/bin/npm
    printf '%s' "$NPM_SHIM_B64" | base64 -d > /usr/local/bin/npm
    chmod 755 /usr/local/bin/npm
    ln -sf "$BIN_DIR/npm" /usr/local/bin/npm.real
else
    ln -sf "$BIN_DIR/npm" /usr/local/bin/npm
fi

log "Installing OpenCode..."
npm config set prefix /usr/local
# OpenCode V2 here is the @opencode-ai/cli beta package, launched as
# `opencode2`. Drop the old v1 package and @opencode/cli (whose postinstall
# does not run under proot and leaves only a "postinstall was not run" stub)
# so nothing else claims the `opencode` name.
npm uninstall -g opencode-ai @opencode/cli >/dev/null 2>&1 || true
npm install -g @opencode-ai/cli

# Put execution back on the real path.
#
# OpenCode's postinstall hard-links the platform binary into place, leaving
# st_nlink = 2. proot runs any multi-linked file from a synthetic /.l2s/...
# path (its --link2symlink option) and replaces the real path with a symlink
# to it. process.execPath then stops pointing at the npm package, OpenCode
# cannot find the package.json above itself, decides it has no install
# method, and `/update` fails with "installation method not found". Copying
# the content into a plain file undoes that.
log "Fixing the binary's hard link for proot..."
for ocbin in /usr/local/lib/node_modules/@opencode-ai/cli/bin/opencode2*; do
    [ -e "$ocbin" ] || [ -L "$ocbin" ] || continue
    # stat must follow the link (-L): without it a proot symlink reports 1
    # and would be skipped, which is exactly the case we need to repair.
    if [ ! -L "$ocbin" ] && [ -f "$ocbin" ]; then
        [ "$(stat -L -c %h "$ocbin" 2>/dev/null || echo 1)" = "1" ] && continue
    fi
    octmp="$ocbin.repair.$$"
    # Clear the path before moving into it: renaming over the proot symlink
    # fails with EPERM.
    if cp -L "$ocbin" "$octmp" 2>/dev/null; then
        rm -f "$ocbin"
        mv "$octmp" "$ocbin" 2>/dev/null || cp "$octmp" "$ocbin" 2>/dev/null
        chmod 755 "$ocbin" 2>/dev/null
        rm -f "$octmp"
    else
        rm -f "$octmp"
    fi
done

OPENCODE_VERSION="$(opencode2 --version)"

log "OpenCode $OPENCODE_VERSION is installed."
GUEST

# --- 4. Launcher + widget shortcut -------------------------------------------

if [ ! -f "$SCRIPT_DIR/oc" ]; then
    die "Launcher script 'oc' not found next to install.sh"
fi
log "Installing launcher..."
install -m 755 "$SCRIPT_DIR/oc" "$PREFIX/bin/oc"

# Record whether the Termux home directory is already visible inside the
# environment (newer proot-distro binds it by default). The launcher reads
# this so it never adds a duplicate bind.
mkdir -p "$CONFIG_DIR"
if proot-distro login "$DISTRO" --shared-tmp -- test -d "$HOME" >/dev/null 2>&1; then
    printf 'BIND_HOME=0\n' > "$CONFIG_DIR/config"
else
    printf 'BIND_HOME=1\n' > "$CONFIG_DIR/config"
fi

if [ -f "$SCRIPT_DIR/OpenCode.sh" ]; then
    mkdir -p "$HOME/.shortcuts"
    install -m 755 "$SCRIPT_DIR/OpenCode.sh" "$HOME/.shortcuts/OpenCode.sh"
    log "Widget shortcut installed at ~/.shortcuts/OpenCode.sh"
fi

# --- Done ---------------------------------------------------------------------

mkdir -p "$PROJECTS_DIR"

log "Setup complete."
printf '\n'
printf '  Start OpenCode:     oc\n'
printf '  Pick a project:     oc my-project      (in ~/projects)\n'
printf '  One-off prompt:     oc run "explain this repo"\n'
printf '  Linux shell only:   oc shell\n'
printf '\n'
printf '  On first launch, sign in to a provider inside OpenCode,\n'
printf '  or run: oc auth login\n'
printf '\n'
