# Testing

## Automated

```bash
swift test
```

35 tests across 6 suites cover `MixerCore`: gain rendering (ramp, channel mapping, pre-gain peak),
volume curve, meter scale and ballistics, atomics, app identity resolution (helper → owning app,
WebKit, daemons), session grouping (including never listing the mixer itself), tap/visibility policies, activity tracking, search,
persistence (round-trip, pruning, disabled persistence, corrupt data, clamping) and device
filtering.

Core Audio, taps and the UI are **not** covered automatically: they need real hardware, the
System Audio Recording permission and a person listening.

## Checks that do not need the permission

```bash
swift build && .build/debug/MacVolumeMixer --list-sessions
```

Expect the real output devices and the grouped audio sessions (helpers folded into their app).

```bash
.build/debug/MacVolumeMixer --self-test
```

Builds a complete tap pipeline (process tap → private aggregate device → IOProc) against the real
default output device and tears it down without starting IO. Verified working on macOS 26.6.2:
object creation, Float32 format negotiation, aggregate composition and clean teardown, leaving no
stray aggregate devices behind.

```bash
scripts/build-app.sh
open -n "build/Mac Volume Mixer.app" --args --disable-taps
```

Expect a menu bar icon, a working master slider, working output switching, the app list updating
live, and a banner saying per-app volume is disabled.

## Manual matrix (requires the permission)

Grant *Privacy & Security → Screen & System Audio Recording → System Audio Recording Only* for
Mac Volume Mixer, then press **Check Again**.

### Core behaviour

| # | Scenario | Expected |
|---|---|---|
| 1 | Play audio in Chrome, Spotify, Discord, VS Code, VLC, Safari and trigger a system alert sound | Each appears as its own row, named and with its icon; Chrome/Discord/VS Code helpers appear **once**, under the app |
| 2 | Chrome at 100 %, Spotify at 30 % | Only Spotify is quieter; Chrome and the master volume are unchanged |
| 3 | Discord muted | Discord is silent, everything else unaffected |
| 4 | Move the master slider | All audio scales; per-app sliders keep their positions |
| 5 | Set Spotify to 0 %, then back up | Silence, then audio returns |
| 6 | Watch the meter of a processed app | Level follows the actual audio, including when muted (activity is measured pre-gain); apps at 100 % show the "playing" marker, not a meter |
| 7 | Set volumes, quit and relaunch the app | Volumes are restored |
| 8 | Set Spotify to 30 %, quit Spotify, relaunch it, play | Row returns at 30 % and is attenuated |
| 9 | Search with six or more apps listed | The field appears and filters by name and bundle ID |
| 10 | Stop all audio in an app | The row stays ~30 s, then disappears (unless *Show inactive applications* is on or it is muted/turned down) |

### Devices

| # | Scenario | Expected |
|---|---|---|
| 11 | Switch output in the panel while a processed app plays | Audio follows the new device within a moment; attenuation is preserved |
| 12 | Connect AirPods | System switches; processed apps keep their volumes; if a preferred device is set, it is selected |
| 13 | Disconnect AirPods | Playback returns to speakers with volumes intact and no stuck silence |
| 14 | Select an HDMI/display output with no software volume | Master slider disables with an explanatory line; per-app volumes still work |
| 15 | Set a preferred device in Settings, disconnect and reconnect it | It is re-selected on reconnect and shown as "(not connected)" while absent |

### Robustness

| # | Scenario | Expected |
|---|---|---|
| 16 | Sleep and wake the Mac | Taps rebuild ~2 s after wake; audio and attenuation work |
| 17 | Restart the Mac (with *Launch at login*) | The app starts, permission is remembered, volumes are restored |
| 18 | Force-quit Mac Volume Mixer (`kill -9`) while an app is muted | **That app's audio returns to normal** — taps die with the process |
| 19 | Deny the permission | Banner explains; master volume and device switching still work; **no app is left silent** |
| 20 | Revoke the permission while running | Reopen the panel; the app must not leave apps muted (quit and relaunch if the banner appears) |
| 21 | Leave the app running idle for an hour with the panel closed | CPU stays near 0 %; no growth in memory |

### Assumptions worth confirming explicitly

These follow from the design and the headers but could not be verified in a headless session:

1. **Idle-resume (row 6 + 8).** Taps use `.muted`, and their IO is stopped 15 s after an app goes
   quiet. When the app plays again, macOS should report `kAudioProcessPropertyIsRunningOutput`,
   which restarts IO. Confirm a muted app stays silent and a turned-down app resumes at the right
   volume, losing at most a few tens of milliseconds of onset.
2. **Bluetooth sample rates.** With AirPods in HFP (16/24 kHz) mode, confirm no pitch or glitch
   artifacts. The engine logs a notice if the tap and device rates differ.
3. **Multichannel devices.** On a 5.1/7.1 device, confirm processed audio plays through the front
   pair only.
4. **Hardened runtime.** A Developer ID build includes `com.apple.security.device.audio-input`
   defensively; confirm taps still work, and remove it if they do without it.

### Log inspection

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "dev.macvolumemixer.MacVolumeMixer"' --style compact
```

Categories: `hal`, `devices`, `processes`, `taps`, `permission`, `mixer`, `app`. Every Core Audio
failure is logged with its four-character `OSStatus`, e.g. `'!obj' (560947818)`.
