import Foundation

/// Remembers when each app last stopped playing, so rows don't vanish the instant a sound ends
/// and tap IO can idle down after a grace period.
public struct ActivityTracker: Sendable {
    public private(set) var playingIDs: Set<String> = []
    private var stoppedAt: [String: Date] = [:]

    public init() {}

    public mutating func update(playingIDs newPlayingIDs: Set<String>, now: Date) {
        for id in playingIDs.subtracting(newPlayingIDs) {
            stoppedAt[id] = now
        }
        for id in newPlayingIDs {
            stoppedAt[id] = nil
        }
        playingIDs = newPlayingIDs
    }

    public func isPlaying(_ id: String) -> Bool { playingIDs.contains(id) }

    /// When the app stopped playing, or `nil` if it is playing or was never seen playing.
    public func stoppedPlayingAt(_ id: String) -> Date? { stoppedAt[id] }

    /// Playing now, or stopped less than `interval` ago.
    public func wasActive(_ id: String, within interval: TimeInterval, now: Date) -> Bool {
        if isPlaying(id) { return true }
        guard let stopped = stoppedAt[id] else { return false }
        return now.timeIntervalSince(stopped) < interval
    }

    /// When `wasActive(_:within:now:)` will flip to `false`, if it is currently a pending grace period.
    public func graceExpiry(_ id: String, within interval: TimeInterval, now: Date) -> Date? {
        guard !isPlaying(id), let stopped = stoppedAt[id] else { return nil }
        let expiry = stopped.addingTimeInterval(interval)
        return expiry > now ? expiry : nil
    }

    /// Drops history for apps that no longer exist.
    public mutating func prune(keeping ids: Set<String>) {
        stoppedAt = stoppedAt.filter { ids.contains($0.key) }
        playingIDs.formIntersection(ids)
    }
}
