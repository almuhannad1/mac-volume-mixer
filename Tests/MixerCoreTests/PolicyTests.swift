import Foundation
import Testing
@testable import MixerCore

struct PolicyTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    private func session(_ id: String, playing: Bool, kind: AppIdentity.Kind = .application, path: String? = "/Applications/A.app") -> AudioAppSession {
        AudioAppSession(
            identity: AppIdentity(id: id, bundleIdentifier: id, bundlePath: path, displayName: id, kind: kind),
            processes: [AudioProcessInfo(objectID: 1, pid: 1, bundleID: id, executablePath: nil, isRunningOutput: playing)]
        )
    }

    @Test func tapsOnlyNonDefaultSettingsWithAuthorization() {
        #expect(!TapPolicy.shouldEngage(setting: .default, captureAuthorized: true))
        #expect(TapPolicy.shouldEngage(setting: EffectiveAppSetting(volume: 0.3, isMuted: false), captureAuthorized: true))
        #expect(TapPolicy.shouldEngage(setting: EffectiveAppSetting(volume: 1, isMuted: true), captureAuthorized: true))
        #expect(!TapPolicy.shouldEngage(setting: EffectiveAppSetting(volume: 1, isMuted: true), captureAuthorized: false))
    }

    @Test func routingNeedsATapEvenAtFullVolume() {
        // The audio has to be re-rendered onto another device, so unity gain still needs a tap.
        let routed = EffectiveAppSetting(volume: 1, isMuted: false, routeDeviceUID: "airpods")
        #expect(!routed.isDefault)
        #expect(TapPolicy.shouldEngage(setting: routed, captureAuthorized: true))
        #expect(!TapPolicy.shouldEngage(setting: routed, captureAuthorized: false))
    }

    @Test func soloAndDuckingEngageTapsOnUntouchedApps() {
        #expect(TapPolicy.shouldEngage(setting: .default, captureAuthorized: true, isForcedByMixer: true))
        #expect(!TapPolicy.shouldEngage(setting: .default, captureAuthorized: true, isForcedByMixer: false))
        // Neither can engage a tap without capture access, which would silence nothing.
        #expect(!TapPolicy.shouldEngage(setting: .default, captureAuthorized: false, isForcedByMixer: true))
    }

    @Test func callDuckingTriggersOnUserFacingMicUseOnly() {
        func micSession(_ id: String, kind: AppIdentity.Kind, path: String?) -> AudioAppSession {
            AudioAppSession(
                identity: AppIdentity(id: id, bundleIdentifier: id, bundlePath: path, displayName: id, kind: kind),
                processes: [AudioProcessInfo(objectID: 1, pid: 1, bundleID: id, executablePath: path,
                                             isRunningOutput: false, isRunningInput: true)]
            )
        }
        // Siri's recogniser holds the mic more or less permanently; it must never duck the Mac.
        let daemon = micSession("com.apple.CoreSpeech", kind: .process, path: nil)
        #expect(DuckPolicy.duckTrigger(in: [daemon]) == nil)

        let discord = micSession("com.hnc.Discord", kind: .application, path: "/Applications/Discord.app")
        #expect(DuckPolicy.duckTrigger(in: [daemon, discord]) == "com.hnc.Discord")

        let silent = session("com.brave.Browser", playing: true)
        #expect(DuckPolicy.duckTrigger(in: [silent]) == nil)
    }

    @Test func duckingSparesTheAppOnTheCall() {
        #expect(DuckPolicy.levelMultiplier(for: "discord", trigger: "discord", level: 0.3) == 1)
        #expect(DuckPolicy.levelMultiplier(for: "brave", trigger: "discord", level: 0.3) == 0.3)
        #expect(DuckPolicy.levelMultiplier(for: "brave", trigger: nil, level: 0.3) == 1)
        #expect(DuckPolicy.levelMultiplier(for: "brave", trigger: "discord", level: 5) == 1)
    }

    /// Dimming an app that is silent, or one the user cannot see, would engage a tap and a
    /// realtime IO thread to turn down audio nobody is hearing.
    @Test func duckingOnlyTouchesAppsWorthATap() {
        let playing = session("com.brave.Browser", playing: true)
        #expect(DuckPolicy.levelMultiplier(for: playing, trigger: "discord", level: 0.3) == 0.3)

        let silent = session("com.brave.Browser", playing: false)
        #expect(DuckPolicy.levelMultiplier(for: silent, trigger: "discord", level: 0.3) == 1)

        let daemon = session("com.apple.someDaemon", playing: true, kind: .process, path: nil)
        #expect(DuckPolicy.levelMultiplier(for: daemon, trigger: "discord", level: 0.3) == 1)

        // The app on the call keeps its own level even while playing.
        let onCall = session("discord", playing: true)
        #expect(DuckPolicy.levelMultiplier(for: onCall, trigger: "discord", level: 0.3) == 1)
    }

    /// A notification re-reads only the volatile properties, so the cached immutable ones must
    /// survive untouched.
    @Test func volatileUpdateKeepsImmutableFields() {
        let original = AudioProcessInfo(objectID: 7, pid: 42, bundleID: "com.brave.Browser",
                                        executablePath: "/Applications/Brave.app/Contents/MacOS/Brave",
                                        isRunningOutput: false, isRunningInput: false, outputDeviceIDs: [])
        let updated = original.updating(isRunningOutput: true, isRunningInput: true, outputDeviceIDs: [3])

        #expect(updated.objectID == 7)
        #expect(updated.pid == 42)
        #expect(updated.bundleID == "com.brave.Browser")
        #expect(updated.executablePath == original.executablePath)
        #expect(updated.isRunningOutput)
        #expect(updated.isRunningInput)
        #expect(updated.outputDeviceIDs == [3])
    }

    @Test func routeResolutionPrefersPinnedThenAppThenSystem() {
        let available: Set<String> = ["speakers", "airpods"]
        let pinned = RoutePolicy.resolve(pinnedDeviceUID: "airpods", availableDeviceUIDs: available,
                                         appDeviceUID: "usb", systemDefaultDeviceUID: "speakers")
        #expect(pinned == RoutePolicy.Resolution(deviceUID: "airpods", isPinnedDeviceMissing: false))

        let appChosen = RoutePolicy.resolve(pinnedDeviceUID: nil, availableDeviceUIDs: available,
                                            appDeviceUID: "usb", systemDefaultDeviceUID: "speakers")
        #expect(appChosen == RoutePolicy.Resolution(deviceUID: "usb", isPinnedDeviceMissing: false))

        let systemDefault = RoutePolicy.resolve(pinnedDeviceUID: nil, availableDeviceUIDs: available,
                                                appDeviceUID: nil, systemDefaultDeviceUID: "speakers")
        #expect(systemDefault.deviceUID == "speakers")
    }

    @Test func disconnectedPinnedDeviceFallsBackButIsRemembered() {
        let resolution = RoutePolicy.resolve(pinnedDeviceUID: "airpods", availableDeviceUIDs: ["speakers"],
                                             appDeviceUID: nil, systemDefaultDeviceUID: "speakers")
        #expect(resolution == RoutePolicy.Resolution(deviceUID: "speakers", isPinnedDeviceMissing: true))

        // The stored preference is untouched, so reconnecting restores the route.
        var setting = AppVolumeSetting()
        setting.setRoute(deviceUID: "airpods", deviceName: "AirPods Pro")
        #expect(setting.outputDeviceUID == "airpods")
        #expect(setting.outputDeviceName == "AirPods Pro")
        #expect(!setting.isStorageDefault)
    }

    @Test func activityTrackerRecordsStopTimeAndGrace() {
        var tracker = ActivityTracker()
        tracker.update(playingIDs: ["spotify"], now: t0)
        #expect(tracker.isPlaying("spotify"))
        #expect(tracker.graceExpiry("spotify", within: 10, now: t0) == nil)

        tracker.update(playingIDs: [], now: t0.addingTimeInterval(60))
        let stop = t0.addingTimeInterval(60)
        #expect(tracker.stoppedPlayingAt("spotify") == stop)
        #expect(tracker.wasActive("spotify", within: 10, now: stop.addingTimeInterval(9)))
        #expect(!tracker.wasActive("spotify", within: 10, now: stop.addingTimeInterval(10)))
        #expect(tracker.graceExpiry("spotify", within: 10, now: stop.addingTimeInterval(1)) == stop.addingTimeInterval(10))
        #expect(tracker.graceExpiry("spotify", within: 10, now: stop.addingTimeInterval(11)) == nil)

        #expect(TapPolicy.shouldRunIO(sessionID: "spotify", activity: tracker, now: stop.addingTimeInterval(5)))
        #expect(!TapPolicy.shouldRunIO(sessionID: "spotify", activity: tracker, now: stop.addingTimeInterval(TapPolicy.ioIdleGrace + 1)))

        tracker.update(playingIDs: ["spotify"], now: stop.addingTimeInterval(100))
        #expect(tracker.stoppedPlayingAt("spotify") == nil)

        tracker.prune(keeping: [])
        #expect(!tracker.isPlaying("spotify"))
    }

    @Test func neverPlayedAppIsNotActive() {
        let tracker = ActivityTracker()
        #expect(!tracker.wasActive("x", within: 100, now: t0))
        #expect(!TapPolicy.shouldRunIO(sessionID: "x", activity: tracker, now: t0))
    }

    @Test func listVisibilityRules() {
        let filter = AppListFilter(showInactiveApps: false)
        let tracker = ActivityTracker()
        #expect(filter.isVisible(session("a", playing: true), isCustomised: false, activity: tracker, now: t0))
        #expect(!filter.isVisible(session("a", playing: false), isCustomised: false, activity: tracker, now: t0))
        #expect(filter.isVisible(session("a", playing: false), isCustomised: true, activity: tracker, now: t0))
        #expect(!filter.isVisible(session("d", playing: false, kind: .process, path: nil), isCustomised: true, activity: tracker, now: t0))
        #expect(AppListFilter(showInactiveApps: true).isVisible(session("a", playing: false), isCustomised: false, activity: tracker, now: t0))

        var lingering = ActivityTracker()
        lingering.update(playingIDs: ["a"], now: t0)
        lingering.update(playingIDs: [], now: t0)
        #expect(filter.isVisible(session("a", playing: false), isCustomised: false, activity: lingering, now: t0.addingTimeInterval(5)))
        #expect(!filter.isVisible(session("a", playing: false), isCustomised: false, activity: lingering,
                                  now: t0.addingTimeInterval(AppListFilter.lingerInterval + 1)))
    }

    @Test func searchMatchesNameAndBundleID() {
        let identity = AppIdentity(id: "com.spotify.client", bundleIdentifier: "com.spotify.client", bundlePath: nil,
                                   displayName: "Spotify", kind: .application)
        #expect(AppListFilter.matches(identity, query: ""))
        #expect(AppListFilter.matches(identity, query: "  spot "))
        #expect(AppListFilter.matches(identity, query: "com.spotify"))
        #expect(!AppListFilter.matches(identity, query: "chrome"))
    }

    @Test func volumeGlyphs() {
        #expect(VolumeGlyph.speakerSymbol(volume: 0.5, isMuted: true) == "speaker.slash.fill")
        #expect(VolumeGlyph.speakerSymbol(volume: 0, isMuted: false) == "speaker.slash.fill")
        #expect(VolumeGlyph.speakerSymbol(volume: 0.2, isMuted: false) == "speaker.wave.1.fill")
        #expect(VolumeGlyph.speakerSymbol(volume: 0.5, isMuted: false) == "speaker.wave.2.fill")
        #expect(VolumeGlyph.speakerSymbol(volume: 1, isMuted: false) == "speaker.wave.3.fill")
    }
}
