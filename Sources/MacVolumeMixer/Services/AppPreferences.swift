import Foundation
import Observation

/// User preferences backed by `UserDefaults`.
@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let showMenuBarIcon = "showMenuBarIcon"
        static let openMixerAtLaunch = "openMixerAtLaunch"
        static let preferredOutputDeviceUID = "preferredOutputDeviceUID"
        static let preferredOutputDeviceName = "preferredOutputDeviceName"
        static let rememberAppVolumes = "rememberAppVolumes"
        static let showInactiveApps = "showInactiveApps"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    var openMixerAtLaunch: Bool {
        didSet { defaults.set(openMixerAtLaunch, forKey: Key.openMixerAtLaunch) }
    }

    /// UID of the device to switch to at launch and whenever it connects; `nil` follows the system.
    var preferredOutputDeviceUID: String? {
        didSet { defaults.set(preferredOutputDeviceUID, forKey: Key.preferredOutputDeviceUID) }
    }

    /// Last known name of the preferred device, shown while it is disconnected.
    var preferredOutputDeviceName: String? {
        didSet { defaults.set(preferredOutputDeviceName, forKey: Key.preferredOutputDeviceName) }
    }

    var rememberAppVolumes: Bool {
        didSet { defaults.set(rememberAppVolumes, forKey: Key.rememberAppVolumes) }
    }

    var showInactiveApps: Bool {
        didSet { defaults.set(showInactiveApps, forKey: Key.showInactiveApps) }
    }

    init(defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            Key.showMenuBarIcon: true,
            Key.openMixerAtLaunch: false,
            Key.rememberAppVolumes: true,
            Key.showInactiveApps: false,
        ])
        self.defaults = defaults
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        openMixerAtLaunch = defaults.bool(forKey: Key.openMixerAtLaunch)
        preferredOutputDeviceUID = defaults.string(forKey: Key.preferredOutputDeviceUID)
        preferredOutputDeviceName = defaults.string(forKey: Key.preferredOutputDeviceName)
        rememberAppVolumes = defaults.bool(forKey: Key.rememberAppVolumes)
        showInactiveApps = defaults.bool(forKey: Key.showInactiveApps)
    }
}
