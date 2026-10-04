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
    /// With nothing being metered there is nothing to animate, so the loop idles instead of waking
    /// twenty times a second to read no meters at all.
    private static let idleMeterInterval: Duration = .milliseconds(500)

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
            var listedIDs: Set<String> = []
            while !Task.isCancelled {
                guard let self else { return }
                let apps = controller.apps
                var isMetering = false
                for app in apps where app.isProcessing {
                    isMetering = true
                    meters.update(appID: app.id, peak: controller.takePeak(for: app.id))
                }
                // Pruning rebuilds both caches, so only do it when the list has really changed.
                let ids = Set(apps.map(\.id))
                if ids != listedIDs {
                    listedIDs = ids
                    meters.prune(keeping: ids)
                    icons.prune(keeping: ids)
                }
                try? await Task.sleep(for: isMetering ? Self.meterInterval : Self.idleMeterInterval)
            }
        }
    }

    // MARK: Intents

    func setVolume(_ volume: Double, for app: MixerController.AppItem) { controller.setVolume(volume, for: app.id) }
    func toggleMute(for app: MixerController.AppItem) { controller.toggleMute(for: app.id) }
    func toggleSolo(for app: MixerController.AppItem) { controller.toggleSolo(for: app.id) }
    func setOutputDevice(_ deviceUID: String?, for app: MixerController.AppItem) {
        controller.setOutputDevice(deviceUID, for: app.id)
    }
    func setBalance(_ balance: Double, for app: MixerController.AppItem) { controller.setBalance(balance, for: app.id) }
    func setMono(_ isMono: Bool, for app: MixerController.AppItem) { controller.setMono(isMono, for: app.id) }
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
