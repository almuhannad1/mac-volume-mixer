# Testing

## Automated

```bash
scripts/test.sh
```

Plain `swift test` also works where Xcode is installed. With only the Command Line Tools, SwiftPM
may fail to find the swift-testing macro plugin; `scripts/test.sh` passes its path explicitly.

54 tests across 7 suites cover `MixerCore`: gain rendering (ramp, channel mapping, pre-gain peak),
volume curve, meter scale and ballistics, atomics, app identity resolution (helper → owning app,
WebKit, daemons), session grouping (including never listing the mixer itself), tap/visibility policies, activity tracking, search,
persistence (round-trip, pruning, disabled persistence, corrupt data, clamping), per-app output
routing (priority order, disconnected fallback, storage of a route at unity gain), per-device
levels, backward compatibility with settings written by 1.0, call ducking (only user-facing apps
trigger it; the app on the call keeps its own level; silent and non-user-facing apps are never
dimmed, because that would engage a tap for nothing), incremental process updates preserving a
process's immutable fields, per-channel gains for balance and mono, device filtering, and release
version parsing and comparison (numeric, so 1.10.0 beats 1.9.0; an unreadable version never claims
an update; automatic checks are due at most daily and survive a clock moving backwards).

Core Audio, taps and the UI are **not** covered automatically: they need real hardware, the
System Audio Recording permission and a person listening.

## Checks that do not need the permission

```bash
swift build && .build/debug/MacVolumeMixer --list-sessions
```

Expect the real output devices and the grouped audio sessions (helpers folded into their app).

```bash
"/Applications/Mac Volume Mixer.app/Contents/MacOS/MacVolumeMixer" --check-permission
```

Answers "is per-app volume actually working?" in one line. macOS attributes capture access to the
calling bundle, so run the copy inside the installed app, not the bare build product.

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

## Performance diagnostics

These answer "is it using too much CPU, memory or battery?" with numbers rather than opinions.

```bash
.build/release/MacVolumeMixer --measure-scan
```

Times the two halves of a Core Audio notification. Expect roughly:

```
HAL process scan:      12.92 ms for 20 audio processes   # what a full rescan would cost
Identity + grouping:   0.61 ms for 16 sessions
One object's volatile state: 0.31 ms
Per notification: 0.91 ms now, vs 13.52 ms with a full rescan
```

Notifications fire on every sound any app makes, so the per-notification figure is the app's main
non-realtime cost. If it ever approaches the full-rescan figure, incremental updating has regressed.

```bash
.build/release/MacVolumeMixer --measure-taps <count> <bufferFrames|device> <seconds>
```

Runs `count` taps **on this process**, unmuted, so no other app is affected, and reports CPU,
wake-ups per second and memory footprint. Wake-ups should match `sampleRate / bufferFrames × count`
almost exactly; that figure, not CPU, is what drains a battery. Measured on an M3 Pro at 48 kHz:

| Taps | Buffer | CPU | Wake-ups/s |
|---|---|---|---|
| 0 | — | 0.01 % | 1 |
| 1 | 512 (device default) | 0.19 % | 94 |
| 1 | 256 (low-latency) | 0.13 % | 188 |
| 4 | 512 | 0.55 % | 377 |
| 8 | 256 | 0.64 % | 1501 |

This is also the fastest way to catch a realtime lifetime bug: the harness deliberately passes
temporary `AtomicFloat` cells, so if `TapResources` ever stops owning them, several taps running
for a few seconds will trap in `libmalloc` with "memory corruption of free block".

```bash
"/Applications/Mac Volume Mixer.app/Contents/MacOS/MacVolumeMixer" --check-updates
```

Runs one update check and prints the result. It uses a throwaway preferences domain, so it neither
reads nor disturbs real settings and does not count as the once-a-day automatic check. Run the copy
**inside the app bundle**: the bare binary has no `Info.plist`, so it has no version to compare and
says so rather than guessing.

