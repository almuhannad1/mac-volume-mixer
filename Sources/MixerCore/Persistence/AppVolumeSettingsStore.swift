import Foundation
import os

/// Per-application volume and mute preferences, keyed by `AppIdentity.id` (normally a bundle ID).
///
/// Only non-default settings are stored; an app at 100 % unmuted has no entry.
public final class AppVolumeSettingsStore {
    public static let storageKey = "appVolumeSettings.v1"

    private static let logger = Logger(subsystem: "dev.macvolumemixer.MacVolumeMixer", category: "settings")

    private let persistence: SettingsPersistence
    private var settings: [String: AppVolumeSetting] = [:]

    /// When disabled, settings live only for the current session and stored values are erased.
    public var isPersistenceEnabled: Bool {
        didSet {
            guard oldValue != isPersistenceEnabled else { return }
            if isPersistenceEnabled { save() } else { persistence.setData(nil, forKey: Self.storageKey) }
        }
    }

    public init(persistence: SettingsPersistence, isPersistenceEnabled: Bool = true) {
        self.persistence = persistence
        self.isPersistenceEnabled = isPersistenceEnabled
        if isPersistenceEnabled {
            settings = Self.load(from: persistence)
        }
    }

    public var allSettings: [String: AppVolumeSetting] { settings }

    public func setting(for appID: String) -> AppVolumeSetting {
        settings[appID] ?? .default
    }

    public func update(_ appID: String, _ change: (inout AppVolumeSetting) -> Void) {
        var setting = self.setting(for: appID)
        change(&setting)
        guard setting != self.setting(for: appID) else { return }
        settings[appID] = setting.isDefault ? nil : setting
        save()
    }

    public func removeAll() {
        settings.removeAll()
        save()
    }

    private func save() {
        guard isPersistenceEnabled else { return }
        if settings.isEmpty {
            persistence.setData(nil, forKey: Self.storageKey)
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            persistence.setData(try encoder.encode(settings), forKey: Self.storageKey)
        } catch {
            Self.logger.error("Failed to encode app volume settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from persistence: SettingsPersistence) -> [String: AppVolumeSetting] {
        guard let data = persistence.data(forKey: storageKey) else { return [:] }
        do {
            return try JSONDecoder().decode([String: AppVolumeSetting].self, from: data)
                .filter { !$0.value.isDefault }
        } catch {
            logger.error("Discarding unreadable app volume settings: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }
}
