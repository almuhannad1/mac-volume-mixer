import Foundation

/// Minimal key/data storage so persistence can be tested without touching real defaults.
public protocol SettingsPersistence: AnyObject {
    func data(forKey key: String) -> Data?
    func setData(_ data: Data?, forKey key: String)
}

public final class UserDefaultsPersistence: SettingsPersistence {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }

    public func setData(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public final class InMemoryPersistence: SettingsPersistence {
    public private(set) var storage: [String: Data] = [:]

    public init() {}

    public func data(forKey key: String) -> Data? { storage[key] }
    public func setData(_ data: Data?, forKey key: String) { storage[key] = data }
}
