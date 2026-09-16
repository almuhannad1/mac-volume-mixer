# Feasibility Investigation: Per-Application Volume on macOS

> Question: *Can macOS publicly support independent per-application output volume control?*
>
> Short answer: **Yes, since macOS 14.2**, through Core Audio **process taps** combined with a
> private **aggregate device**. There is still **no** direct per-process volume property like
> Windows has. macOS 14.2+ lets a process *mute another process's output and receive that audio
> itself*, so it can play the audio back at any gain. Before 14.2 the only options were virtual
> audio drivers or injecting code into `coreaudiod`.

Everything below was checked against the macOS 26 SDK headers on the build machine
(`CoreAudio.framework/Headers/AudioHardware.h`, `AudioHardwareTapping.h`, `CATapDescription.h`).
It was also exercised live with small probe programs (see [Evidence](#evidence-gathered-on-this-machine)).

---

## 1. How Windows does it

Windows routes every stream through the shared-mode **Audio Engine** (`audiodg.exe`). Streams are
grouped into **audio sessions**, and the engine applies a per-session gain *before* mixing:

| Windows Core Audio API | Purpose |
|---|---|
| `IAudioSessionManager2` → `IAudioSessionEnumerator` | enumerate sessions on an endpoint |
| `IAudioSessionControl2::GetProcessId` | map a session to a process |
| `ISimpleAudioVolume::SetMasterVolume / SetMute` | **per-session volume & mute** |
| `IAudioMeterInformation::GetPeakValue` | per-session peak meter |
| `IAudioSessionNotification` / `IAudioSessionEvents` | session added / state changed events |

EarTrumpet is a UI over these interfaces. The OS does the audio work.

## 2. How macOS works

On macOS each client process runs its own IO cycle against the **HAL** (`coreaudiod`) and writes
its samples into the device's mix buffer. The HAL has no per-client gain stage that other
processes can adjust.

| Capability | Public macOS API | Available |
|---|---|---|
| Enumerate processes using audio | `kAudioHardwarePropertyProcessObjectList` → `AudioProcess` objects (`kAudioProcessClassID`) | macOS 14.0+ |
| Process → PID / bundle ID | `kAudioProcessPropertyPID`, `kAudioProcessPropertyBundleID` | 14.0+ |
| Is the process playing? | `kAudioProcessPropertyIsRunningOutput` (listenable) | 14.0+ |
| Which device a process plays to | `kAudioProcessPropertyDevices` (output scope) | 14.0+ |
| **Set a process's volume** | **none** | ❌ never |
| Capture a process's output | `AudioHardwareCreateProcessTap(CATapDescription)` | **14.2+** |
| **Mute the original output while capturing** | `CATapDescription.muteBehavior = .muted / .mutedWhenTapped` | **14.2+** |
| Read a tap / play to hardware | private aggregate device with `kAudioAggregateDeviceTapListKey` + `AudioDeviceCreateIOProcIDWithBlock` | 14.2+ |
| Modify a live tap | `kAudioTapPropertyDescription` (settable) | 14.2+ |
| System output volume | `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`, `kAudioDevicePropertyVolumeScalar`, `kAudioDevicePropertyMute` | all |
| Output devices / default device | `kAudioHardwarePropertyDevices`, `kAudioHardwarePropertyDefaultOutputDevice` (settable) | all |
| Tap by bundle ID; auto-restore after relaunch | `CATapDescription.bundleIDs`, `.processRestoreEnabled` | macOS 26+ |

**Conclusion:** macOS lets us enumerate audio processes and *intercept* them. That is enough to
build real per-app volume. The attenuation, however, has to be applied by **our own process**:

```
App ──(muted at HAL by our tap)──╳──▶ speakers
 │
 └──▶ tap stream ──▶ our aggregate device IOProc ──(× gain)──▶ speakers
```

## 3. Candidate architectures

| # | Approach | Works for arbitrary apps? | Verdict |
|---|---|---|---|
| **A** | Direct per-process Core Audio volume | — | **Does not exist.** No HAL property or function sets another process's gain. |
| **B** | AudioUnit-based | No | AUs run inside a *host's* graph. You cannot insert an AU into another process's render chain without code injection. |
| **C** | Virtual audio device (AudioServerPlugIn driver, e.g. Background Music) | Yes | Works on old macOS. Requires an admin-installed driver in `/Library/Audio/Plug-Ins/HAL`, replaces the default output device, and adds a second clock domain. A driver bug can break all system audio. Not App Store compatible. |
| **D** | ScreenCaptureKit audio capture + re-playback | **No** | `SCStream` can *capture* an app's audio but cannot *mute* the original. The result is the app at full volume plus a second copy. Also needs the broader Screen Recording permission. Only useful for metering. |
| **E** | **Core Audio process taps + private aggregate device** | **Yes (macOS 14.2+)** | Public, user-space, no drivers. The HAL mutes the tapped process, we render it at our gain. **Chosen.** |

### Ranking

Scores: 5 = best.

| Criterion | E: Process taps | C: Virtual device | D: ScreenCaptureKit | B: AudioUnit | A: Direct |
|---|---|---|---|---|---|
| Reliability | 4 | 3 | 1 (can't attenuate) | 0 | 0 |
| Performance | 4 (only processed apps pay) | 3 (all audio via driver) | 2 | – | – |
| macOS compatibility | 3 (14.2+) | 5 | 4 (13+) | – | – |
| Security | 5 (user space, TCC-gated) | 2 (root-installed driver) | 4 | – | – |
| User permissions | 4 (System Audio Recording) | 3 (admin password) | 3 (Screen Recording) | – | – |
| Complexity | 3 | 1 | 3 | – | – |
| App Store | 3 (plausible, unverified) | 0 | 4 | – | – |
| Controls arbitrary apps | 5 | 5 | 0 | 0 | 0 |
| **Total** | **31** | 22 | 21 | – | – |

## 4. What this means in practice (limitations)

These are real limitations, and the app documents all of them in its UI and README:

1. **Minimum macOS 14.2.** The process-tap functions are marked `API_AVAILABLE(macos(14.2))`.
2. **Permission required.** Reading a tap requires the *System Audio Recording* TCC permission
   (`NSAudioCaptureUsageDescription`, shown under *Privacy & Security → Screen & System Audio
   Recording*). **No public API reports this permission's status.** The only public checks
   (`CGPreflightScreenCaptureAccess`) cover screen recording, not audio capture. The app
   therefore runs a **self-test**:
   - It taps its own process.
   - It plays an inaudible signal (−100 dBFS, 30 Hz).
   - It checks whether the signal comes back through the tap.

   Without permission, taps deliver silence. So the app *never* engages a muting tap until the
   self-test passes, otherwise apps would go silent.
3. **Processing is done by us.** An app below 100 % (or muted) is re-rendered by Mac Volume
   Mixer. That adds roughly one IO buffer of latency (≈10–20 ms), with drift-compensated
   resampling to the output device. Apps at 100 % and unmuted are **not tapped at all** (true
   bypass, zero cost).
4. **Engage/disengage glitch.** Moving an app below 100 % for the first time creates the tap. The
   app goes silent for ~50–200 ms while the aggregate device starts. The same short gap happens
   when a newly started app has its saved volume restored.
5. **Per-process, not per-tab.** Chrome renders *all* tabs in one audio-service process, so the
   HAL exposes one process. **Per-tab volume is impossible** from outside Chrome.
6. **WebKit (Safari, Mail, …).** WebKit apps play audio from the shared system XPC service
   `com.apple.WebKit.GPU`. Its path is inside `WebKit.framework`, not Safari.app. Linking that
   process back to Safari needs a private "responsible PID" API. Mac Volume Mixer shows these
   processes as **"Safari & Web Content"** rather than guessing.
7. **Helper processes.** Electron/Chromium apps (Discord, Slack, VS Code, Chrome, Brave) play audio
   from helper processes. On this machine that was `Discord Helper (Renderer)`. They are grouped
   into the owning `.app` by resolving the outermost `.app` bundle from the executable path
   (`proc_pidpath`, public libproc).
8. **Activity meter.** A real peak meter exists only for apps whose audio is flowing through a tap
   (non-default volume or muted). For bypassed apps the UI shows a truthful *"is playing"*
   indicator from `kAudioProcessPropertyIsRunningOutput`, not a fake level. We could tap every
   app just to meter it, but that would add latency to all audio.
9. **Onset while idle.** To save power the tap's IO is stopped ~15 s after an app goes quiet. The
   tap uses `.muted` so a muted app can never blast at full volume. The trade-off: the first
   few tens of milliseconds after the app starts again may be lost while IO restarts.
10. **Apps with their own device selection.** If an app plays to a specific device (e.g. Discord
    set to a headset), the engine follows `kAudioProcessPropertyDevices`. If an app's helpers use
    different devices at once, the system default output is used.
11. **Exclusive (hog mode) devices** cannot be shared by an aggregate device.
12. **App Store.** Process taps don't obviously conflict with the sandbox, but this has **not**
    been verified. The MVP targets Developer ID distribution.

## Evidence gathered on this machine

macOS 26.6.2, Apple Silicon, Command Line Tools / Swift 6.4.

**Process enumeration** (`kAudioHardwarePropertyProcessObjectList`) returned real entries:

- `com.hnc.Discord.helper.Renderer`: `run=1 out=1`, path inside `/Applications/Discord.app/…` → helper grouping required.
- `com.brave.Browser.helper`: path inside `Brave Browser.app/…`.
- `com.apple.WebKit.GPU`: path in `/System/Volumes/Preboot/Cryptexes/OS/System/Library/Frameworks/WebKit.framework/…` → cannot be attributed to Safari.
- `systemsoundserverd`: system alert sounds.
- The probe itself: our own process must be excluded.

**Tap spike:**

| Call | Status |
|---|---|
| `AudioHardwareCreateProcessTap` (stereo mixdown, private) | `0` → format Float32, 48 kHz, 2 ch, interleaved (flags `0x9`) |
| `AudioHardwareCreateAggregateDevice` (speakers as main sub-device + tap) | `0` → 1 input stream (tap), 1 output stream (speakers), both Float32 |
| `kAudioTapPropertyDescription` | settable, set returned `0` |
| `AudioHardwareDestroyAggregateDevice`, `AudioHardwareDestroyProcessTap` | `0`, `0` |

**Devices:** the machine also has *Background Music* (a virtual-device mixer, approach C) and a
Microsoft Teams loopback driver installed. Both are proof that approach C exists, and both must
appear as ordinary selectable outputs.

**Not verifiable from this session:**

- The TCC prompt and actual audible attenuation. These need a person to approve the permission
  and listen.
- The real-app test matrix in [TESTING.md](TESTING.md). It must be run manually.
