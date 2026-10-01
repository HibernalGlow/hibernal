# Hibernal

A native macOS menu bar app that triggers **deep hibernate on demand** — independent of closing the lid. Built from a custom `pmset` workflow (originally an iCloud Shortcut) and packaged as a proper Swift app with settings, a global keyboard shortcut, and a one-time privileged helper.

![Hibernal app icon](Resources/AppIcon-1024.png)

## Install

```bash
brew install --cask hibernalglow/tap/hibernal
```

Or download `Hibernal-<version>.dmg` from [the latest release](https://github.com/HibernalGlow/hibernal/releases/latest), mount it and drag **Hibernal** to **Applications**.

Builds are **ad-hoc signed and not notarized** (no Developer ID). That is enough for the signature to validate — `codesign --verify --deep --strict` passes — so Finder will not call the app damaged, but a quarantined copy still needs one manual approval: **System Settings → Privacy & Security → Open Anyway**. Homebrew also installs with the quarantine flag, so the same override applies once after every install or upgrade.

On first hibernate macOS asks for your password **once** to install the privileged helper (`com.hibernal.helper`). After that hibernates are passwordless — **including across app updates**, because readiness compares the installed helper's bytes with the one this build ships, so the prompt only comes back when the helper itself actually changes.

## What it does

- **Hibernate now** via global keyboard shortcut or menu bar
- **Normal lid-close sleep** stays separate (optional restore to `hibernatemode 3` after wake)
- **One-time password** to install a privileged helper — no password on every hibernate after that
- **Countdown popup** when a sleep assertion blocks immediate re-hibernate
- **Menu bar moon icon** keeps the shortcut alive after you close Settings
- English and Simplified Chinese — the app follows the system language, and `CFBundleLocalizations` lists both so you can also pin one language to this app alone in System Settings

## Settings

| Option | Description |
|--------|-------------|
| **Enable hibernate** | Master on/off for shortcut and hibernate actions |
| **Restore normal sleep after wake** | Returns to `hibernatemode 3` after shortcut hibernate so lid-close stays standard sleep |
| **Eject external drives** | Safely ejects USB, Thunderbolt, and SD volumes before hibernating |
| **Keep awake on power adapter** | Sets `pmset -c sleep 0` while plugged in |
| **Start on login** | Launches hidden to the menu bar at login |
| **Keyboard shortcut** | Default: Control + Option + Command + `\` |

### Window & service controls

- **Cmd+Q** or red close button — hides Settings; app keeps running in menu bar
- **Stop Background Service** — disables menu bar icon and shortcut; Settings stays open
- **Restart App** — re-enables menu bar and shortcut
- **Quit App** — fully exits

## How hibernate works

When triggered, the app:

1. Pauses known sleep-blocking processes (e.g. Grok agent, AMP agents)
2. Sets `hibernatemode 25` and disables standby/power nap
3. Waits out a blocking sleep assertion if one is listed (with on-screen countdown)
4. Runs `pmset sleepnow`
5. Optionally restores `hibernatemode 3` after wake

Because the helper runs the whole script, everything above happens as root from one
launch; if `sleepnow` did not actually hibernate, the script leaves `hibernatemode` at 25
and logs `sleepnow did not hibernate (hibernatecount N -> N)` instead of pretending the
restore happened.

Logs: `~/Library/Logs/Hibernal/hibernate.log` · support files: `~/Library/Application Support/Hibernal/`

## Requirements

- macOS 13.0 or later
- Universal binary: Apple Silicon and Intel in one DMG

## Build from source

```bash
git clone https://github.com/HibernalGlow/hibernal.git
cd hibernal
./build-dmg.sh          # or ./build-app.sh for just the bundle
```

Outputs: `dist/Hibernal.app` and `releases/Hibernal-<version>.dmg` (both gitignored; release assets come from CI).

`build-app.sh` compiles every arch in `ARCHS` (default `arm64 x86_64`), `lipo`s them together, signs inside-out (helper first, then the bundle seal) and fails the build if `codesign --verify --deep --strict` rejects the result. Pass `SIGN_IDENTITY="Developer ID Application: …"` to sign with a real certificate.

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds, verifies and publishes the DMG as a release asset (and prints its sha256 in the job summary for the Homebrew cask).

## Troubleshooting

**Shortcut not working after boot**
Wait ~30 seconds after login, or open Settings once and close it. The app re-registers the hotkey on a schedule after login launch.

**"Second hibernate only sleeps"**
Measured on an M-series Mac: after waking from hibernate, `powerd` holds a `hibernate user wake` assertion (`UserIsActive`) for **600 s**, and this app waits at most **125 s** before forcing `pmset sleepnow` anyway. Inside that window a forced sleep has been observed both hibernating and not hibernating, so the countdown is not a guarantee — check `pmset -g log` for `Wake from Hibernate` versus a plain sleep to see which you got.

**Machine wakes itself ~10 minutes after hibernating**
That is not this app. On every sleep `powerd` schedules a user-invisible wake alarm ~590 s out, registered by `AppleCredentialManagerDaemon` (`com.apple.alarm.user-invisible-com.apple.acmd.alarm`). It is not shown by `pmset -g sched` while pending, `pmset schedule cancelall` does not remove it, and disabling AppleCredentialManager is not advisable — it is a system credential/TPM-facing daemon.

**Privileged helper not installed**
Check Settings for the orange/green helper status. First hibernate prompts for your password once to install.

**Move app to Applications**
Use **Quit App** before copying to `/Applications`, then toggle **Start on login** off and on to refresh the Launch Agent path.

## Renaming note

Version 2.0.0 renamed the app from *Hibernate Control* to **Hibernal**, including the bundle identifier (`com.hibernal.app`), the helper (`com.hibernal.helper`), the login item (`com.hibernal.agent`) and the settings domain. Any pre-2.0.0 copy keeps its old helper and login item installed; remove them once the new version is working:

```bash
sudo launchctl bootout system/com.hibernatecontrol.helper
sudo rm /Library/LaunchDaemons/com.hibernatecontrol.helper.plist \
        /Library/PrivilegedHelperTools/com.hibernatecontrol.helper \
        ~/Library/LaunchAgents/com.hibernatecontrol.agent.plist
```

## License

Personal utility project. Use at your own risk — hibernate affects power state and open work.
