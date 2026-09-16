import CoreAudio
import MixerCore

/// Tracks the system's audio output devices and the default output device.
@MainActor
public final class AudioDeviceService {
    /// Every device with output streams (including hidden/aggregate ones), keyed by ID.
    public private(set) var allOutputDevices: [AudioOutputDevice] = []
    /// Devices suitable for the output picker.
    public private(set) var selectableDevices: [AudioOutputDevice] = []
    public private(set) var defaultOutputDeviceID = AudioObjectID(kAudioObjectUnknown)

    public var onChange: (() -> Void)?

    private var listeners: [PropertyListener] = []

    public init() {}

    public var defaultOutputDevice: AudioOutputDevice? {
        allOutputDevices.first { $0.id == defaultOutputDeviceID }
    }

    public func device(id: AudioObjectID) -> AudioOutputDevice? {
        allOutputDevices.first { $0.id == id }
    }

    public func start() {
        guard listeners.isEmpty else { return }
        let handler: @MainActor () -> Void = { [weak self] in self?.refresh() }
        listeners = [
            PropertyListener(objectID: HAL.systemObject, address: HAL.address(kAudioHardwarePropertyDevices), handler: handler),
            PropertyListener(objectID: HAL.systemObject, address: HAL.address(kAudioHardwarePropertyDefaultOutputDevice), handler: handler),
        ]
        refresh()
    }

    public func refresh() {
        let devices = Self.readOutputDevices()
        let defaultID = (try? HAL.read(HAL.systemObject, HAL.address(kAudioHardwarePropertyDefaultOutputDevice),
                                       initial: AudioObjectID(kAudioObjectUnknown))) ?? AudioObjectID(kAudioObjectUnknown)
        guard devices != allOutputDevices || defaultID != defaultOutputDeviceID else { return }
        allOutputDevices = devices
        selectableDevices = OutputDeviceFilter.selectable(devices, excludingUIDPrefix: HALConstants.aggregateUIDPrefix)
        defaultOutputDeviceID = defaultID
        HALLog.devices.info("Output devices: \(devices.map(\.name), privacy: .public); default: \(defaultID)")
        onChange?()
    }

    public func setDefaultOutputDevice(_ deviceID: AudioObjectID) throws {
        try HAL.write(HAL.systemObject, HAL.address(kAudioHardwarePropertyDefaultOutputDevice), value: deviceID)
    }

    nonisolated public static func readOutputDevices() -> [AudioOutputDevice] {
        let ids = (try? HAL.readArray(HAL.systemObject, HAL.address(kAudioHardwarePropertyDevices), of: AudioObjectID.self)) ?? []
        return ids.compactMap(readOutputDevice)
    }

    nonisolated static func readOutputDevice(_ id: AudioObjectID) -> AudioOutputDevice? {
        let channels = HAL.streamFormats(id, scope: kAudioObjectPropertyScopeOutput)
            .reduce(0) { $0 + Int($1.mChannelsPerFrame) }
        guard channels > 0, let uid = try? HAL.readString(id, HAL.address(kAudioDevicePropertyDeviceUID)) else { return nil }
        let name = (try? HAL.readString(id, HAL.address(kAudioObjectPropertyName))) ?? uid
        let transport = (try? HAL.read(id, HAL.address(kAudioDevicePropertyTransportType), initial: UInt32(0))) ?? 0
        let hidden = (try? HAL.readBool(id, HAL.address(kAudioDevicePropertyIsHidden))) ?? false
        return AudioOutputDevice(id: id, uid: uid, name: name, transportType: AudioTransportType(code: transport),
                                 outputChannelCount: channels, isHidden: hidden)
    }
}
