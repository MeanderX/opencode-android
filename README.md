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

1. Get these three files onto the phone, e.g. into `Download/`:
   `install.sh`, `oc`, `OpenCode.sh` (USB or cloud drive).
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

Re-run `bash install.sh` — it is idempotent and refreshes OpenCode.
To update manually: `oc shell`, then `npm update -g opencode-ai`.

## Tips

- **Keyboard hides in the TUI:** press the recent-apps button, then return to
  Termux — the keyboard comes back.
- Projects live in `~/projects` (Termux) and are visible at the same path
  inside the Linux environment.
- If something misbehaves, check `oc shell` → `opencode service status`.

## Uninstall

```sh
proot-distro remove debian   # removes the Linux environment and OpenCode
rm "$PREFIX/bin/oc" "$HOME/.shortcuts/OpenCode.sh"
```
