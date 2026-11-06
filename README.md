<p align="center">
  <img src="docs/assets/moon.svg" alt="Ansomnia: a crescent moon with a slash through it" width="112">
</p>

<h1 align="center">Ansomnia</h1>

<p align="center">
  <strong>Keep your Mac awake. Give the session an end time.</strong>
</p>

<p align="center">
  A macOS menu bar app for timed awake sessions. Ansomnia is a moon icon that
  lives in your MacBook menu bar. It has no Dock icon and no main window. Set
  how long your Mac stays awake, choose what happens when the lid closes, and
  see when something could not be undone.
</p>

<p align="center">
  <a href="https://github.com/AImunich20/Ansomnia/releases/latest/download/Ansomnia.dmg"><strong>Download</strong></a> ·
  <a href="#install"><strong>Install</strong></a> ·
  <a href="#using-it"><strong>Using it</strong></a> ·
  <a href="#what-happens-when-the-lid-closes"><strong>Lid close</strong></a> ·
  <a href="#how-recovery-works"><strong>Recovery</strong></a> ·
  <a href="SECURITY.md"><strong>Security</strong></a>
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/License-MIT-536D78?style=flat-square"></a>
  <img alt="macOS 26 or later" src="https://img.shields.io/badge/macOS-26%2B-303336?style=flat-square">
  <img alt="Experimental source build" src="https://img.shields.io/badge/Status-experimental-536D78?style=flat-square">
</p>

