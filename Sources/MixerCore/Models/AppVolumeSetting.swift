/// What the mixer should actually do for one app on one output device: the values the panel
/// shows and the tap engine applies.
public struct EffectiveAppSetting: Hashable, Sendable {
    public var volume: Double
    public var isMuted: Bool
    /// Device the user pinned this app to, or `nil` to follow the app/system output.
    public var routeDeviceUID: String?

    public static let `default` = EffectiveAppSetting(volume: 1, isMuted: false)

    public init(volume: Double, isMuted: Bool, routeDeviceUID: String? = nil) {
        self.volume = AppVolumeSetting.clamp(volume)
        self.isMuted = isMuted
        self.routeDeviceUID = routeDeviceUID
    }

    /// `true` when the app would sound exactly as it does without the mixer: unity gain, unmuted
    /// and playing where it would anyway — so no tap is needed.
    public var isDefault: Bool { routeDeviceUID == nil && !isMuted && volume >= 0.9995 }

    public var percent: Int { Int((volume * 100).rounded()) }
}

/// The stored preferences for one application.
///
/// `volume`/`isMuted` are the app's baseline, used for any output device without its own entry.
/// Every field added after 1.0 decodes optionally, so settings written by 1.0 load unchanged and
/// no migration is required.
public struct AppVolumeSetting: Codable, Hashable, Sendable {
    /// A level remembered for one specific output device.
    public struct DeviceLevel: Codable, Hashable, Sendable {
        public var volume: Double
        public var isMuted: Bool

        public init(volume: Double, isMuted: Bool) {
            self.volume = AppVolumeSetting.clamp(volume)
            self.isMuted = isMuted
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1,
                isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
            )
        }

        public var isDefault: Bool { !isMuted && volume >= 0.9995 }
    }

    public private(set) var volume: Double
    public private(set) var isMuted: Bool
    /// UID of the device this app is pinned to, independent of the system output.
    public private(set) var outputDeviceUID: String?
    /// Last known name of that device, shown while it is disconnected.
    public private(set) var outputDeviceName: String?
    public private(set) var perDevice: [String: DeviceLevel]

    public static let `default` = AppVolumeSetting()

    public init(
        volume: Double = 1,
        isMuted: Bool = false,
        outputDeviceUID: String? = nil,
        outputDeviceName: String? = nil,
        perDevice: [String: DeviceLevel] = [:]
    ) {
        self.volume = Self.clamp(volume)
        self.isMuted = isMuted
        self.outputDeviceUID = outputDeviceUID
        self.outputDeviceName = outputDeviceName
        self.perDevice = perDevice
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1,
            isMuted: try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false,
            outputDeviceUID: try container.decodeIfPresent(String.self, forKey: .outputDeviceUID),
            outputDeviceName: try container.decodeIfPresent(String.self, forKey: .outputDeviceName),
            perDevice: try container.decodeIfPresent([String: DeviceLevel].self, forKey: .perDevice) ?? [:]
        )
    }

    /// The values to apply on `deviceUID`. Pass `nil` when per-device memory is off or the
    /// current device is unknown, which falls back to the baseline.
    public func effective(onDeviceUID deviceUID: String?) -> EffectiveAppSetting {
        if let deviceUID, let level = perDevice[deviceUID] {
            return EffectiveAppSetting(volume: level.volume, isMuted: level.isMuted, routeDeviceUID: outputDeviceUID)
        }
        return EffectiveAppSetting(volume: volume, isMuted: isMuted, routeDeviceUID: outputDeviceUID)
    }

    /// Changes the level for one device, mirroring it into the baseline so devices that have
    /// never been used still start from the user's most recent choice.
    public mutating func setLevel(volume newVolume: Double? = nil, isMuted newMuted: Bool? = nil, forDeviceUID deviceUID: String?) {
        let current = effective(onDeviceUID: deviceUID)
        volume = Self.clamp(newVolume ?? current.volume)
        isMuted = newMuted ?? current.isMuted
        if let deviceUID {
            perDevice[deviceUID] = DeviceLevel(volume: volume, isMuted: isMuted)
        }
    }

    public mutating func setRoute(deviceUID: String?, deviceName: String? = nil) {
        outputDeviceUID = deviceUID
        outputDeviceName = deviceUID == nil ? nil : (deviceName ?? outputDeviceName)
    }

    public mutating func clearPerDeviceLevels() {
        perDevice.removeAll()
    }

    /// `true` when nothing about this app differs from stock macOS behaviour, so the entry can be
    /// dropped from storage entirely.
    public var isStorageDefault: Bool {
        outputDeviceUID == nil && !isMuted && volume >= 0.9995 && perDevice.values.allSatisfy(\.isDefault)
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 1 }
        return min(max(value, 0), 1)
    }
}
