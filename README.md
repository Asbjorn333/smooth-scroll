# SmoothScroll

SmoothScroll is a native macOS menu bar app that makes mouse wheel scrolling feel smooth and inertial, closer to trackpad scrolling.

## What it does

- Captures discrete wheel input from external mice
- Re-emits smooth pixel-based scroll events
- Keeps trackpad/continuous scroll behavior untouched
- Supports vertical and horizontal wheel smoothing
- Runs as a lightweight menu bar utility

## Features

- Menu bar app with icon
- `Enabled` toggle
- `Window Switcher (Cmd+Tab)` toggle for per-window switching
- `Keyboard Cleaning` mode toggle
- `Mouse Buttons` section with side-button mapping
- Live tuning sliders for `Speed`, `Pointer Speed`, `Smoothness`, `Decay`, and `FPS`
- `Save Settings` action
- Auto-save of settings via `UserDefaults`
- `Launch at Login` toggle
- Optional headless mode (`--headless`)
- Desktop `.app` bundle build/install scripts

## Requirements

- macOS 13+
- Swift 6 toolchain / Xcode Command Line Tools

## Secret scanning (gitleaks)

Install gitleaks:

```bash
brew install gitleaks
```

Enable the repository pre-commit hook:

```bash
./scripts/install-git-hooks.sh
```

After this, every commit is scanned for secrets from staged files. A commit is blocked when a potential secret is detected.

Manual full-history scan:

```bash
gitleaks git --redact .
```

CI is also configured in `.github/workflows/gitleaks.yml` to run on `push` and `pull_request`.

## Quick start (recommended)

Build and install a desktop app on `~/Desktop`:

```bash
./scripts/install-app.sh
```

Then open `~/Desktop/SmoothScroll.app`.

## First launch permissions

Grant both permissions when prompted:

- `System Settings > Privacy & Security > Accessibility`
- `System Settings > Privacy & Security > Input Monitoring`

Without these permissions, event capture cannot work.

## Menu controls

- `Enabled`: turns smoothing on/off
- `Window Switcher (Cmd+Tab)`: replaces native app switching with visible window switching, including multiple windows from the same app
- `Enable Keyboard Cleaning`: blocks keyboard input globally so you can clean the keyboard safely with mouse/trackpad still active; auto-disables after 2 minutes
- `Mouse Buttons`: map side buttons (`Button 4`/`Button 5`) to `Passthrough`, `Back`, `Forward`, `Toggle SmoothScroll`, or keyboard keys (for example `Enter`)
- `Speed`: stronger scroll output per wheel notch
- `Pointer Speed`: controls macOS cursor tracking for both mouse and trackpad (`com.apple.mouse.scaling` + `com.apple.trackpad.scaling`)
- `Smoothness`: higher value = softer, more blended response
- `Decay`: higher value = shorter glide tail
- `FPS`: output update rate
- `Save Settings`: explicit manual save (slider changes are also auto-saved)
- `Launch at Login`: installs/removes a LaunchAgent

## Tuning ranges

- `Speed`: `1..1000`
- `Pointer Speed`: `0.0..20.0` (applies to global + runtime HID acceleration)
- `Smoothness`: `0.00..0.995`
- `Decay`: `0.1..120.0`
- `FPS`: `30..360`

## Default profile

- `Speed`: `100`
- `Pointer Speed`: uses current macOS pointer speed on first launch
- `Smoothness`: `0.80`
- `Decay`: `28.0`
- `FPS`: `120`

## Run from source

Menu bar mode:

```bash
swift run SmoothScroll
```

Headless mode:

```bash
swift run SmoothScroll --headless
```

Headless with custom tuning:

```bash
swift run SmoothScroll --headless --speed 100 --pointer-speed 2.0 --smoothness 0.80 --decay 28 --fps 120
```

## App bundle scripts

Build `.app` bundle into `dist/`:

```bash
./scripts/build-app.sh
```

Install `.app` to Desktop:

```bash
./scripts/install-app.sh
```

Update existing installed app in place (auto-detects `~/Applications`, `/Applications`, or `~/Desktop`):

```bash
./scripts/update-app.sh
```

Update a specific installed app path:

```bash
./scripts/update-app.sh "/Applications/SmoothScroll.app"
```

Install to custom directory:

```bash
TARGET_DIR="$HOME/Applications" ./scripts/install-app.sh
```

Open built app:

```bash
./scripts/open-app.sh
```

Close app:

```bash
./scripts/close-app.sh
```

## Launch at login scripts (optional)

Install LaunchAgent:

```bash
./scripts/install-launch-agent.sh
```

Remove LaunchAgent:

```bash
./scripts/uninstall-launch-agent.sh
```

## Troubleshooting

No scrolling effect:

- Confirm Accessibility + Input Monitoring are granted
- Quit and relaunch the app after granting permissions

`Cmd+Tab` still switches apps instead of windows:

- Confirm `Window Switcher (Cmd+Tab)` is enabled in the menu
- Quit and relaunch the app after granting Accessibility and Input Monitoring

Finder still shows an old app icon:

```bash
touch ~/Desktop/SmoothScroll.app
killall Finder
```

Scrolling feels too fast or too floaty:

- Reduce `Speed` if it feels too strong
- Increase `Decay` if glide lasts too long
- Reduce `Smoothness` if response feels sluggish

## Project layout

- `Sources/SmoothScroll/SmoothScroll.swift`: app, engine, menu UI
- `scripts/build-app.sh`: builds `.app` bundle
- `scripts/generate-icon.sh`: generates `AppIcon.icns`
- `scripts/install-app.sh`: installs app to Desktop or custom dir
- `scripts/update-app.sh`: rebuilds and updates an installed app path
- `scripts/install-launch-agent.sh`: optional LaunchAgent installer

## Privacy

SmoothScroll does not send telemetry or network data. It processes local input events on your machine only.

## License

MIT. See `LICENSE`.
