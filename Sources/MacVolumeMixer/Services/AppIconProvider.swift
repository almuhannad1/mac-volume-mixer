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

    /// Drops icons for apps that are no longer listed. Icons are only resolved while the panel is
    /// open, but without this the cache would keep an `NSImage` for every app that has ever played
    /// a sound, for the lifetime of the app.
    func prune(keeping appIDs: Set<String>) {
        guard cache.count > appIDs.count else { return }
        cache = cache.filter { appIDs.contains($0.key) }
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
