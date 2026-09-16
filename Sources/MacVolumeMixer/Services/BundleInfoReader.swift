import AudioHAL
import Foundation
import MixerCore

enum AppBundle {
    /// Our own bundle identifier. Falls back to the known ID when running outside an app bundle
    /// (command-line builds), so the mixer can never list — and therefore never tap — itself.
    static let identifier = Bundle.main.bundleIdentifier ?? HALConstants.subsystem
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
