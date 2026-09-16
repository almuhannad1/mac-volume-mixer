import AppKit
import AudioHAL
import MixerCore
import SwiftUI

/// `MacVolumeMixer --list-sessions`: prints what Core Audio exposes, without creating any taps.
enum Diagnostics {
    /// `--self-test`: builds and releases a real tap pipeline without starting audio IO.
    static func runTapSelfTest() -> Int32 {
        switch TapEngineSelfTest.run() {
        case let .success(message):
            print("✔ \(message)")
            print("  (IO was never started, so nothing was muted and no permission was requested.)")
            return EXIT_SUCCESS
        case let .failure(error):
            print("✘ Tap pipeline failed: \(error)")
            return EXIT_FAILURE
        }
    }

    static func printAudioSessions() {
        print("Output devices")
        for device in AudioDeviceService.readOutputDevices() {
            let flags = [device.isHidden ? "hidden" : nil, device.uid.hasPrefix(HALConstants.aggregateUIDPrefix) ? "mixer-aggregate" : nil]
                .compactMap { $0 }
            print("  [\(device.id)] \(device.name) — uid: \(device.uid), transport: \(device.transportType), channels: \(device.outputChannelCount)"
                + (flags.isEmpty ? "" : ", \(flags.joined(separator: ", "))"))
        }

        let processes = AudioProcessMonitor.readProcesses()
        let resolver = AppIdentityResolver(bundleInfo: BundleInfoReader.read)
        let sessions = AudioSessionGrouper.group(
            processes, excludingPID: getpid(), ownBundleID: AppBundle.identifier, resolver: resolver
        )
        print("\nAudio sessions (▶ = playing)")
        for session in sessions {
            let marker = session.isProducingOutput ? "▶" : " "
            let pids = session.processes.map { "\($0.pid)" }.joined(separator: ", ")
            print("  \(marker) \(session.identity.displayName) — id: \(session.id), kind: \(session.identity.kind), "
                + "user-facing: \(session.identity.isUserFacing), pids: \(pids)")
        }
    }
}

#if DEBUG
extension Diagnostics {
    /// Debug builds only: `MacVolumeMixer --snapshot-panel out.png [--dark]` renders the mixer panel
    /// offscreen with live device/session data (taps disabled) for layout review.
    @MainActor
    static func snapshotPanel(to path: String, dark: Bool) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let defaults = UserDefaults(suiteName: "MacVolumeMixer.snapshot") ?? .standard
        let preferences = AppPreferences(defaults: defaults)
        preferences.showInactiveApps = true
        let controller = MixerController(preferences: preferences, disableTaps: false, defaults: defaults)
        controller.start()
        let model = MixerViewModel(controller: controller)

        let hostingView = NSHostingView(rootView: MixerPanelView(model: model).background(.regularMaterial))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        // Let the permission probe, layout, sizing and observation settle.
        for _ in 0..<20 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.setContentSize(hostingView.fittingSize)
        }
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path) (\(Int(hostingView.bounds.width))×\(Int(hostingView.bounds.height)))")
    }
}
#endif
