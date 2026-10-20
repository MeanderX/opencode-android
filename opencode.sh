#!/data/data/com.termux/files/usr/bin/bash
# opencode.sh — update + start OpenCode (v2 FULL) inside the proot-distro guest.
#
# What was wrong with the previous version:
#   * `npm install -g opencode@2` — there is NO unscoped "opencode" package on
#     npm (HTTP 404). v2 FULL is "@opencode/cli" (dist-tag latest), v1 is
#     "opencode-ai". The old fallback chain therefore never installed v2.
#   * `ln -sf "$BIN" /usr/local/bin/opencode` when BIN already *was*
#     /usr/local/bin/opencode created a self-referential link
#     ("Too many symbolic links encountered") — i.e. the update destroyed the
#     very binary it was trying to publish.
#   * npm global prefix pointed into the node tarball dir, so the published
#     symlinks were invisible to `bash -lc`.
#   * v1 and v2 both declare a bin named "opencode"; installing both into the
#     same global prefix makes npm overwrite one with the other.
#   * v2's real binary is fetched by the package postinstall; with install
#     scripts disabled you only get a 229-byte stub that errors out.
#
# This version: separate prefixes per major version, explicit stub detection,
# every candidate verified with --version before use, and network install only
# as a last resort. Re-running it is cheap: an install is skipped when the
# installed version already matches npm's latest, and the proot hard-link
# repair is applied after any install so OpenCode's /update keeps working.
set -uo pipefail
DISTRO="${OPENCODE_DISTRO:-debian}"

proot-distro login "$DISTRO" --shared-tmp -- /bin/bash -s <<'GUEST'
set -uo pipefail
say() { printf '[guest] %s\n' "$*"; }

# Cheap version lookup from the installed package.json. Running the binary
# costs ~200 MB of I/O every launch; reading one file does not.
pkg_version() {
  local pj="$1/package.json" v
  [ -f "$pj" ] || return 1
  v="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$pj" | head -n1)"
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

# Latest version straight from the registry. Empty when offline, which the
# callers treat as "unknown — fall back to installing @latest".
latest_version() {
  curl -fsSL --max-time 20 "https://registry.npmjs.org/$1/latest" 2>/dev/null \
    | sed -n 's/.*"version":"\([^"]*\)".*/\1/p' | head -n1
}

# OpenCode's postinstall hard-links the platform binary into place. proot
# (--link2symlink) then replaces the real path with a symlink into /.l2s, so
# process.execPath stops pointing at the npm package, OpenCode cannot find
# package.json above itself, and /update fails with "installation method not
# found". Copying to a fresh inode drops the link count back to 1.
# Returns 0 = already healthy, 2 = repaired, 1 = could not repair.
repair_binary() {
  local bin="$1" nlink tmp real
  [ -e "$bin" ] || [ -L "$bin" ] || return 1
  if [ ! -L "$bin" ] && [ -f "$bin" ]; then
    nlink="$(stat -L -c %h "$bin" 2>/dev/null || echo 1)"
    [ "$nlink" = "1" ] && return 0
  fi
  real="$(readlink -f "$bin" 2>/dev/null || true)"
  if [ -z "$real" ] || [ ! -f "$real" ]; then
    say "binary points nowhere: $bin"
    rm -f "$bin" 2>/dev/null
    return 1
  fi
  say "repairing hard-linked binary: $bin"
  tmp="$bin.repair.$$"
  if cp -L "$bin" "$tmp" 2>/dev/null; then
    rm -f "$bin"
    mv "$tmp" "$bin" 2>/dev/null || cp "$tmp" "$bin" 2>/dev/null
    chmod 755 "$bin" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
    return 2
  fi
  rm -f "$tmp" 2>/dev/null
  return 1
}

command -v node >/dev/null 2>&1 || { say "FATAL: node is missing in the guest — re-run ~/ocdl/install.sh"; exit 1; }

# --- 1. predictable npm layout, install scripts enabled -------------------
npm config set prefix /usr/local        >/dev/null 2>&1
npm config set ignore-scripts false     >/dev/null 2>&1
npm config set foreground-scripts true  >/dev/null 2>&1
PREFIX="$(npm prefix -g 2>/dev/null || echo /usr/local)"
BINDIR="$PREFIX/bin"
ROOT="$PREFIX/lib/node_modules"
V2ROOT="$ROOT/@opencode/cli"
V2BIN="$V2ROOT/bin/opencode.exe"
V1PREFIX="/usr/local/opencode-v1"
V1BIN="$V1PREFIX/lib/node_modules/opencode-ai/bin/opencode.exe"
say "npm prefix: $PREFIX"

# --- 2. update v2 FULL (skipped when already current) ---------------------
# npm does not treat "install the same version again" as a no-op: it reports
# a change, re-runs the postinstall (which re-creates the hard link proot
# chokes on) and takes minutes. Compare versions first.
oc_installed="$(pkg_version "$V2ROOT" || true)"
oc_latest="$(latest_version '@opencode%2Fcli' || true)"
if [ -n "$oc_latest" ] && [ "$oc_installed" = "$oc_latest" ] && [ -e "$V2BIN" ]; then
  say "v2 already at $oc_installed — skipping npm install"
else
  # An interrupted upgrade leaves @opencode/.cli-XXXX behind. npm reuses the
  # same deterministic name, so the next install dies with ENOTEMPTY.
  rm -rf "$ROOT/@opencode/.cli-"* 2>/dev/null || true
  say "v2 update: ${oc_installed:-none} -> ${oc_latest:-latest}"
  if npm install -g "@opencode/cli@${oc_latest:-latest}"; then
    say "v2 npm install: ok"
  else
    say "v2 npm install: FAILED"
  fi
