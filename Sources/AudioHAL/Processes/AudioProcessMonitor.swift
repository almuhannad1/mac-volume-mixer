import CoreAudio
import Darwin
import MixerCore

/// Observes Core Audio's process objects (macOS 14+) and publishes coalesced snapshots.
///
/// Every field of a process object is a separate IPC round trip to `coreaudiod`, so reading them
/// all costs roughly 13 ms for 20 audio processes. Notifications arrive whenever *any* app starts
/// or stops playing — including every system alert sound — so rescanning everything each time was
/// the app's largest CPU cost. Instead, the immutable fields (pid, bundle ID, executable path) are
/// read once per process object, and a notification re-reads only the three volatile properties of
/// the one object that actually changed.
@MainActor
public final class AudioProcessMonitor {
    public private(set) var processes: [AudioProcessInfo] = []
    public var onChange: (([AudioProcessInfo]) -> Void)?

    private var listListener: PropertyListener?
    private var processListeners: [AudioObjectID: [PropertyListener]] = [:]
    /// Last known state of each live process object.
    private var known: [AudioObjectID: AudioProcessInfo] = [:]
    /// Object IDs in the order the HAL lists them, so the published snapshot is stable.
    private var order: [AudioObjectID] = []
    /// Objects a notification says to re-read.
    private var changedObjectIDs: Set<AudioObjectID> = []
    private var needsListScan = false
    private var updatePending = false

    public init() {}

    public func start() {
        guard listListener == nil else { return }
        listListener = PropertyListener(
            objectID: HAL.systemObject,
            address: HAL.address(kAudioHardwarePropertyProcessObjectList)
        ) { [weak self] in self?.listChanged() }
        scanList()
        publish()
    }

    private func listChanged() {
        needsListScan = true
        scheduleUpdate()
    }

    private func objectChanged(_ objectID: AudioObjectID) {
        changedObjectIDs.insert(objectID)
        scheduleUpdate()
    }

    /// Core Audio often fires several notifications in a burst (list + running state);
    /// coalesce them into one snapshot per main-queue turn.
    private func scheduleUpdate() {
        guard !updatePending else { return }
        updatePending = true
        Task { [weak self] in
            guard let self else { return }
            updatePending = false
            applyPendingChanges()
        }
    }

    private func applyPendingChanges() {
        if needsListScan {
            needsListScan = false
            scanList()
        }
        let changed = changedObjectIDs
        changedObjectIDs.removeAll()
        for objectID in changed {
            refreshVolatileState(of: objectID)
        }
        publish()
    }

    /// Re-reads the process list: adds listeners and a full record for objects that are new, drops
    /// the ones that have gone, and leaves existing records alone — their immutable fields cannot
    /// have changed, and their volatile ones arrive through their own listeners.
    private func scanList() {
        let objectIDs = Self.readProcessObjectIDs()
        order = objectIDs
        let current = Set(objectIDs)
        // Materialise the keys: the loop body mutates the dictionary it would otherwise be viewing.
        for objectID in Array(known.keys) where !current.contains(objectID) {
            known[objectID] = nil
            processListeners[objectID] = nil
        }
        for objectID in objectIDs where known[objectID] == nil {
            // Listen before reading, so a change landing during the read is not missed.
            installListeners(for: objectID)
            guard let info = Self.readProcess(objectID) else {
                processListeners[objectID] = nil // the process exited mid-scan
                continue
            }
            known[objectID] = info
        }
    }

    private func installListeners(for objectID: AudioObjectID) {
        let handler: @MainActor () -> Void = { [weak self] in self?.objectChanged(objectID) }
        processListeners[objectID] = [
            PropertyListener(objectID: objectID, address: HAL.address(kAudioProcessPropertyIsRunningOutput), handler: handler),
            PropertyListener(objectID: objectID, address: HAL.address(kAudioProcessPropertyIsRunningInput), handler: handler),
            PropertyListener(objectID: objectID, address: HAL.address(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput), handler: handler),
        ]
    }

    /// Three reads instead of a whole rescan.
    private func refreshVolatileState(of objectID: AudioObjectID) {
        guard let existing = known[objectID] else { return }
        known[objectID] = existing.updating(
            isRunningOutput: Self.readRunningOutput(objectID),
            isRunningInput: Self.readRunningInput(objectID),
            outputDeviceIDs: Self.readOutputDevices(objectID)
        )
    }

    private func publish() {
        let snapshot = order.compactMap { known[$0] }
        guard snapshot != processes else { return }
        processes = snapshot
        onChange?(snapshot)
    }

    nonisolated public static func readProcesses() -> [AudioProcessInfo] {
        readProcessObjectIDs().compactMap(readProcess)
    }

    nonisolated static func readProcessObjectIDs() -> [AudioObjectID] {
        do {
            return try HAL.readArray(HAL.systemObject, HAL.address(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self)
        } catch {
            HALLog.processes.error("Unable to read the audio process list: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    nonisolated static func readProcess(_ objectID: AudioObjectID) -> AudioProcessInfo? {
        // Processes can exit between listing and reading; skip them quietly.
        guard let pid = try? HAL.read(objectID, HAL.address(kAudioProcessPropertyPID), initial: pid_t(0)) else { return nil }
        return AudioProcessInfo(
            objectID: objectID,
            pid: pid,
            bundleID: try? HAL.readString(objectID, HAL.address(kAudioProcessPropertyBundleID)),
            executablePath: executablePath(for: pid),
            isRunningOutput: readRunningOutput(objectID),
            isRunningInput: readRunningInput(objectID),
            outputDeviceIDs: readOutputDevices(objectID)
        )
    }

    nonisolated static func readRunningOutput(_ objectID: AudioObjectID) -> Bool {
        (try? HAL.readBool(objectID, HAL.address(kAudioProcessPropertyIsRunningOutput))) ?? false
    }

    nonisolated static func readRunningInput(_ objectID: AudioObjectID) -> Bool {
        (try? HAL.readBool(objectID, HAL.address(kAudioProcessPropertyIsRunningInput))) ?? false
    }

    nonisolated static func readOutputDevices(_ objectID: AudioObjectID) -> [AudioObjectID] {
        (try? HAL.readArray(objectID, HAL.address(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput),
                            of: AudioObjectID.self)) ?? []
    }

    nonisolated static func executablePath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The HAL process object that represents the given PID, if it has connected to Core Audio.
    nonisolated public static func processObjectID(forPID pid: pid_t) -> AudioObjectID? {
        let id = try? HAL.read(HAL.systemObject, HAL.address(kAudioHardwarePropertyTranslatePIDToProcessObject),
                               qualifier: pid, initial: AudioObjectID(kAudioObjectUnknown))
        return id == AudioObjectID(kAudioObjectUnknown) ? nil : id
    }
}
