import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let makeContent: () -> SettingsView
    private var window: NSWindow?

    init(makeContent: @escaping () -> SettingsView) {
        self.makeContent = makeContent
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac Volume Mixer Settings"
        window.contentView = NSHostingView(rootView: makeContent())
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
