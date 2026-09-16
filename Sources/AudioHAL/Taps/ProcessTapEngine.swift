import CoreAudio
import Foundation
import MixerCore

/// Applies an independent volume to one application by routing it through a process tap.
///
/// Main-actor callers describe the desired state (`apply`, `shutdown`); the engine performs the
/// actual Core Audio work on its own serial queue, in order, so slow HAL calls never block the UI.
/// Gain changes and peak readings go through lock-free atomics and never touch the HAL.
public final class ProcessTapEngine: @unchecked Sendable {
    public struct Target: Equatable, Sendable {
        public var processObjectIDs: [AudioObjectID]
        public var outputDeviceUID: String

        public init(processObjectIDs: [AudioObjectID], outputDeviceUID: String) {
            self.processObjectIDs = processObjectIDs
            self.outputDeviceUID = outputDeviceUID
        }
    }

    public let appID: String
    private let displayName: String
    private let gain = AtomicFloat(0)
    private let peak = AtomicFloat(0)
    private let queue: DispatchQueue

    private static let engineQueue = DispatchQueue(label: "dev.macvolumemixer.tap-engines", qos: .userInitiated)

    /// Called on the main actor when Core Audio rejects a tap operation.
    @MainActor public var onFailure: ((ProcessTapEngine, CoreAudioError) -> Void)?

    @MainActor private var requestedTarget: Target?
    @MainActor private var requestedRunning = false

    // Confined to `queue`.
    private var resources: TapResources?
    private var wantsRunning = false

    public init(appID: String, displayName: String) {
        self.appID = appID
        self.displayName = displayName
        queue = DispatchQueue(label: "dev.macvolumemixer.tap-engine.\(appID)", target: Self.engineQueue)
    }

    /// Linear gain (see `VolumeCurve`). Safe to call at slider rate.
    public func setGain(_ value: Float) {
        gain.store(value)
    }

    /// Highest pre-gain sample since the previous call.
    public func takePeak() -> Float {
        peak.exchange(0)
    }

    /// Requests a tap for `target`. IO runs only while `running` is true, to save power when
    /// the app is silent. Redundant requests are ignored.
    @MainActor
    public func apply(target: Target, running: Bool) {
        if target != requestedTarget {
            requestedTarget = target
            queue.async { self.configure(target) }
        }
        if running != requestedRunning {
            requestedRunning = running
            queue.async { self.setRunning(running) }
        }
    }

    /// Recreates every Core Audio object, e.g. after sleep/wake when device IDs may be stale.
    @MainActor
    public func rebuild() {
        guard let target = requestedTarget else { return }
        queue.async {
            self.teardown()
            self.configure(target)
        }
    }

    /// Releases the tap; the app's audio returns to normal.
    @MainActor
    public func shutdown() {
        requestedTarget = nil
        requestedRunning = false
        queue.async { self.release() }
    }

    /// Synchronous variant used at application termination.
    @MainActor
    public func shutdownAndWait() {
        requestedTarget = nil
        requestedRunning = false
        queue.sync { release() }
    }

    // MARK: - Queue-confined work

    private func configure(_ target: Target) {
        if let resources, resources.outputDeviceUID == target.outputDeviceUID {
            guard resources.processObjectIDs != target.processObjectIDs else { return }
            do {
                try resources.updateProcesses(target.processObjectIDs)
                return
            } catch {
                HALLog.taps.notice("Rebuilding tap for \(self.displayName, privacy: .public) after a failed process update")
            }
        }

        teardown()
        guard !target.processObjectIDs.isEmpty else { return }
        do {
            let newResources = try TapResources.make(
                name: displayName,
                processObjectIDs: target.processObjectIDs,
                outputDeviceUID: target.outputDeviceUID,
                muteBehavior: .muted,
                gain: gain,
                peak: peak
            )
            resources = newResources
            if wantsRunning {
                try newResources.start()
            }
        } catch {
            teardown()
            report(error)
        }
    }

    private func setRunning(_ running: Bool) {
        wantsRunning = running
        guard let resources else { return }
        do {
            if running {
                try resources.start()
            } else {
                resources.stop()
                peak.store(0)
            }
        } catch {
            teardown()
            report(error)
        }
    }

    private func release() {
        wantsRunning = false
        teardown()
    }

    private func teardown() {
        resources?.destroy()
        resources = nil
        peak.store(0)
    }

    private func report(_ error: Error) {
        let coreAudioError = error as? CoreAudioError ?? .missingObject(String(describing: error))
        Task { @MainActor in
            self.onFailure?(self, coreAudioError)
        }
    }
}
