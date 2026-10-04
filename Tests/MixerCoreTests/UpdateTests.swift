import Foundation
import Testing
@testable import MixerCore

struct UpdateTests {
    @Test func versionsParseFromTagsAndBundleStrings() {
        #expect(ReleaseVersion("v1.2.0") == ReleaseVersion(major: 1, minor: 2, patch: 0))
        #expect(ReleaseVersion("1.2.0") == ReleaseVersion(major: 1, minor: 2, patch: 0))
        #expect(ReleaseVersion("1.2") == ReleaseVersion(major: 1, minor: 2, patch: 0))
        #expect(ReleaseVersion("2") == ReleaseVersion(major: 2, minor: 0, patch: 0))
        // Pre-release and build metadata are ignored for comparison.
        #expect(ReleaseVersion("1.3.0-beta.1") == ReleaseVersion(major: 1, minor: 3, patch: 0))
        #expect(ReleaseVersion("  v1.1.1  ") == ReleaseVersion(major: 1, minor: 1, patch: 1))

        #expect(ReleaseVersion("") == nil)
        #expect(ReleaseVersion("development build") == nil)
        #expect(ReleaseVersion("v") == nil)
        #expect(ReleaseVersion("1.x.0") == nil)
    }

    /// The reason this is a type and not a string comparison.
    @Test func versionsCompareNumericallyNotAlphabetically() {
        #expect(ReleaseVersion("1.10.0")! > ReleaseVersion("1.9.0")!)
        #expect(ReleaseVersion("1.2.10")! > ReleaseVersion("1.2.9")!)
        #expect(ReleaseVersion("2.0.0")! > ReleaseVersion("1.99.99")!)
        #expect(ReleaseVersion("1.2.0")! == ReleaseVersion("1.2.0")!)
        #expect(!(ReleaseVersion("1.2.0")! > ReleaseVersion("1.2.0")!))
    }

    @Test func onlyAGenuinelyNewerReleaseCounts() {
        let current = ReleaseVersion("1.2.0")
        #expect(UpdateCheckPolicy.isUpdate(latest: ReleaseVersion("1.3.0"), current: current))
        #expect(!UpdateCheckPolicy.isUpdate(latest: ReleaseVersion("1.2.0"), current: current))
        // Running a build newer than the latest release (from source) is not an update.
        #expect(!UpdateCheckPolicy.isUpdate(latest: ReleaseVersion("1.1.1"), current: current))
        // An unreadable version on either side must never claim an update.
        #expect(!UpdateCheckPolicy.isUpdate(latest: nil, current: current))
        #expect(!UpdateCheckPolicy.isUpdate(latest: ReleaseVersion("1.3.0"), current: nil))
    }

    @Test func automaticChecksHappenAtMostDaily() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(UpdateCheckPolicy.isCheckDue(lastCheck: nil, now: now))
        #expect(!UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(-60), now: now))
        #expect(!UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(-23 * 3600), now: now))
        #expect(UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(-24 * 3600), now: now))

        // A clock that moved backwards must not postpone checking indefinitely.
        #expect(UpdateCheckPolicy.isCheckDue(lastCheck: now.addingTimeInterval(3600), now: now))
    }
}
