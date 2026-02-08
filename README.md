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
- Live tuning sliders for `Speed`, `Smoothness`, `Decay`, and `FPS`
- `Save Settings` action
- Auto-save of settings via `UserDefaults`
- `Launch at Login` toggle
- Optional headless mode (`--headless`)
- Desktop `.app` bundle build/install scripts

## Requirements

- macOS 13+
- Swift 6 toolchain / Xcode Command Line Tools

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
- `Speed`: stronger scroll output per wheel notch
- `Smoothness`: higher value = softer, more blended response
- `Decay`: higher value = shorter glide tail
- `FPS`: output update rate
- `Save Settings`: explicit manual save (slider changes are also auto-saved)
- `Launch at Login`: installs/removes a LaunchAgent

## Default profile

- `Speed`: `100`
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
swift run SmoothScroll --headless --speed 100 --smoothness 0.80 --decay 28 --fps 120
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
- `scripts/install-launch-agent.sh`: optional LaunchAgent installer

## Privacy

SmoothScroll does not send telemetry or network data. It processes local input events on your machine only.

## License

MIT. See `LICENSE`.
