/// All audio processes that belong to one `AppIdentity`.
public struct AudioAppSession: Hashable, Sendable, Identifiable {
    public let identity: AppIdentity
    public let processes: [AudioProcessInfo]

    public init(identity: AppIdentity, processes: [AudioProcessInfo]) {
        self.identity = identity
        self.processes = processes.sorted { $0.objectID < $1.objectID }
    }

    public var id: String { identity.id }

    /// Sorted process object IDs, suitable for a `CATapDescription`.
    public var processObjectIDs: [UInt32] { processes.map(\.objectID) }

    public var isProducingOutput: Bool { processes.contains { $0.isRunningOutput } }

    /// The device this app plays to, when all of its playing processes agree on exactly one.
    /// `nil` means "use the system default output".
    public var preferredOutputDeviceID: UInt32? {
        let playing = processes.filter(\.isRunningOutput)
        let deviceSets = Set(playing.map(\.outputDeviceIDs).filter { !$0.isEmpty })
        guard deviceSets.count == 1, let devices = deviceSets.first, devices.count == 1 else { return nil }
        return devices[0]
    }
}
