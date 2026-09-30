# Hibernate Control

A native macOS menu bar app that triggers **deep hibernate on demand** — independent of closing the lid. Built from a custom `pmset` workflow (originally an iCloud Shortcut) and packaged as a proper Swift app with settings, a global keyboard shortcut, and a one-time privileged helper.

![Hibernate Control app icon](Resources/AppIcon-1024.png)

## What it does

- **Hibernate now** via global keyboard shortcut or menu bar
- **Normal lid-close sleep** stays separate (optional restore to `hibernatemode 3` after wake)
- **One-time password** to install a privileged helper — no password on every hibernate after that
- **Countdown popup** when macOS AC power cooldown (`acwakelinger`) blocks immediate re-hibernate
- **Menu bar moon icon** keeps the shortcut alive after you close Settings

## Download

**[Latest release (DMG)](https://github.com/PreparedToBeReckless/hibernate-control/releases/latest)**

1. Download `Hibernate Control-x.x.x.dmg`
2. Open the DMG and drag **Hibernate Control** to **Applications**
3. Open the app from Applications
4. Configure settings, then close the window — the app stays in the menu bar

On first hibernate, macOS will ask for your password **once** to install the privileged helper. After that, hibernates are passwordless.

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
3. Waits for AC power cooldown if needed (with on-screen countdown)
4. Runs `pmset sleepnow`
5. Optionally restores `hibernatemode 3` after wake

Logs: `~/Library/Logs/HibernateControl/hibernate.log`

## Requirements

- macOS 13.0 or later
- Apple Silicon or Intel Mac

## Build from source

```bash
git clone https://github.com/PreparedToBeReckless/hibernate-control.git
cd hibernate-control

# Build app bundle
./build-app.sh

# Build DMG installer
./build-dmg.sh
```

Outputs:

- `dist/Hibernate Control.app` — latest build
- `releases/Hibernate Control-<version>.app` — archived build
- `releases/Hibernate Control-<version>.dmg` — installer

Both scripts ad-hoc sign their output and fail the build if `codesign --verify --deep --strict` rejects it. Pass `SIGN_IDENTITY` to sign with a real certificate instead.

## Project structure

```
Sources/HibernateControl/   Main app (settings UI, menu bar, hotkey)
Sources/HibernateHelper/    Privileged helper (root pmset execution)
Sources/Shared/             XPC protocol shared by app and helper
Resources/                  App icon (.icns)
build-app.sh                Compile and bundle the app
build-dmg.sh                Package DMG for distribution
```

## Troubleshooting

**Shortcut not working after boot**  
Wait ~30 seconds after login, or open Settings once and close it. The app re-registers the hotkey on a schedule after login launch.

**Second hibernate only sleeps (not full hibernate)**  
macOS enforces a cooldown after wake before another full hibernate will stick. On battery this is about **2 minutes** (`hibernate user wake`); on AC it is shorter (`acwakelinger`). The countdown popup waits for this automatically — let it finish, or cancel and retry later.

**Privileged helper not installed**  
Check Settings for the orange/green helper status. First hibernate prompts for your password once to install.

**"Hibernate Control is damaged" / "cannot be verified"**  
Builds are ad-hoc signed (`codesign --verify --deep --strict` passes), so drag-to-Applications works, but a *quarantined* copy still needs one approval on a machine with Gatekeeper enabled: **System Settings → Privacy & Security → Open Anyway**. Any copy built before the signing step is genuinely invalid (no resource seal) and Finder reports it damaged regardless of approval — rebuild from this version of `build-dmg.sh`.

To remove the approval step for everyone, sign with a paid Apple Developer ID and notarize:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-dmg.sh
xcrun notarytool submit "releases/Hibernate Control-$(cat VERSION).dmg" --keychain-profile notary --wait
```

**Move app to Applications**  
Use **Quit App** before copying to `/Applications`, then toggle **Start on login** off and on to refresh the Launch Agent path.

## License

Personal utility project. Use at your own risk — hibernate affects power state and open work.