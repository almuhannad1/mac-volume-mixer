import Foundation

/// Resolves which user-facing app an audio process belongs to.
///
/// Chromium/Electron apps (Chrome, Discord, Slack, VS Code) render audio in helper processes
/// nested inside the main bundle, e.g.
/// `/Applications/Discord.app/Contents/Frameworks/Discord Helper (Renderer).app/…`.
/// The *outermost* `.app` in the executable path is the app the user knows.
public struct AppIdentityResolver: Sendable {
    public struct BundleInfo: Sendable, Equatable {
        public let identifier: String?
        public let name: String?

        public init(identifier: String?, name: String?) {
            self.identifier = identifier
            self.name = name
        }
    }

    public typealias BundleInfoProvider = @Sendable (_ bundlePath: String) -> BundleInfo?

    /// System services whose processes live outside any app bundle but are meaningful to users.
    /// WebKit media is shared by Safari and every app embedding WebKit; public APIs cannot tell
    /// which app a WebKit GPU process serves, so they are grouped together honestly.
    static let knownServices: [String: (id: String, name: String)] = [
        "com.apple.WebKit.GPU": ("com.apple.WebKit", "Safari & Web Content"),
        "com.apple.WebKit.WebContent": ("com.apple.WebKit", "Safari & Web Content"),
        "systemsoundserverd": ("com.apple.systemsounds", "System Sounds"),
        "com.apple.systemsoundserverd": ("com.apple.systemsounds", "System Sounds"),
    ]

    private let bundleInfo: BundleInfoProvider

    public init(bundleInfo: @escaping BundleInfoProvider) {
        self.bundleInfo = bundleInfo
    }

    public func identity(for process: AudioProcessInfo) -> AppIdentity {
        let reportedBundleID = process.bundleID.flatMap { $0.isEmpty ? nil : $0 }

        if let reportedBundleID, let service = Self.knownServices[reportedBundleID] {
            return AppIdentity(id: service.id, bundleIdentifier: nil, bundlePath: nil, displayName: service.name, kind: .systemService)
        }

        if let path = process.executablePath, let bundlePath = Self.outermostAppBundlePath(inExecutablePath: path) {
            let info = bundleInfo(bundlePath)
            let identifier = info?.identifier ?? reportedBundleID
            let name = info?.name ?? Self.bundleName(from: bundlePath)
            return AppIdentity(
                id: identifier ?? "path:\(bundlePath)",
                bundleIdentifier: identifier,
                bundlePath: bundlePath,
                displayName: name,
                kind: .application
            )
        }

        let executableName = process.executablePath.map { ($0 as NSString).lastPathComponent }
        if let executableName, let service = Self.knownServices[executableName] {
            return AppIdentity(id: service.id, bundleIdentifier: nil, bundlePath: nil, displayName: service.name, kind: .systemService)
        }

        if let reportedBundleID {
            return AppIdentity(
                id: reportedBundleID,
                bundleIdentifier: reportedBundleID,
                bundlePath: nil,
                displayName: executableName ?? reportedBundleID,
                kind: .process
            )
        }

        let name = executableName ?? "Process \(process.pid)"
        return AppIdentity(id: "process:\(name)", bundleIdentifier: nil, bundlePath: nil, displayName: name, kind: .process)
    }

    /// `/Applications/Discord.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper`
    /// → `/Applications/Discord.app`
    public static func outermostAppBundlePath(inExecutablePath path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard let index = components.firstIndex(where: { $0.hasSuffix(".app") && $0.count > 4 }) else {
            return nil
        }
        return components[...index].joined(separator: "/")
    }

    static func bundleName(from bundlePath: String) -> String {
        let last = (bundlePath as NSString).lastPathComponent
        return last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }
}