```bash
.build/release/MacVolumeMixer --watch-sessions 15
```

Prints every change the process monitor reports. Play a sound part-way through: expect the process
to appear, then flip to playing, then disappear. Verifies that incremental updates still track
apps starting and stopping audio.

```bash
top -l 2 -s 5 -pid $(pgrep -x MacVolumeMixer) -stats pid,cpu,th,mem,idlew,power
```

Idle with nothing turned down, expect ~0 % CPU, ~37 MB, 6 threads and only a couple of idle
wake-ups a second. `footprint -p <pid>` also reports `phys_footprint_peak`, which is worth checking
against a long-running session.

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
| 22 | Right-click an app → *Play through* → a second device | Only that app moves; its row shows `→ Device`; everything else stays on the system output |
| 23 | Route an app, then unplug that device | The row shows *(not connected)*, audio continues on the system output; replugging moves it back |
| 24 | Route an app at 100 % | It still moves device (routing needs a tap even at unity gain) |
| 25 | Solo an app | Every other app goes silent, the soloed row is highlighted; clearing solo restores each app's own level exactly |
| 26 | Quit the soloed app while solo is on | Solo clears itself; nothing stays silent |
| 27 | Set 40 % on speakers, switch to headphones, set 15 %, switch back | 40 % returns; turning off *Remember a level per output device* uses one shared level again |
| 28 | Scroll over the menu bar icon; middle-click it | Master volume changes ~2 % per notch; middle-click toggles mute; both stop when the General setting is off |

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
| 29 | Log out and back in with an app configured below 100 % | The tap engages by itself; if Core Audio has no default device yet at login, the check retries at 5 s, 15 s, 60 s and 5 min, and a device appearing re-checks immediately — it must never stay inert for the session |
| 36 | Deny the permission, then leave the app running for an hour with the panel closed | **No repeating probe.** `log stream` shows no further "self-test" lines, and the audio device is not woken every few minutes. Opening the panel or pressing Check Again probes once, on demand |
| 30 | Hover the menu bar icon while access is missing | The tooltip says per-app volume needs System Audio Recording |
| 31 | Play music, then start a Discord/Zoom/FaceTime call | Music fades down over ~250 ms, the panel says which app is on the call, and it fades back when the call ends |
| 32 | Leave Siri or dictation listening while music plays | **Nothing dims** — system speech services hold the mic permanently and must never trigger ducking |
| 33 | Start a call in the browser you are also playing music in | That app keeps its own level (it is the call), others dim |
| 34 | Right-click an app → *Balance* → Left, then *Mono* | Audio moves to the left ear; mono folds both channels; both engage a tap even at 100 % |
| 35 | Turn on *Low-latency processing* and watch the log while an app is processed | `Buffer for <app> set to 256 frames`; with it off (the default) the device keeps its own buffer and no such line appears |
| 38 | Fresh install, open **Settings → General** | *Check for updates automatically* is **off**, and nothing has contacted the network — confirm with Little Snitch, `nettop`, or simply that no check has run |
| 39 | Press **Check Now** with the setting still off | One check runs and reports "Up to date" or offers the newer version; the setting stays off |
| 40 | Turn the setting on, quit and relaunch twice within a day | Only **one** request is made: the second launch sees the stored date and skips |
| 41 | Turn the setting on with networking disabled | Nothing is reported in the background; a manual **Check Now** explains the failure |
| 42 | Install an older version, then check | The newer version is offered as a link to the release page; **nothing installs itself** |
| 43 | Update over an existing copy, then reopen the panel | Per-app volumes are exactly as they were; re-grant System Audio Recording if macOS asks |
| 37 | Start a call while several apps are listed but silent | Only apps **actually playing** show "Dimmed for a call" and gain a tap; silent rows are untouched (check with `--list-sessions` that no extra aggregate devices exist) |

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
