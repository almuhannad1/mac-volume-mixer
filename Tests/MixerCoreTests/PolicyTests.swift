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
        #expect(TapPolicy.shouldEngage(setting: AppVolumeSetting(volume: 0.3), captureAuthorized: true))
        #expect(TapPolicy.shouldEngage(setting: AppVolumeSetting(volume: 1, isMuted: true), captureAuthorized: true))
        #expect(!TapPolicy.shouldEngage(setting: AppVolumeSetting(volume: 1, isMuted: true), captureAuthorized: false))
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
        #expect(filter.isVisible(session("a", playing: true), setting: .default, activity: tracker, now: t0))
        #expect(!filter.isVisible(session("a", playing: false), setting: .default, activity: tracker, now: t0))
        #expect(filter.isVisible(session("a", playing: false), setting: AppVolumeSetting(isMuted: true), activity: tracker, now: t0))
        #expect(!filter.isVisible(session("d", playing: false, kind: .process, path: nil), setting: AppVolumeSetting(isMuted: true), activity: tracker, now: t0))
        #expect(AppListFilter(showInactiveApps: true).isVisible(session("a", playing: false), setting: .default, activity: tracker, now: t0))

        var lingering = ActivityTracker()
        lingering.update(playingIDs: ["a"], now: t0)
        lingering.update(playingIDs: [], now: t0)
        #expect(filter.isVisible(session("a", playing: false), setting: .default, activity: lingering, now: t0.addingTimeInterval(5)))
        #expect(!filter.isVisible(session("a", playing: false), setting: .default, activity: lingering,
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
