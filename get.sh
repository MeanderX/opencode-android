#!/data/data/com.termux/files/usr/bin/bash
# get.sh — fetch or update the project, then run the installer.
# Usage (inside Termux):
#   pkg install -y curl && curl -fsSL https://raw.githubusercontent.com/MeanderX/opencode-android/main/get.sh | bash
set -euo pipefail

command -v pkg >/dev/null 2>&1 || {
    echo "This installer must run inside Termux." >&2
    exit 1
}

DIR="${OPENCODE_DIR:-$HOME/opencode-android}"
REPO="https://github.com/MeanderX/opencode-android"

command -v git >/dev/null 2>&1 || pkg install -y git

if [ -d "$DIR/.git" ]; then
    echo "[oc-install] Updating $DIR"
    git -C "$DIR" pull --ff-only || true
else
    echo "[oc-install] Downloading $REPO"
    git clone --depth 1 "$REPO" "$DIR"
fi

exec bash "$DIR/install.sh" "$@"