> **Use a stable, well-ventilated surface, not a closed bag.** Ansomnia is
> experimental. Recovery can fail, and a running timer is not a safety
> guarantee.
> [Validation status](docs/release-validation.md) · [Apple's ventilation guidance](https://support.apple.com/en-us/102336)

<p align="center">
  <img src="docs/assets/session-flow.svg" alt="Illustrated menu-bar controls: enter Days, Hours, and Minutes, watch the countdown, and click × to finish early. Click the moon or countdown to add time. Closing the lid is optional, and incomplete recovery needs attention." width="880">
</p>

## Install

Requires macOS 26 or later on an Apple Silicon Mac.

<p align="center">
  <a href="https://github.com/AImunich20/Ansomnia/releases/latest/download/Ansomnia.dmg"><img alt="Download Ansomnia.dmg" src="https://img.shields.io/badge/Download-Ansomnia.dmg-303336?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>

<p align="center">
  <a href="https://github.com/AImunich20/Ansomnia/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/AImunich20/Ansomnia?style=flat-square&label=latest&color=536D78"></a>
  <a href="https://github.com/AImunich20/Ansomnia/actions/workflows/release.yml"><img alt="Release build" src="https://github.com/AImunich20/Ansomnia/actions/workflows/release.yml/badge.svg"></a>
</p>

The button always downloads the newest release:
`https://github.com/AImunich20/Ansomnia/releases/latest/download/Ansomnia.dmg`.

1. Open `Ansomnia.dmg`.
2. In Terminal, run the installer on the disk image (it asks for your
   password once, for the sudoers rule):

   ```bash
   bash "/Volumes/Ansomnia/Install Ansomnia.command"
   ```

3. Ansomnia opens in the menu bar. The app is ad-hoc signed, not notarized,
   so if macOS blocks the first launch, open System Settings > Privacy &
   Security and click **Open Anyway**.

Each release lists the DMG's SHA-256 in `SHA256SUMS`; to check a download,
compare it with `shasum -a 256 ~/Downloads/Ansomnia.dmg`.

### Updates

Right-click the moon, choose Settings, and under App click **Check for
updates**. When a newer release exists, **Download and install** fetches its
DMG from GitHub, checks it against the release's `SHA256SUMS` and installs it
in the background, with no Terminal window: Ansomnia ends any session, quits
and reopens as the new version, and a notification says how it went (details
in `~/Library/Logs/Ansomnia/update.log`). It asks for your password, in a
macOS dialog, only if the sleep permission in `/etc/sudoers.d/ansomnia` has
to be written again. The app never checks on its own.

### How releases are built

[`.github/workflows/release.yml`](.github/workflows/release.yml) runs on every
push to `main`. It reads `CFBundleShortVersionString` from
[`Resources/Info.plist`](Resources/Info.plist), and when that version has no
release yet it builds the DMG on a macOS 26 runner with
[`scripts/make-dmg.sh`](scripts/make-dmg.sh) and publishes it as the GitHub
Release `v<version>`, marked Latest. To ship a new version, bump the version
in `Resources/Info.plist` and push. Pushes that keep the version publish
nothing.

A release can also be built on your own Mac (this needs Xcode), without
waiting for the workflow:

```bash
scripts/release-local.sh --install            # test, build dist/, install it here
scripts/release-local.sh --install --publish  # ...and publish it on GitHub
```

`--publish` pushes `main` together with the tag `v<version>` in one atomic
push and uploads the DMG built here, with the same files and notes as the
workflow. The workflow run that push starts finds the tag and stops, so
either way ships a version exactly once.

To build the same DMG yourself: `scripts/make-dmg.sh --output dist`.

### Build from source

Needs Xcode with Swift 6.2 or later. Replace `v<version>` with the latest
release tag, or leave out `--branch v<version>` for the newest code:

```bash
git clone --branch v<version> --depth 1 https://github.com/AImunich20/Ansomnia.git
cd Ansomnia
./scripts/install.sh
open "$HOME/Applications/Ansomnia.app"
```

<details>
<summary><strong>What the installer changes on your Mac</strong></summary>

The installer needs your password, because the sudoers rule is a system
file. It installs:

- The app, at `~/Applications/Ansomnia.app`.
- A **recovery agent**, a `launchd` job that runs every minute. If the app is
  gone when a session should have ended, the agent tries to undo the
  session's changes.
- A **sudoers rule** at `/etc/sudoers.d/ansomnia`. A sudoers rule decides who
  can run what with `sudo`. This one lets your user account, not just
  Ansomnia, run these four commands without a password:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -b lowpowermode 1
/usr/bin/pmset -b lowpowermode 0
```

Any program running as you can use that rule too, so review it before you
install. [docs/install.md](docs/install.md#what-gets-installed) lists every
file and explains how upgrades replace them.

</details>

## Using it

1. **Start.** Click the moon in the menu bar, enter days, hours and minutes,
   and press Enter.
2. **Add time.** Click the moon or the countdown during a session.
3. **End early.** Click the × next to the countdown.
4. **Settings and status.** Right-click the moon. Quit asks Ansomnia to undo
   the session first, and it refuses while a change is still waiting to be
   undone. Saved audio for an output that isn't connected doesn't hold it up.
   Ansomnia restores that output if it reconnects while the app runs, or at
   the next launch.

You don't have to close the lid, and opening it doesn't end the session.

On battery power, Ansomnia turns on Low Power Mode below 40% and ends the
session below 10%. Those are the defaults. You can change both in Settings,
and an end floor of 0 turns the battery end off. The heat rules turn on Low Power
Mode when the Mac gets seriously hot and end the session at critical heat.
They are on by default, and Settings can turn them off. All of these rules
only work while the app runs.

Before your first session, check Settings. Then run a short session you can
watch, and read `~/Library/Logs/Ansomnia/ansomnia.log` afterward.

## What happens when the lid closes

<p align="center">
  <img src="docs/assets/lid-actions.svg" alt="Illustrated Settings defaults: Slack, WhatsApp, and Discord on the freeze list, Docker's idle rule off, mute on. During a session, lid close applies configured actions; reopening attempts to resume verified owned freezes and restore saved audio. The session continues. Without an active session, lid changes do nothing." width="880">
</p>

During a session, closing the lid does each of these, and opening it tries
to undo them. The timer keeps counting down while the lid is closed.

- **Display and keyboard light go off.** Ansomnia saves their brightness
  first. With sleep turned off, macOS no longer does this by itself.
- **Apps on the freeze list are frozen.** Freezing sends an app's processes
  `SIGSTOP`, which pauses them until `SIGCONT` on lid open. The list starts
  with Slack, WhatsApp and Discord. "Freeze every other app" is off by
  default. Even when on, it skips meeting, recording and dictation apps: Zoom,
  Teams, Webex, FaceTime, Wispr Flow, Granola, Otter, OBS and Loom.
- **Audio is muted.** Lid open unmutes each output Ansomnia muted, even if you
  switched to another one.
- **Low Power Mode turns on.** It turns off when the lid opens, unless a
  battery or heat rule still needs it.
- **Docker Desktop is frozen when no container runs.** This one is off by
  default.

On Mac laptops with Apple silicon or a T2 chip, closing the lid disconnects
the built-in microphone in hardware. Recording a meeting with the lid closed
needs AirPods or an external mic.

[docs/lid-close.md](docs/lid-close.md) has the details: how Docker is checked,
how brightness is restored, the one-time settings change when you upgrade,
and how to test lid actions without closing the lid.

## How recovery works

<p align="center">
  <img src="docs/assets/recovery-flow.svg" alt="The app and a launchd backstop coordinate through a shared lock and recovery journal. The app handles normal cleanup. The backstop checks every minute and attempts due recovery, leaving valid active sessions alone. Failed or unreadable recovery evidence stays on disk; saved audio needs the app and unconfirmed stopped processes need inspection." width="880">
</p>

Ansomnia writes each change to a **recovery journal**, a file on disk, before
it makes the change. Ending the session tries to undo what the journal lists.
If the app crashes or quits, the recovery agent tries the same once the
session's end time has passed.

Some things need you:

- The recovery agent can't restore audio. Open Ansomnia again for that.
- The recovery agent doesn't watch the battery or the temperature.
- Ansomnia only unfreezes a process it can prove it froze. A frozen process
  it can't prove stays frozen until you check it.

If the menu shows a recovery warning, deal with it before you leave the Mac
alone. [docs/recovery.md](docs/recovery.md) explains each case.

## Optional extras

<details>
<summary><strong>iPhone hotspot handoff and tmux</strong></summary>

If the Wi-Fi drops during a session, Ansomnia can join your iPhone's hotspot.
Set System Settings > Wi-Fi > Ask to join hotspots to Automatically, then enter
the hotspot's name and password in Ansomnia's Settings. The password stays in
your login Keychain. Ansomnia asks for Location Services access, because
macOS requires it to read Wi-Fi network names. It never reads your location.
After you reinstall Ansomnia, enter the password again.

After 90 seconds without a network, Ansomnia can also type `continue` into a
tmux pane running a coding agent. It only types into panes you list in
Settings and mark yourself:

```bash
tmux set-option -p -t <session:window.pane> @ansomnia-nudge on
```

It doesn't press Enter unless you turn that on. Mark a pane you don't type in.
[docs/extras.md](docs/extras.md) has the details.

</details>

<details>
<summary><strong>Chrome, Chromium, Arc and Comet throttling</strong></summary>

These browsers slow down windows that macOS reports as hidden, which includes
every window while the lid is closed. If a running browser lacks
`--disable-backgrounding-occluded-windows` or
`--disable-renderer-backgrounding`, the right-click menu offers "Relaunch
[browser] unthrottled". It asks first, because relaunching quits the browser,
and tabs come back only if the browser reopens them on startup. Some web apps
may still stop with the lid closed.
[docs/extras.md](docs/extras.md#chrome-chromium-arc-and-comet-throttling) has the
details.

</details>

<details>
<summary><strong>Configuration and privacy</strong></summary>

Settings live in `~/Library/Application Support/Ansomnia/config.json` and logs
in `~/Library/Logs/Ansomnia/`. Ansomnia sets both folders and their files to
owner-only permissions. It leaves symlinks and access control lists (ACLs,
extra per-account permission entries) as they are, so another account can
still have access through one. Logs can contain Wi-Fi names, process details
and tmux targets, so check them before you share one.
[docs/extras.md](docs/extras.md#configuration-and-privacy) has the details.

</details>

## Uninstall

From your checkout:

```bash
./scripts/uninstall.sh          # removes the app, the agent and the sudoers rule
./scripts/uninstall.sh --purge  # also removes settings and logs
```

From the release DMG, run `bash /Volumes/Ansomnia/uninstall.sh` instead. The
uninstaller undoes any open session first and stops if it can't.
[docs/install.md](docs/install.md#uninstall) has the details.

## Development

```bash
swift build
swift test
```

The tests use fakes and temporary folders, so they never change your power
settings. See [Contributing](CONTRIBUTING.md), [Security reporting](SECURITY.md),
[Release validation](docs/release-validation.md) and [Design notes](docs/spec.md).

## Star history

<a href="https://www.star-history.com/?repos=AImunich20%2FAnsomnia&amp;type=date&amp;legend=top-left">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=AImunich20/ansomnia&amp;type=date&amp;theme=dark&amp;legend=top-left" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=AImunich20/ansomnia&amp;type=date&amp;legend=top-left" />
    <img alt="Star history for AImunich20/Ansomnia" src="https://api.star-history.com/svg?repos=AImunich20/ansomnia&amp;type=date&amp;legend=top-left" />
  </picture>
</a>

## License

[MIT](LICENSE)
