import Foundation

/// When to look for a new release, and whether what came back is worth mentioning.
///
/// Kept separate from the network so the rules can be tested without one.
public enum UpdateCheckPolicy {
    /// Automatic checks happen at most once a day, so turning them on costs one request a day.
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isCheckDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck else { return true }
        // A clock that moved backwards (time zone, NTP, restored backup) must not postpone
        // checking until the original date is reached again.
        if now < lastCheck { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// `true` only when there is a genuinely newer version than the one running. A build newer
    /// than the latest release — someone running from source — is not an update.
    public static func isUpdate(latest: ReleaseVersion?, current: ReleaseVersion?) -> Bool {
        guard let latest, let current else { return false }
        return latest > current
    }
}
