import CoreAudio
import Darwin
import MixerCore

/// Observes Core Audio's process objects (macOS 14+) and publishes coalesced snapshots.
@MainActor
public final class AudioProcessMonitor {
    public private(set) var processes: [AudioProcessInfo] = []
    public var onChange: (([AudioProcessInfo]) -> Void)?

    private var listListener: PropertyListener?
    private var processListeners: [AudioObjectID: [PropertyListener]] = [:]
    private var refreshPending = false

    public init() {}

    public func start() {
        guard listListener == nil else { return }
        listListener = PropertyListener(
            objectID: HAL.systemObject,
            address: HAL.address(kAudioHardwarePropertyProcessObjectList)
        ) { [weak self] in self?.scheduleRefresh() }
        refresh()
    }

    /// Core Audio often fires several notifications in a burst (list + running state);
    /// coalesce them into one snapshot per main-queue turn.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { [weak self] in
            guard let self else { return }
            refreshPending = false
            refresh()
        }
    }

    private func refresh() {
        let objectIDs = Self.readProcessObjectIDs()
        updateListeners(for: objectIDs)
        let snapshot = objectIDs.compactMap(Self.readProcess)
        guard snapshot != processes else { return }
        processes = snapshot
        onChange?(snapshot)
    }

    private func updateListeners(for objectIDs: [AudioObjectID]) {
        let current = Set(objectIDs)
        for id in processListeners.keys where !current.contains(id) {
            processListeners[id] = nil
        }
        let handler: @MainActor () -> Void = { [weak self] in self?.scheduleRefresh() }
        for id in current where processListeners[id] == nil {
            processListeners[id] = [
                PropertyListener(objectID: id, address: HAL.address(kAudioProcessPropertyIsRunningOutput), handler: handler),
                PropertyListener(objectID: id, address: HAL.address(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput), handler: handler),
            ]
        }
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
            isRunningOutput: (try? HAL.readBool(objectID, HAL.address(kAudioProcessPropertyIsRunningOutput))) ?? false,
            outputDeviceIDs: (try? HAL.readArray(objectID, HAL.address(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput),
                                                 of: AudioObjectID.self)) ?? []
        )
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
