# Overtone

## Overview
Menu-bar-only macOS system-wide equalizer: an eqMac clone with all Pro features (Expert parametric EQ,
AutoEQ headphone correction, spectrum analyzer, spatial audio, per-app volume mixer, Audio Unit hosting).
It captures system audio with Core Audio process taps (no driver), processes it in a real-time C engine
and plays it on the real output device through a private aggregate device.

## Tech Stack
- Language: Swift 6 toolchain (Swift 5 language mode) + C11 for the real-time DSP
- Framework: SwiftUI + AppKit (NSStatusItem/NSPopover), Core Audio, AudioToolbox, AVFoundation, Accelerate
- Build: Swift Package Manager; `scripts/build-app.sh` assembles and signs the .app bundle
- Tests: Swift Testing (`import Testing`)
- Database: none (JSON files in ~/Library/Application Support/Overtone)

## Commands
- `swift build` — Debug build
- `scripts/build-app.sh [release|debug]` — Build `build/Overtone.app`
- `scripts/run.sh` — Build a debug bundle and launch it
- `scripts/package-release.sh <version>` — Universal release zip + SHA-256 (used by the Release workflow)
- `scripts/update-cask.sh <version> <sha256> <tap-dir>` — Write the Homebrew cask into a homebrew-tap checkout
- `scripts/make-artwork.sh` — Regenerate the app icon and README images from `LogoMark`
- `scripts/notarize.sh <app> <zip>` — Notarize + staple (called by package-release.sh when credentials exist)
- `build/Overtone.app/Contents/MacOS/Overtone --check-plugins` — Host every installed AU effect and render a test tone
- `.build/debug/Overtone --detect [--speed N] <audio files…>` — Play files as a playlist through the music type detector and print each auto preset switch
- `swift test` — Run tests
- `scripts/check.sh` — All quality gates (warnings-as-errors build, tests, size limits, secret scan)
- `swiftformat --lint src tests` — Check code style
- `.build/debug/Overtone --snapshot <dir>` — Render every screen to PNG without audio

## Architecture
- `src/OvertoneDSP` (C): everything reachable from the HAL IO proc (`io.c`). Rules: no allocation, no
  locks, no Objective-C/Swift calls, no blocking. Parameters arrive via the triple buffer in `params.c`;
  the Audio Unit chain via the hazard-pointer swap in `plugins.c`. Chain order: taps mix → detector tap → preamp →
  biquad cascade → width → crossfeed → reverb → AU plugins → analyzer tap → volume/balance → limiter.
- `src/Overtone/Audio`: `ProcessTap` (global tap excluding Overtone and per-app taps, muted when tapped),
  `AggregateDevice` (output device + taps), `AudioPipeline` (one running graph), `AudioEngine`
  (permission, device following, debounced rebuilds, health check).
- `src/Overtone/Detection`: auto preset mode. `SoundClassifier` streams the pre-EQ detector ring into
  Apple's SoundAnalysis classifier; `MusicTypeDetector` votes over time (in audio seconds) and prefers
  Music.app's genre when Music is the only app playing; `AutoPresetController` applies built-in presets
  while the user's own EQ stays in `AppState.manualEqualizer` (what gets saved).
- `src/Overtone/DSP/ParamsBuilder.swift`: pure translation from settings to the C `ot_params` snapshot.
- `src/Overtone/App/AppController.swift`: wires `AppState` changes to the engine, persistence, per-device
  profiles, mixer taps and volume keys.
- UI: SwiftUI views in `src/Overtone/UI`, all models injected via `AppEnvironment`.

## Environment Variables
Build-time only (`.env`, see `.env.example`): `CODESIGN_IDENTITY`, `BUNDLE_ID`, `VERSION`, `UNIVERSAL`.
Optional: `NOTARY_KEYCHAIN_PROFILE` (local notarization via a saved notarytool profile).
CI secrets (optional, names only, never commit values): `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`
(Developer ID signing), `NOTARY_KEY_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` (notarization),
`TAP_DEPLOY_KEY` (write deploy key that lets the Release workflow update `TobiasPol/homebrew-tap`).
All are created by `scripts/setup-release-signing.sh` (run by a human; it never prints values).

## Conventions
- No file over 300 lines, no function over 50 lines (`scripts/check.sh` enforces the file limit).
- Keep the IO path in C. Anything the audio thread reads must be published as a full snapshot.
- `ot_dsp_prepare()` only while IO is stopped (`AudioEngine.launch`).
- Never commit `.env`.
