import CoreAudio
import MixerCore

/// Thin, typed wrappers around the `AudioObject*PropertyData` C functions.
enum HAL {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func hasProperty(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    /// Reads a fixed-size (POD) property.
    static func read<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) throws -> T {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        try CoreAudioError.check(status, "Reading \(describe(address)) of object \(object)")
        return value
    }

    /// Reads a fixed-size property using a qualifier (e.g. translating a PID).
    static func read<T, Q>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, qualifier: Q, initial: T) throws -> T {
        var address = address
        var qualifier = qualifier
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { qualifierPointer in
            withUnsafeMutablePointer(to: &value) {
                AudioObjectGetPropertyData(object, &address, UInt32(MemoryLayout<Q>.size), qualifierPointer, &size, $0)
            }
        }
        try CoreAudioError.check(status, "Reading \(describe(address)) of object \(object)")
        return value
    }

    static func readArray<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, of _: T.Type) throws -> [T] {
        var address = address
        var size: UInt32 = 0
        try CoreAudioError.check(
            AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size),
            "Sizing \(describe(address)) of object \(object)"
        )
        let capacity = Int(size) / MemoryLayout<T>.stride
        guard capacity > 0 else { return [] }
        return try [T](unsafeUninitializedCapacity: capacity) { buffer, initializedCount in
            let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
            initializedCount = status == noErr ? min(capacity, Int(size) / MemoryLayout<T>.stride) : 0
            try CoreAudioError.check(status, "Reading \(describe(address)) of object \(object)")
        }
    }

    static func readString(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) throws -> String {
        let value: Unmanaged<CFString>? = try read(object, address, initial: nil)
        guard let value else { throw CoreAudioError.missingObject("\(describe(address)) of object \(object) is null") }
        return value.takeRetainedValue() as String
    }

    static func readBool(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) throws -> Bool {
        try read(object, address, initial: UInt32(0)) != 0
    }

    static func write<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, value: T) throws {
        var address = address
        var value = value
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        try CoreAudioError.check(status, "Writing \(describe(address)) of object \(object)")
    }

    static func describe(_ address: AudioObjectPropertyAddress) -> String {
        let selector = FourCharCode.string(from: address.mSelector) ?? "\(address.mSelector)"
        let scope = FourCharCode.string(from: address.mScope) ?? "\(address.mScope)"
        return "'\(selector)'/'\(scope)'/\(address.mElement)"
    }

    // MARK: Common queries

    static func streamFormats(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> [AudioStreamBasicDescription] {
        let streams = (try? readArray(device, address(kAudioDevicePropertyStreams, scope: scope), of: AudioStreamID.self)) ?? []
        return streams.compactMap {
            try? read($0, address(kAudioStreamPropertyVirtualFormat), initial: AudioStreamBasicDescription())
        }
    }

    static func isFloat32LinearPCM(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mBitsPerChannel == 32
            && format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    }
}
