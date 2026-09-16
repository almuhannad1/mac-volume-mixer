/// A logical, user-recognisable audio source (one app, possibly many processes).
public struct AppIdentity: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// A regular app bundle, e.g. Spotify.app.
        case application
        /// A macOS component users still recognise, e.g. System Sounds or WebKit media.
        case systemService
        /// An unbundled process or system daemon.
        case process
    }

    /// Stable key used for persistence, normally the owning app's bundle identifier.
    public let id: String
    public let bundleIdentifier: String?
    /// Path of the outermost `.app` bundle, used for the icon.
    public let bundlePath: String?
    public let displayName: String
    public let kind: Kind

    public init(id: String, bundleIdentifier: String?, bundlePath: String?, displayName: String, kind: Kind) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.displayName = displayName
        self.kind = kind
    }

    /// Whether this source is worth listing while it is silent ("Show inactive applications").
    public var isUserFacing: Bool {
        switch kind {
        case .application: return !(bundlePath?.hasPrefix("/System/Library/") ?? false)
        case .systemService: return true
        case .process: return false
        }
    }
}