fi

# v1 goes into its own prefix so it cannot fight v2 over the "opencode" name
v1_installed="$(pkg_version "$V1PREFIX/lib/node_modules/opencode-ai" || true)"
v1_latest="$(latest_version 'opencode-ai' || true)"
if [ -n "$v1_latest" ] && [ "$v1_installed" = "$v1_latest" ]; then
  say "v1 already at $v1_installed — skipping npm install"
else
  if npm install -g --prefix "$V1PREFIX" opencode-ai@latest; then
    say "v1 npm install: ok ($V1PREFIX)"
  else
    say "v1 npm install: FAILED"
  fi
fi

# --- 3. detect the postinstall stub and repair it ------------------------
is_stub() {  # the shipped stub is ~229 bytes and prints a known error
  [ -f "$1" ] || return 1
  [ "$(wc -c <"$1" 2>/dev/null || echo 0)" -lt 2000 ] && return 0
  grep -q "postinstall script was not run" "$1" 2>/dev/null && return 0
  return 1
}
if is_stub "$V2BIN"; then
  say "v2 binary is a stub — running postinstall by hand"
  ( cd "$V2ROOT" && node ./postinstall.mjs ) || say "manual postinstall failed"
fi
if is_stub "$V1BIN"; then
  say "v1 binary is a stub — running postinstall by hand"
  ( cd "$V1PREFIX/lib/node_modules/opencode-ai" && node ./postinstall.mjs ) || say "manual postinstall failed"
fi

# The postinstall above (and any install) leaves the binary hard-linked.
# Repair it now, before publishing links, so /update keeps working.
repair_binary "$V2BIN"
case $? in
  2) command -v opencode2 >/dev/null 2>&1 \
       && opencode2 service restart >/dev/null 2>&1 || true ;;
  1) say "warning: could not repair $V2BIN" ;;
esac

# --- 4. remove broken / self-referential links ----------------------------
for b in opencode opencode2 opencode1; do
  p="$BINDIR/$b"
  if [ -L "$p" ] && [ ! -x "$p" ]; then
    say "removing broken link: $p -> $(readlink "$p")"
    rm -f "$p"
  fi
done

# --- 5. pick the first candidate that actually runs ----------------------
run_version() {  # "$1" must print a version
  if command -v timeout >/dev/null 2>&1; then
    timeout 25 "$1" --version 2>&1
  else
    "$1" --version 2>&1
  fi
}
pick=""
# candidates in priority order: v2 (npm) -> v2 (official installer) -> v1 (own
# prefix) -> v1 (legacy global install from install.sh) -> anything findable
for cand in "$V2BIN" "$HOME/.opencode/bin/opencode" "$V1BIN" "$ROOT/opencode-ai/bin/opencode.exe" \
            "$PREFIX/lib/nodejs/"*/lib/node_modules/@opencode/cli/bin/opencode.exe \
            "$PREFIX/lib/nodejs/"*/bin/opencode \
            /usr/lib/node_modules/@opencode/cli/bin/opencode.exe \
            /usr/lib/node_modules/opencode-ai/bin/opencode.exe; do
  [ -n "$cand" ] || continue
  [ -s "$cand" ] || continue
  if out="$(run_version "$cand")" && [ -n "$out" ]; then
    say "candidate OK: $cand -> $out"
    pick="$cand"
    break
  else
    say "candidate BAD: $cand -> ${out:-<no output>}"
  fi
done

# --- 6. last resort: official v2 installer (network) ---------------------
if [ -z "$pick" ]; then
  say "no working candidate — trying https://opencode.ai/v2/install"
  if curl -fsSL --max-time 300 https://opencode.ai/v2/install | bash; then
    if out="$(run_version "$HOME/.opencode/bin/opencode")" && [ -n "$out" ]; then
      say "v2 installer worked: $out"
      pick="$HOME/.opencode/bin/opencode"
    fi
  else
    say "v2 installer failed"
  fi
fi

if [ -z "$pick" ]; then
  say "ERROR: no working opencode binary found in this guest"
  exit 1
fi

# --- 7. publish canonical links (never point a link at itself) ------------
ln -sfn "$pick" "$BINDIR/opencode2"
ln -sfn "$pick" "$BINDIR/opencode"
if [ -x "$V1BIN" ]; then
  ln -sfn "$V1BIN" "$BINDIR/opencode1"
fi

say "installed: $pick"
run_version "$BINDIR/opencode" | sed 's/^/[opencode] /'
GUEST
rc=$?
if [ "$rc" -ne 0 ]; then
  printf '[opencode] update/repair failed (exit %s)\n' "$rc" >&2
  exit "$rc"
fi

# --- 8. start -------------------------------------------------------------
printf '[opencode] Starting ...\n'
exec proot-distro login "$DISTRO" --shared-tmp -- /bin/bash -lc '
  export PATH="$(npm prefix -g 2>/dev/null)/bin:$HOME/.opencode/bin:$PATH"
  if command -v opencode2 >/dev/null 2>&1 && [ -x "$(command -v opencode2)" ]; then
    exec opencode2 "$@"
  elif command -v opencode >/dev/null 2>&1 && [ -x "$(command -v opencode)" ]; then
    exec opencode "$@"
  else
    echo "ERROR: opencode binary missing inside '"$DISTRO"'"; exit 1
  fi
' -- "$@"
