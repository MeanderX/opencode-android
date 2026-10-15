# OpenCode on Android (Termux)

A tiny tool that installs [OpenCode](https://opencode.ai) on your Android
phone and launches it in the right environment — then puts it one tap away on
your home screen.

## Why it needs a Linux environment

OpenCode's installers and npm check `process.platform`, which reports
`android` inside plain Termux and breaks installation. The fix used here is
[proot-distro](https://github.com/termux/proot-distro): a real Debian Linux
environment inside Termux (no root required) where OpenCode installs and runs
normally, kept current with upstream releases.

## Requirements

- Termux installed (from [F-Droid](https://f-droid.org/en/packages/com.termux/)
  or the [GitHub releases](https://github.com/termux/termux-app/releases) —
  the Play Store build is outdated and does not work with this)
- Roughly 1.5–2 GB of free storage

## Install

**Option A — clone from GitHub (recommended):**

```sh
pkg install git
git clone https://github.com/MeanderX/opencode-android
cd opencode-android
bash install.sh
```

**Option B — copy the files manually:**

1. Get these four files onto the phone, e.g. into `Download/`:
   `install.sh`, `oc`, `OpenCode.sh`, `npm-shim` (USB or cloud drive).
2. Open Termux and run:

   ```sh
   cd ~/storage/downloads/opencode-android   # wherever you put the files
   bash install.sh
   ```

The installer updates Termux, creates the Debian environment, installs
Node.js 22 + OpenCode inside it, and installs the `oc` launcher. It asks
for storage access once (approve the Android dialog).

## Use

| Command | What it does |
|---|---|
| `oc` | OpenCode in the last used project (or `~/projects`) |
| `oc my-project` | OpenCode in `~/projects/my-project` (created if missing) |
| `oc /some/dir` | OpenCode in an explicit directory |
| `oc run "prompt"` | One-off prompt without the interactive interface |
| `oc shell` | Drop into the Linux environment itself |
| `oc auth login` | Sign in to a provider (persists in the environment) |

Anything that is not a project directory is passed straight through to
`opencode`, so flags work too: `oc --version`, `oc mini`, `oc mcp list`, ...

On first launch, sign in to a model provider inside OpenCode.

## Home-screen widget (optional)

Install the [Termux:Widget](https://f-droid.org/en/packages/com.termux.widget/)
app **from the same source as Termux**, then:

1. Long-press the home screen → **Widgets** → **Termux:Widget**
2. Drag the **OpenCode.sh** shortcut onto your home screen

Tapping it opens OpenCode directly.

## Updating

**Automatic.** Both launchers — `oc` and the home-screen widget — check the
npm registry at most once every 24 hours and install a newer OpenCode if
there is one. Most launches do nothing at all; when a check does run it
prints what it is doing. No check happens when you are offline.

Turn it off with an environment variable:

```sh
OC_NO_AUTOUPDATE=1 oc
```

**Manual.** Inside OpenCode, run `/update`. From the shell:

```sh
oc                       # picks up any pending update on launch
oc shell                 # then: npm install -g @opencode/cli@latest
```

Re-running `bash install.sh` is also safe at any time — it is idempotent and
refreshes everything.

### Why this needed extra work on proot

OpenCode decides how it was installed by looking for a `package.json` two
directories above its own executable, then confirming the npm package is
globally installed. Two things on Android get in the way, and this repo
handles both:

1. **proot's `--link2symlink`.** OpenCode's npm `postinstall` *hard-links*
   the platform binary into place, leaving `st_nlink = 2`. proot runs any
   multi-linked file from a synthetic `/.l2s/...` path instead of its real
   one, and replaces the real path with a symlink to it. OpenCode's
   `process.execPath` then stops pointing at the npm package, the
   `package.json` lookup fails, and it reports
   `installation method not found`. The launchers copy the binary back into
   a plain file before every launch, which also repairs it after any
   update — including one you run from inside OpenCode itself. Note that
   `stat` must be given `-L` to see through the symlink; without it a
   hijacked binary looks perfectly healthy.
2. **A slow `npm list -g`.** The detection step shells out to npm with a
   short deadline, and under proot real npm needs ~8 seconds just to start,
   so the probe can time out. `npm-shim` answers that one query straight
   from disk in milliseconds and forwards everything else to the real npm.


## Tips

- **Keyboard hides in the TUI:** press the recent-apps button, then return to
  Termux — the keyboard comes back.
- Projects live in `~/projects` (Termux) and are visible at the same path
  inside the Linux environment.
- If something misbehaves, check `oc shell` → `opencode service status`.

## Troubleshooting

- **`/update` says "Could not detect the installation method":** the binary
  is hard-linked again, which usually means it was reinstalled without going
  through these launchers. Confirm and repair:

  ```sh
  oc shell
  stat -c %h /usr/local/lib/node_modules/@opencode/cli/bin/opencode.exe
  # 1 is correct; 2 or more means proot will hijack the path
  ```

  Simply launching `oc` once fixes it. To do it by hand:

  ```sh
  oc shell
  b=/usr/local/lib/node_modules/@opencode/cli/bin/opencode.exe
  cp -L "$b" "$b.repair" && rm -f "$b" && mv "$b.repair" "$b" && chmod 755 "$b"
  ```

- **`exec: opencode: not found` after install:** npm's default global prefix
  with a tarball Node install is the tarball root instead of `/usr/local`, so
  the `opencode` launcher lands outside PATH. The installer now pins the
  prefix. To fix an install made before that fix:

  ```sh
  oc shell
  npm config set prefix /usr/local && npm install -g @opencode/cli
  ```

  That also leaves a stray copy of OpenCode (~150 MB) under the tarball
  root. Remove it with:

  ```sh
  rm -rf /usr/local/lib/nodejs/node-v22*/lib/node_modules/opencode-*
  rm -f /usr/local/lib/nodejs/node-v22*/bin/opencode
  ```

## Uninstall

```sh
proot-distro remove debian   # removes the Linux environment and OpenCode
rm "$PREFIX/bin/oc" "$HOME/.shortcuts/OpenCode.sh"
```
