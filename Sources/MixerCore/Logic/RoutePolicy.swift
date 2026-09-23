/// Chooses which output device an app's audio should be rendered onto.
public enum RoutePolicy {
    public struct Resolution: Equatable, Sendable {
        public var deviceUID: String?
        /// The user pinned a device that is not currently connected, so the fallback is in use.
        public var isPinnedDeviceMissing: Bool

        public init(deviceUID: String?, isPinnedDeviceMissing: Bool) {
            self.deviceUID = deviceUID
            self.isPinnedDeviceMissing = isPinnedDeviceMissing
        }
    }

    /// Priority: the device the user pinned the app to, then the device the app picked for
    /// itself, then the system default.
    ///
    /// A pinned device that is unplugged falls back without the preference being forgotten, so
    /// the app returns to it when the device comes back.
    public static func resolve(
        pinnedDeviceUID: String?,
        availableDeviceUIDs: Set<String>,
        appDeviceUID: String?,
        systemDefaultDeviceUID: String?
    ) -> Resolution {
        let fallback = appDeviceUID ?? systemDefaultDeviceUID
        guard let pinnedDeviceUID else {
            return Resolution(deviceUID: fallback, isPinnedDeviceMissing: false)
        }
        if availableDeviceUIDs.contains(pinnedDeviceUID) {
            return Resolution(deviceUID: pinnedDeviceUID, isPinnedDeviceMissing: false)
        }
        return Resolution(deviceUID: fallback, isPinnedDeviceMissing: true)
    }
}
