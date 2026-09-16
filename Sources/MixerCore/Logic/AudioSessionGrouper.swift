import Foundation


/// Groups Core Audio process objects into per-app sessions.
public enum AudioSessionGrouper {
    /// - Parameters:
    ///   - ownPID: this process, which must never tap itself.
    ///   - ownBundleID: the mixer's own bundle identifier. Any process sharing it is excluded too,
    ///     so a second instance (or a command-line build) can never be routed through a tap —
    ///     that would mute the very output the mixer renders for every other app.
    public static func group(
        _ processes: [AudioProcessInfo],
        excludingPID ownPID: Int32,
        ownBundleID: String? = nil,
        resolver: AppIdentityResolver
    ) -> [AudioAppSession] {
        var buckets: [String: (identity: AppIdentity, processes: [AudioProcessInfo])] = [:]
        for process in processes where process.pid != ownPID {
            let identity = resolver.identity(for: process)
            if let ownBundleID, identity.bundleIdentifier == ownBundleID || identity.id == ownBundleID {
                continue
            }
            buckets[identity.id, default: (identity, [])].processes.append(process)
        }
        return buckets.values
            .map { AudioAppSession(identity: $0.identity, processes: $0.processes) }
            .sorted {
                let order = $0.identity.displayName.localizedStandardCompare($1.identity.displayName)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }
}
