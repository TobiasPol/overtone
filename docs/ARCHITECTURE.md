# Overtone architecture

## Signal flow

```
 every app ──┐                                   ┌──────────────── private aggregate device ───────────────┐
             ├─► global process tap (muted) ──┐  │                                                          │
 Spotify ────┴─► per-app tap (muted) ─────────┼──┼─► IO proc (io.c, HAL real-time thread)                   │
                                              │  │     mix taps × per-app gain                              │
                                              │  │     preamp → biquad cascade (AutoEQ + EQ)                │
                                              │  │     stereo width → crossfeed → room reverb               │
                                              │  │     Audio Unit chain → analyzer ring                     │
                                              │  │     volume/balance (boost) → look-ahead limiter          │
                                              │  │     write L/R to preferred stereo channels ──► speakers  │
                                              └──┘                                                          │
                                                 └──────────────────────────────────────────────────────────┘
```

- **Global tap**: `CATapDescription(stereoGlobalTapButExcludeProcesses:)` excluding Overtone's own
  process object (to avoid feedback) and every process that has a per-app tap.
- **Per-app taps**: created for apps with an entry in the mixer settings. All helper processes of an
  app (browser renderers, for example) are grouped via the responsible-process SPI used by Activity Monitor.
- **Mute behaviour**: `.mutedWhenTapped`. Tapped processes are silent only while Overtone reads the tap,
  so quitting or crashing restores normal audio immediately.
- **Aggregate device**: private, with the real output as main and clock sub-device. Taps use drift
  compensation.

## Threads and data handoff

| Data | Producer | Consumer | Mechanism |
| --- | --- | --- | --- |
| `ot_params` snapshot (EQ coefficients, gains, effect settings) | main thread | IO thread | wait-free triple buffer (`params.c`) |
| Audio Unit chain | main thread | IO thread | atomic pointer swap + hazard pointer; the old chain is freed after the IO thread leaves it (`plugins.c`, `PluginHost.retire`) |
| Analyzer samples | IO thread | main thread (30 fps timer) | SPSC ring buffer (`analyzer.c`) |
| Output peaks | IO thread | main thread | relaxed atomics |

Coefficient changes are ramped linearly across one block, and gains are smoothed with an ~8 ms one-pole,
so slider moves don't click. Denormals are flushed (FPCR.FZ / MXCSR) at the start of every IO cycle.

## Lifecycle

1. `AudioEngine.setEnabled(true)`: preflight the TCC audio-capture permission (request if undetermined).
2. `rebuild()`: tear down → create taps → aggregate → `dsp.prepare(sampleRate)` →
   `PluginHost.prepare` (reconfigures AUs while IO is stopped) → publish parameters → start IO.
3. A health check 2.5 s later verifies that IO cycles are running. Outputs such as AirPlay that accept an
   aggregate but never run it are torn down, so the system isn't left silent.
4. Rebuild triggers (debounced): default output change, output sample-rate change or removal, wake from
   sleep, per-app tap set change. Process list changes that don't change the tap set are applied in
   place by updating the tap descriptions.

## Persistence

`~/Library/Application Support/Overtone/`:

- `settings.json`: all settings plus per-device EQ/correction profiles. Each section decodes
  independently, so one damaged section never wipes the rest.
- `presets.json`: user presets.
- `autoeq-index.md`: cached AutoEQ index (refreshed weekly). Profiles are fetched on demand from
  `raw.githubusercontent.com/jaakkopasanen/AutoEq`.

## Differences from eqMac

- No driver. Overtone uses process taps, so macOS 14.4+ is required, and the system volume keeps
  controlling the device's hardware volume. Overtone's own volume slider is an additional software gain
  (with boost). On outputs without hardware volume, the volume keys can drive it instead.
- Native SwiftUI interface instead of a web UI.
