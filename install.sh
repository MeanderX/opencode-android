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
proot-distro login "$DISTRO" --shared-tmp -- /bin/bash -s <<'GUEST'
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
ln -sf "$BIN_DIR/npm"  /usr/local/bin/npm
ln -sf "$BIN_DIR/npx"  /usr/local/bin/npx
rm -f /var/tmp/node.tar.xz

log "Installing OpenCode..."
npm install -g opencode-ai

log "OpenCode $(opencode --version) is installed."
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
