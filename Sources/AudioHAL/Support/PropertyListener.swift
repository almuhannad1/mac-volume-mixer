import CoreAudio
import Foundation

/// Registers a Core Audio property listener for as long as the object is alive.
///
/// Callbacks are delivered on the main queue and forwarded to a main-actor handler.
public final class PropertyListener {
    private let objectID: AudioObjectID
    private var address: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock
    private let isRegistered: Bool

    init(objectID: AudioObjectID, address: AudioObjectPropertyAddress, handler: @escaping @MainActor () -> Void) {
        self.objectID = objectID
        self.address = address
        self.block = { _, _ in
            MainActor.assumeIsolated { handler() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &self.address, DispatchQueue.main, block)
        isRegistered = status == noErr
        if !isRegistered {
            HALLog.hal.error("Adding listener \(HAL.describe(address), privacy: .public) on object \(objectID) failed: \(status)")
        }
    }

    deinit {
        guard isRegistered else { return }
        AudioObjectRemovePropertyListenerBlock(objectID, &address, DispatchQueue.main, block)
    }
}
