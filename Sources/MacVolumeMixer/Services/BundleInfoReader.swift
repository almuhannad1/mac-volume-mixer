import AudioHAL
import Foundation
import MixerCore

enum AppBundle {
    /// Our own bundle identifier. Falls back to the known ID when running outside an app bundle
    /// (command-line builds), so the mixer can never list — and therefore never tap — itself.
    static let identifier = Bundle.main.bundleIdentifier ?? HALConstants.subsystem

    /// `CFBundleShortVersionString`, e.g. "1.2.0", or `nil` when running the bare binary outside
    /// an app bundle. Never invent a number here: a fake one would make the update check report
    /// that every release is newer than the build in hand.
    static let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    /// `CFBundleVersion`, the build number.
    static let buildVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
}

enum BundleInfoReader {
    /// Name as Finder shows it ("Visual Studio Code", not the internal "Code") plus the bundle ID.
    @Sendable
    static func read(bundlePath: String) -> AppIdentityResolver.BundleInfo? {
        guard let bundle = Bundle(path: bundlePath) else { return nil }
        var name = FileManager.default.displayName(atPath: bundlePath)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return .init(identifier: bundle.bundleIdentifier, name: name.isEmpty ? nil : name)
    }
}
