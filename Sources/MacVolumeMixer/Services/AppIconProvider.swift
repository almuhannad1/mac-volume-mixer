import AppKit
import MixerCore

enum AppIcon {
    case image(NSImage)
    case symbol(String)
}

/// Resolves and caches icons for audio sessions.
@MainActor
final class AppIconProvider {
    private var cache: [String: AppIcon] = [:]

    func icon(for identity: AppIdentity) -> AppIcon {
        if let cached = cache[identity.id] { return cached }
        let icon = resolve(identity)
        cache[identity.id] = icon
        return icon
    }

    private func resolve(_ identity: AppIdentity) -> AppIcon {
        if let path = identity.bundlePath {
            return .image(NSWorkspace.shared.icon(forFile: path))
        }
        switch identity.id {
        case "com.apple.WebKit":
            if let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
                return .image(NSWorkspace.shared.icon(forFile: safari.path))
            }
            return .symbol("safari")
        case "com.apple.systemsounds":
            return .symbol("bell.badge")
        default:
            return .symbol("gearshape.2")
        }
    }
}
