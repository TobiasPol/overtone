# Overtone

A native, system-wide equalizer for macOS that lives only in the menu bar. It
re-creates [eqMac](https://github.com/bitgapp/eqMac) feature-for-feature,
**including every eqMac Pro feature**, without installing an audio driver.

![Overtone](docs/screenshots/popover-equalizer-advanced.png)

## Features

| Feature | eqMac | Overtone |
| --- | --- | --- |
| System-wide audio processing | Free | ✅ |
| Volume booster (up to 400 %) | Free | ✅ |
| Balance, on every device including HDMI | Free | ✅ |
| Volume keys for HDMI / DisplayPort outputs (with on-screen HUD) | Free | ✅ |
| Basic EQ: bass, mids, treble | Free | ✅ |
| Advanced EQ: fixed 10 bands plus preamp, 22 built-in presets | Free | ✅ |
| Expert EQ: up to 32 parametric bands (8 filter types, frequency, gain, Q), drag bands on the graph | **Pro** | ✅ |
| AutoEQ headphone correction (8,800+ measured headphones) | **Pro** | ✅ |
| Spectrum analyzer and live frequency-response graph | **Pro** | ✅ |
| Spatial audio: room simulation (small room to cathedral), stereo width, headphone crossfeed | **Pro** | ✅ |
| Volume mixer: per-app volume, mute and boost | **Pro** | ✅ |
| Audio Unit hosting (any AU effect, with its own editor window) | **Pro** | ✅ |
| Custom UI: accent colours, hide sections | **Pro** | ✅ |
| Presets: save, import, export (JSON and Equalizer APO `ParametricEQ.txt`) | ✅ | ✅ |
| Remember EQ and correction per output device | | ✅ |
| Look-ahead limiter and auto-gain clipping protection | | ✅ |
| Launch at login | ✅ | ✅ |

## How it works

eqMac routes audio through a virtual audio driver. Overtone instead uses
**Core Audio process taps** (macOS 14.2+):

1. A global tap captures every app's output, except Overtone's own, and mutes
   the original while Overtone is reading it.
2. A private aggregate device combines that tap with your real output device.
3. Overtone's real-time C engine processes the audio and plays it on the same
   device: EQ, spatial effects, plugins, volume and limiter.

So there's nothing to install, and nothing kernel-level to uninstall. If
Overtone quits or crashes, macOS unmutes the apps immediately and sound plays
normally. Apps with a custom mixer volume get their own tap, so their level can
be set independently.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the details.

## Requirements

- macOS 14.4 or later (Apple Silicon or Intel)
- Xcode 16 or later (Swift 6 toolchain) to build

## Build and run

```bash
scripts/build-app.sh            # → build/Overtone.app (release, ad-hoc signed)
open build/Overtone.app
```

Or build, quit any running copy and relaunch a debug build in one step:

```bash
scripts/run.sh
```

To install it, copy `build/Overtone.app` to `/Applications`. Then turn on
**Open Overtone at login** in Settings.

### Permissions

| Permission | Why | When |
| --- | --- | --- |
| **System Audio Recording** | Capture system audio to process it | First time processing starts |
| **Accessibility** (optional) | Capture volume keys for outputs without hardware volume | Only if you use that option |

Ad-hoc signed builds get a new code signature on every rebuild, so macOS asks
for permission again. Set `CODESIGN_IDENTITY` in `.env` to a real signing
identity to avoid that. To reset the permission:

```bash
tccutil reset AudioCapture com.tobiaspol.overtone
```

## Usage

- **Left-click** the menu bar icon to open Overtone. **Right-click** for quick
  on/off, Settings and Quit.
- **Equalizer:** switch between Basic, Advanced and Expert. In Expert mode, drag
  the numbered handles on the graph, or type exact values. Double-click any
  slider or knob to reset it.
- **Headphones:** search for your model and click it to apply the AutoEQ
  correction. Use **Edit in Expert EQ** to fine-tune it band by band.
- **Effects:** pick a room preset or shape your own, widen or narrow the stereo
  image, and enable crossfeed for headphones.
- **Mixer:** apps appear while they play. Adjusted apps stay listed while they run.
- **Plugins:** add any installed Audio Unit effect. They run in order after the
  EQ and spatial stage.
- **Footer:** Overtone volume (up to the boost limit), balance, and the system
  output device.

## Development

```bash
swift build                 # debug build
swift test                  # DSP and app unit tests
scripts/check.sh            # all quality gates (CI runs this)
scripts/install-hooks.sh    # run the gates before every commit
.build/debug/Overtone --snapshot docs/screenshots   # render every screen to PNG
```

### Environment variables

Read by `scripts/build-app.sh` from `.env` (copy `.env.example`):

| Variable | Purpose |
| --- | --- |
| `CODESIGN_IDENTITY` | Signing identity (`-` = ad-hoc) |
| `BUNDLE_ID` | Bundle identifier of the built app |
| `VERSION` | Marketing version |
| `UNIVERSAL` | `1` builds an arm64 + x86_64 binary |

### Project layout

```
src/OvertoneDSP/     C real-time engine (IO proc, EQ, effects, limiter, plugin chain)
src/Overtone/
  App/               entry point, status item, controller
  Audio/             Core Audio: devices, process taps, aggregate device, engine
  DSP/               Swift bridge, parameter builder, response curve, spectrum analyzer
  Models/            settings and persistence
  Presets/ AutoEQ/ Mixer/ Plugins/ System/
  UI/                SwiftUI views
tests/               Swift Testing suites
scripts/             build, run, icon and quality-gate scripts
```

## Troubleshooting

- **No sound after turning Overtone on:** check the menu for an error. Some
  outputs, such as AirPlay, can't be wrapped in an aggregate device. Overtone
  detects this and falls back to unprocessed audio. Pick another output.
- **Permission was denied:** open **System Settings → Privacy & Security →
  Screen & System Audio Recording**, allow Overtone, then click **Try Again**.
- **Clipping when boosting:** keep the limiter on, or enable **Auto Gain**.

## Credits

- Headphone measurements and correction profiles: [AutoEQ](https://github.com/jaakkopasanen/AutoEq)
  by Jaakko Pasanen.
- Room simulation based on Jezar's public-domain Freeverb.
- Filters from Robert Bristow-Johnson's *Audio EQ Cookbook*.
- Inspired by [eqMac](https://github.com/bitgapp/eqMac). Overtone is an
  independent project and shares no code with it.
