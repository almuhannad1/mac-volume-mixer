import AppKit
import AudioHAL
import CoreAudio
import MixerCore
import Observation

/// Presentation state and user intents for the mixer panel.
@MainActor
@Observable
final class MixerViewModel {
    enum CaptureNotice: Equatable {
        case permissionNeeded(isChecking: Bool)
        case unavailable(String)
        case processingDisabled
    }

    let controller: MixerController
    var searchText = ""
    private(set) var isPanelVisible = false
    /// Measured height of the panel's scrollable content (drives the popover size).
    var panelContentHeight: CGFloat = 200

    @ObservationIgnored let meters = MeterBank()
    @ObservationIgnored private let icons = AppIconProvider()
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored var openSettingsAction: () -> Void = {}

    private static let meterInterval: Duration = .milliseconds(50)
    private static let permissionRecheckTicks = 80 // ≈ every 4 s while the panel is open

    init(controller: MixerController) {
        self.controller = controller
    }

    // MARK: Derived state

    var visibleApps: [MixerController.AppItem] {
        controller.apps.filter { AppListFilter.matches($0.identity, query: searchText) }
    }

    var showsSearchField: Bool {
        controller.apps.count >= 6 || !searchText.isEmpty
    }

    var captureNotice: CaptureNotice? {
        if controller.isTapProcessingDisabled { return .processingDisabled }
        switch controller.captureAuthorization {
        case .authorized, .unknown: return nil
        case .notGranted: return .permissionNeeded(isChecking: controller.isCheckingCaptureAccess)
        case let .unavailable(message): return .unavailable(message)
        }
    }

    func icon(for item: MixerController.AppItem) -> AppIcon {
        icons.icon(for: item.identity)
    }

    // MARK: Panel lifecycle

    func panelDidOpen() {
        isPanelVisible = true
        if controller.captureAuthorization != .authorized {
            controller.recheckCaptureAuthorization()
        }
        startMeterLoop()
    }

    func panelDidClose() {
        isPanelVisible = false
        searchText = ""
        meterTask?.cancel()
        meterTask = nil
    }

    /// Meters are sampled only while the panel is visible and only for apps whose audio flows
    /// through a tap; otherwise nothing runs.
    private func startMeterLoop() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                let apps = controller.apps
                for app in apps where app.isProcessing {
                    meters.update(appID: app.id, peak: controller.takePeak(for: app.id))
                }
                meters.prune(keeping: Set(apps.map(\.id)))

                tick += 1
                if tick % Self.permissionRecheckTicks == 0, controller.captureAuthorization == .notGranted {
                    controller.recheckCaptureAuthorization()
                }
                try? await Task.sleep(for: Self.meterInterval)
            }
        }
    }

    // MARK: Intents

    func setVolume(_ volume: Double, for app: MixerController.AppItem) { controller.setVolume(volume, for: app.id) }
    func toggleMute(for app: MixerController.AppItem) { controller.toggleMute(for: app.id) }
    func resetVolume(for app: MixerController.AppItem) { controller.resetVolume(for: app.id) }
    func setMasterVolume(_ volume: Double) { controller.setMasterVolume(Float(volume)) }
    func toggleMasterMute() { controller.toggleMasterMute() }
    func selectOutputDevice(_ deviceID: AudioObjectID) { controller.selectOutputDevice(deviceID) }
    func recheckPermission() { controller.recheckCaptureAuthorization() }
    func openSettings() { openSettingsAction() }
    func quit() { NSApp.terminate(nil) }

    func openPrivacySettings() {
        SystemSettingsLink.openAudioCapturePrivacy()
    }
}

enum SystemSettingsLink {
    /// *Privacy & Security → Screen & System Audio Recording*, where "System Audio Recording Only" lives.
    static func openAudioCapturePrivacy() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
