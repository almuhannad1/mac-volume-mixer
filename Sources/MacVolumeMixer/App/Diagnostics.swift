import AppKit
import AudioHAL
import CoreAudio
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

    /// `--check-permission`: reports whether taps actually deliver audio for *this* bundle.
    ///
    /// Run the copy inside the installed app bundle to test the app's own grant; running the
    /// bare binary tests the terminal's instead, since macOS attributes access to the caller.
    static func checkCapturePermission() -> Int32 {
        let deviceID = AudioDeviceService.currentDefaultOutputDeviceID()
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            print("✘ No default output device; cannot check.")
            return EXIT_FAILURE
        }
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome = AudioCaptureAuthorization.unknown
        // Detached: this function blocks the main actor on the semaphore, so an inherited
        // main-actor task would deadlock waiting for it.
        Task.detached {
            outcome = await AudioCapturePermissionProbe.check(outputDeviceID: deviceID)
            semaphore.signal()
        }
        semaphore.wait()

        switch outcome {
        case .authorized:
            print("✔ System Audio Recording is granted: per-app volume works.")
            return EXIT_SUCCESS
        case .notGranted:
            print("✘ System Audio Recording is not granted, so taps would return silence.")
            print("  Allow it in System Settings → Privacy & Security → Screen & System Audio Recording.")
            return EXIT_FAILURE
        case let .unavailable(reason):
            print("✘ The check could not run: \(reason)")
            return EXIT_FAILURE
        case .unknown:
            print("✘ The check did not complete.")
            return EXIT_FAILURE
        }
    }

    /// `--measure-taps [count] [bufferFrames|device] [seconds]`: reports the CPU and wake-up cost
    /// of running taps, so power reports can be answered with measurements.
    static func measureTapLoad(arguments: [String]) -> Int32 {
        let count = Int(arguments.first ?? "") ?? 1
        let buffer: UInt32? = arguments.dropFirst().first.flatMap { $0 == "device" ? nil : UInt32($0) }
        let seconds = Double(arguments.dropFirst(2).first ?? "") ?? 10

        do {
            let result = try TapLoadMeasurement.run(tapCount: count, bufferFrames: buffer, seconds: seconds)
            let bufferLabel = buffer == nil ? "\(result.bufferFrames) (device default)" : "\(result.bufferFrames)"
            print("""
                \(result.tapCount) tap(s), buffer \(bufferLabel) frames at \(Int(result.sampleRate)) Hz                 over \(String(format: "%.1f", result.seconds)) s
                  CPU                \(String(format: "%.2f", result.cpuPercent)) % of one core
                  Wake-ups           \(String(format: "%.0f", result.wakeupsPerSecond)) /s                 (expected \(String(format: "%.0f", result.expectedCallbacksPerSecond)) realtime callbacks/s)
                  Memory footprint   \(result.footprintBytes / 1_048_576) MB
                """)
            return EXIT_SUCCESS
        } catch {
            print("✘ Measurement failed: \(error)")
            return EXIT_FAILURE
        }
    }

    /// `--measure-scan`: how long one full audio-process enumeration takes. This runs on every
    /// Core Audio notification, so it is the app's main non-realtime CPU cost.
    static func measureProcessScan() -> Int32 {
        let scan = TapLoadMeasurement.measureProcessScan()
        print("HAL process scan:      \(String(format: "%.2f", scan.milliseconds)) ms for \(scan.processCount) audio processes")

        let processes = AudioProcessMonitor.readProcesses()
        let resolver = AppIdentityResolver(bundleInfo: BundleInfoReader.read)
        let iterations = 20
        let start = Date()
        var sessions = 0
        for _ in 0..<iterations {
            sessions = AudioSessionGrouper.group(
                processes, excludingPID: getpid(), ownBundleID: AppBundle.identifier, resolver: resolver
            ).count
        }
        let grouping = Date().timeIntervalSince(start) / Double(iterations) * 1000
        print("Identity + grouping:   \(String(format: "%.2f", grouping)) ms for \(sessions) sessions")
        let volatileRefresh = TapLoadMeasurement.measureVolatileRefresh()
        print("One object's volatile state: \(String(format: "%.2f", volatileRefresh)) ms")
        print("""
            Per notification: \(String(format: "%.2f", volatileRefresh + grouping)) ms now,             vs \(String(format: "%.2f", scan.milliseconds + grouping)) ms with a full rescan
            """)
        return EXIT_SUCCESS
    }

    /// `--watch-sessions [seconds]`: prints every change the process monitor reports, to verify
    /// that incremental updates still track apps starting and stopping audio.
    @MainActor
    static func watchSessions(seconds: Double) -> Int32 {
        let monitor = AudioProcessMonitor()
        let resolver = AppIdentityResolver(bundleInfo: BundleInfoReader.read)
        var changes = 0
        let started = Date()

        monitor.onChange = { processes in
            changes += 1
            let sessions = AudioSessionGrouper.group(
                processes, excludingPID: getpid(), ownBundleID: AppBundle.identifier, resolver: resolver
            )
            let playing = sessions.filter(\.isProducingOutput).map(\.identity.displayName)
            let elapsed = String(format: "%5.1fs", Date().timeIntervalSince(started))
            print("[\(elapsed)] change \(changes): \(sessions.count) sessions, playing: "
                + (playing.isEmpty ? "—" : playing.joined(separator: ", ")))
        }
        monitor.start()
        print("Watching for \(Int(seconds))s…")
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        print("\(changes) change events in \(Int(seconds))s")
        return EXIT_SUCCESS
    }

    /// `--probe-multi-output <uid> <uid> [--stacked]`: feasibility check for sending one app to
    /// two output devices at once.
    static func probeMultiOutput(arguments: [String]) -> Int32 {
        let stacked = arguments.contains("--stacked")
        let uids = arguments.filter { !$0.hasPrefix("--") }
        guard uids.count >= 2 else {
            print("Usage: --probe-multi-output <deviceUID> <deviceUID> [--stacked]")
            print("Device UIDs come from --list-sessions.")
            return EXIT_FAILURE
        }
        do {
            let layout = arguments.contains("--nested")
                ? try MultiOutputProbe.probeNested(deviceUIDs: uids)
                : try MultiOutputProbe.probe(deviceUIDs: uids, stacked: stacked)
            print("""
                \(stacked ? "Stacked (mirrored)" : "Aggregate (channels concatenated)"): \(layout.aggregateName)
                  Sample rate      \(Int(layout.sampleRate)) Hz
                  Output streams   \(layout.outputStreamChannelCounts) → \(layout.totalOutputChannels) channels total
                  Input streams    \(layout.inputStreamChannelCounts) (the tap is the last one)
                  IO started       \(layout.startedIO ? "yes" : "NO")\(layout.note.isEmpty ? "" : " — \(layout.note)")
                """)
            return layout.startedIO ? EXIT_SUCCESS : EXIT_FAILURE
        } catch {
            print("✘ Not possible: \(error)")
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
        print("\nAudio sessions (▶ = playing, ● = microphone in use)")
        for session in sessions {
            let marker = (session.isProducingOutput ? "▶" : " ") + (session.isUsingInput ? "●" : " ")
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
    /// Debug builds only: renders the About tab offscreen, for reviewing its layout.
    @MainActor
    static func snapshotAbout(to path: String, dark: Bool) {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let hostingView = NSHostingView(rootView: AboutSettingsView())
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 440)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        for _ in 0..<5 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }

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
