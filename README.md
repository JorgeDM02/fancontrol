# FanControl

Take control of your Mac's cooling fans from the menu bar.

FanControl gives you live temperature and fan-speed monitoring plus hands-on fan control for Apple Silicon Macs (M1 through M5, macOS 14 or newer). Instead of being stuck with whatever fan curve the system picks, you can set your own speeds, save presets, and build temperature-driven fan curves — all from a clean SwiftUI window and a menu-bar widget.

## Features

- **Live monitoring** — see CPU, GPU, SSD and other temperatures alongside both fans' current RPM.
- **Manual control** — drive all fans with one dial, or switch to per-fan mode and set each fan independently:
  - **Auto** — return a fan to the system's own logic.
  - **Custom** — hold a fixed RPM.
  - **Full speed** — pin a fan to its maximum.
- **Fan curves** — map any temperature sensor to a target RPM. Drag points directly on the graph, attach the curve to one fan or both, and let the fans ramp up exactly when you want them to. 3°C hysteresis prevents annoying on/off flapping around the knee of the curve.
- **Presets** — save your favourite configurations and switch between them instantly.
- **Menu-bar widget** — optional live temperature readout next to the fan icon, tied to any sensor you choose.
- **Start at login** — optional, and starts minimized if you want.

## Safety

Fan speed settings are enforced by a small privileged helper that runs as root — the same mechanism fan-control utilities on Macs have used for years. There's nothing dangerous about sensible speed limits: values are clamped to the fan's hardware minimum and maximum, and **every override reverts to system control automatically if the app quits or crashes** (including a failsafe watchdog inside the helper). If anything goes wrong, just quit the app and the fans return to Apple's defaults.

The first time you set a fan speed you'll be asked for your administrator password to install the helper — that's expected and safe.

## Install

Prebuilt releases and build instructions will live under **Releases**. Until then, build from source:

```bash
git clone <this-repo-url> && cd fancontrol
swift build -c release
./scripts/build.sh          # assembles build/FanControl.app
open build/FanControl.app
```

The bundled `scripts/install-helper.sh` can pre-install the privileged helper (it will prompt for your password); normally the app's **Install helper** button handles this for you.

## Using it

1. Launch FanControl — it appears in both your Dock and menu bar.
2. If a temperature widget isn't visible in the menu bar, enable it in **Settings**.
3. Open the **Fans** tab, then **Take control** once the helper is installed.
4. Pick a speed for all fans, flip "Apply to all fans" off to set each fan individually, or build a curve in the **Curves** tab.

Everything you adjust is remembered the next time you open the app.

## How it works

FanControl is built on the SMCs that every Mac exposes through IOKit:

- A **SwiftUI app** handles the UI, monitoring, presets and curves.
- A **privileged helper** (`com.fancontrol.helper`) is the only component allowed to write to the SMC; the app talks to it over XPC.
- Manual mode is re-asserted every ~300 ms to beat the system's thermal manager from reclaiming fan control, and a 10-second watchdog hands control back if the app ever stops responding.

SMC keys and the write protocol follow the same approach used by established macOS fan-control projects and work on current Apple Silicon hardware.

## Development

- `swift build` / `swift test` — build and run the test suite.
- `scripts/build.sh` — release build, `.app` bundle assembly, ad-hoc signing.
- `scripts/generate-icon.swift` — regenerate the app icon from `appicon.png`.

High-level layout:

```
Sources/
  SMCShim/          C shim wrapping the AppleSMC IOKit interface
  FanControlCore/   SMC reads/writes, fans, sensors, curves, presets
  FanControlApp/    SwiftUI GUI, settings, menu bar, XPC client
  FanControlHelper/ Root daemon that performs SMC writes
```

## License

MIT — see [LICENSE](LICENSE).