import Foundation

/// Decides which sessions appear in the mixer.
public struct AppListFilter: Sendable {
    /// Rows stay visible this long after playback stops, so the list doesn't jump around.
    public static let lingerInterval: TimeInterval = 30

    public var showInactiveApps: Bool

    public init(showInactiveApps: Bool) {
        self.showInactiveApps = showInactiveApps
    }

    public func isVisible(_ session: AudioAppSession, setting: AppVolumeSetting, activity: ActivityTracker, now: Date) -> Bool {
        if session.isProducingOutput { return true }
        if activity.wasActive(session.id, within: Self.lingerInterval, now: now) { return true }
        guard session.identity.isUserFacing else { return false }
        // Keep apps the user has turned down or muted reachable, so they can be restored.
        if !setting.isDefault { return true }
        return showInactiveApps
    }

    /// Case- and diacritic-insensitive match on the name or bundle identifier.
    public static func matches(_ identity: AppIdentity, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return identity.displayName.localizedStandardContains(trimmed)
            || (identity.bundleIdentifier?.localizedStandardContains(trimmed) ?? false)
    }
}
