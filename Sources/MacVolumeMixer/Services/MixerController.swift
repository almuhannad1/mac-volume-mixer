import AppKit
import AudioHAL
import CoreAudio
import MixerCore
import Observation

/// Orchestrates devices, audio sessions, persisted settings and tap engines.
///
/// Every event funnels into `reconcile()`, which derives the desired state from scratch and only
/// forwards changes to the engines. Timed transitions (idle IO, disengage, list linger) are handled
/// by a single scheduled wake-up instead of polling.
@MainActor
@Observable
final class MixerController {
    struct AppItem: Identifiable, Equatable {
        let identity: AppIdentity
        let setting: AppVolumeSetting
        let isPlaying: Bool
        /// Audio is routed through a tap, so a real level meter is available.
        let isProcessing: Bool
        let failureMessage: String?

        var id: String { identity.id }
    }

    private(set) var apps: [AppItem] = []
    private(set) var outputDevices: [AudioOutputDevice] = []
    private(set) var currentOutputDevice: AudioOutputDevice?
    private(set) var masterVolume: Float?
    private(set) var isMasterMuted = false
    private(set) var canMuteMaster = false
    private(set) var captureAuthorization: AudioCaptureAuthorization = .unknown
    private(set) var isCheckingCaptureAccess = false
    /// Set by `--disable-taps`: everything except per-app processing works.
    let isTapProcessingDisabled: Bool

    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let settingsStore: AppVolumeSettingsStore
    @ObservationIgnored private let deviceService = AudioDeviceService()
    @ObservationIgnored private let volumeController = DeviceVolumeController()
    @ObservationIgnored private let processMonitor = AudioProcessMonitor()
    @ObservationIgnored private let resolver = AppIdentityResolver(bundleInfo: BundleInfoReader.read)

    @ObservationIgnored private var sessions: [AudioAppSession] = []
    @ObservationIgnored private var activity = ActivityTracker()
    @ObservationIgnored private var engines: [String: ProcessTapEngine] = [:]
    @ObservationIgnored private var disengageDeadlines: [String: Date] = [:]
    @ObservationIgnored private var engineFailures: [String: String] = [:]
    @ObservationIgnored private var knownDeviceUIDs: Set<String> = []
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledWake: Date?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []

    init(preferences: AppPreferences, disableTaps: Bool, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.isTapProcessingDisabled = disableTaps
        settingsStore = AppVolumeSettingsStore(
            persistence: UserDefaultsPersistence(defaults: defaults),
            isPersistenceEnabled: preferences.rememberAppVolumes
        )
    }

    // MARK: - Lifecycle

    func start() {
        deviceService.onChange = { [weak self] in self?.devicesChanged() }
        volumeController.onChange = { [weak self] in self?.masterVolumeChanged() }
        processMonitor.onChange = { [weak self] in self?.processesChanged($0) }

        deviceService.start()
        processMonitor.start()
        devicesChanged()
        processesChanged(processMonitor.processes)
        observePreferences()
        observeSleepWake()
        recheckCaptureAuthorization()
        if isTapProcessingDisabled {
            AppLog.mixer.notice("Per-app processing disabled by --disable-taps")
        }
    }

    /// Releases every tap synchronously so no app stays muted after we quit.
    func shutdown() {
        probeTask?.cancel()
        wakeTask?.cancel()
        for engine in engines.values {
            engine.shutdownAndWait()
        }
        engines.removeAll()
    }

    // MARK: - Intents

    func setVolume(_ volume: Double, for appID: String) {
        settingsStore.update(appID) {
            $0.setVolume(volume)
            if volume > 0 { $0.isMuted = false }
        }
        engineFailures[appID] = nil
        reconcile()
    }

    func toggleMute(for appID: String) {
        settingsStore.update(appID) { $0.isMuted.toggle() }
        engineFailures[appID] = nil
        reconcile()
    }

    func resetVolume(for appID: String) {
        settingsStore.update(appID) { $0 = .default }
        reconcile()
    }

    func resetAllVolumes() {
        settingsStore.removeAll()
        reconcile()
    }

    func setMasterVolume(_ volume: Float) {
        volumeController.setVolume(volume)
    }

    func toggleMasterMute() {
        volumeController.setMuted(!volumeController.isMuted)
    }

    func selectOutputDevice(_ deviceID: AudioObjectID) {
        guard deviceID != deviceService.defaultOutputDeviceID else { return }
        do {
            try deviceService.setDefaultOutputDevice(deviceID)
        } catch {
            AppLog.mixer.error("Switching output device failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Highest pre-gain peak since the last call, for apps whose audio is routed through a tap.
    func takePeak(for appID: String) -> Float? {
        engines[appID]?.takePeak()
    }

    func recheckCaptureAuthorization() {
        guard !isTapProcessingDisabled, probeTask == nil else { return }
        let deviceID = deviceService.defaultOutputDeviceID
        guard deviceID != AudioObjectID(kAudioObjectUnknown) else {
            captureAuthorization = .unavailable("No output device is available.")
            return
        }
        isCheckingCaptureAccess = true
        probeTask = Task { [weak self] in
            let result = await AudioCapturePermissionProbe.check(outputDeviceID: deviceID)
            guard let self, !Task.isCancelled else { return }
            probeTask = nil
            isCheckingCaptureAccess = false
            if result != captureAuthorization {
                AppLog.mixer.info("Audio capture authorization: \(String(describing: result), privacy: .public)")
                captureAuthorization = result
            }
            reconcile()
        }
    }

    // MARK: - Event handling

    private func devicesChanged() {
        update(\.outputDevices, deviceService.selectableDevices)
        let newDefault = deviceService.defaultOutputDevice
        if newDefault?.uid != currentOutputDevice?.uid {
            AppLog.mixer.info("Default output is now \(newDefault?.name ?? "none", privacy: .public)")
            engineFailures.removeAll()
        }
        update(\.currentOutputDevice, newDefault)
        volumeController.bind(to: deviceService.defaultOutputDeviceID)
        masterVolumeChanged()

        let uids = Set(deviceService.allOutputDevices.map(\.uid))
        let appeared = uids.subtracting(knownDeviceUIDs)
        knownDeviceUIDs = uids
        if let preferred = preferences.preferredOutputDeviceUID, appeared.contains(preferred) {
            applyPreferredOutputDevice()
        }
        reconcile()
    }

    private func masterVolumeChanged() {
        update(\.masterVolume, volumeController.volume)
        update(\.isMasterMuted, volumeController.isMuted)
        update(\.canMuteMaster, volumeController.canMute)
    }

    private func processesChanged(_ processes: [AudioProcessInfo]) {
        let newSessions = AudioSessionGrouper.group(
            processes, excludingPID: getpid(), ownBundleID: AppBundle.identifier, resolver: resolver
        )
        let previousProcesses = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.processObjectIDs) })
        for session in newSessions where previousProcesses[session.id] != session.processObjectIDs {
            engineFailures[session.id] = nil // e.g. the app was relaunched; try again
        }
        sessions = newSessions

        let now = Date()
        activity.update(playingIDs: Set(newSessions.filter(\.isProducingOutput).map(\.id)), now: now)
        activity.prune(keeping: Set(newSessions.map(\.id)))
        reconcile()
    }

    private func applyPreferredOutputDevice() {
        guard let uid = preferences.preferredOutputDeviceUID,
              let device = deviceService.selectableDevices.first(where: { $0.uid == uid }) else { return }
        selectOutputDevice(device.id)
    }

    private func observePreferences() {
        observeContinuously { [weak self] in
            _ = self?.preferences.rememberAppVolumes
            _ = self?.preferences.showInactiveApps
        } onChange: { [weak self] in
            guard let self else { return }
            settingsStore.isPersistenceEnabled = preferences.rememberAppVolumes
            reconcile()
        }
        observeContinuously { [weak self] in
            _ = self?.preferences.preferredOutputDeviceUID
        } onChange: { [weak self] in
            self?.applyPreferredOutputDevice()
        }
    }

    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemDidWake() }
        })
    }

    private func systemDidWake() {
        AppLog.mixer.info("System woke; rebuilding taps")
        Task { [weak self] in
            // Give Bluetooth and USB devices a moment to re-enumerate.
            try? await Task.sleep(for: .seconds(2))
            guard let self else { return }
            engineFailures.removeAll()
            deviceService.refresh()
            for engine in engines.values {
                engine.rebuild()
            }
            reconcile()
        }
    }

    private func engineFailed(_ engine: ProcessTapEngine, error: CoreAudioError) {
        guard engines[engine.appID] === engine else { return }
        AppLog.mixer.error("Tap for \(engine.appID, privacy: .public) failed: \(error.description, privacy: .public)")
        engineFailures[engine.appID] = error.description
        reconcile()
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let now = Date()
        let captureAuthorized = captureAuthorization == .authorized && !isTapProcessingDisabled
        var nextWake: Date?
        func wake(at date: Date?) {
            guard let date else { return }
            nextWake = min(nextWake ?? date, date)
        }

        for session in sessions {
            let id = session.id
            let setting = settingsStore.setting(for: id)
            let wantsTap = TapPolicy.shouldEngage(setting: setting, captureAuthorized: captureAuthorized) && engineFailures[id] == nil

            if wantsTap, let deviceUID = targetDeviceUID(for: session) {
                disengageDeadlines[id] = nil
                let engine = engines[id] ?? makeEngine(for: session.identity)
                engine.setGain(VolumeCurve.gain(for: setting))
                engine.apply(
                    target: .init(processObjectIDs: session.processObjectIDs, outputDeviceUID: deviceUID),
                    running: TapPolicy.shouldRunIO(sessionID: id, activity: activity, now: now)
                )
                wake(at: activity.graceExpiry(id, within: TapPolicy.ioIdleGrace, now: now))
            } else if let engine = engines[id] {
                // Back at 100 %: pass audio through at unity briefly, then release the tap.
                engine.setGain(VolumeCurve.gain(for: setting))
                let deadline = disengageDeadlines[id] ?? now.addingTimeInterval(TapPolicy.disengageDelay)
                if !captureAuthorized || engineFailures[id] != nil || deadline <= now {
                    releaseEngine(id)
                } else {
                    disengageDeadlines[id] = deadline
                    wake(at: deadline)
                }
            }
        }

        let liveIDs = Set(sessions.map(\.id))
        for id in engines.keys where !liveIDs.contains(id) {
            releaseEngine(id)
        }

        let filter = AppListFilter(showInactiveApps: preferences.showInactiveApps)
        let items = sessions.compactMap { session -> AppItem? in
            let setting = settingsStore.setting(for: session.id)
            guard filter.isVisible(session, setting: setting, activity: activity, now: now) else { return nil }
            wake(at: activity.graceExpiry(session.id, within: AppListFilter.lingerInterval, now: now))
            return AppItem(
                identity: session.identity,
                setting: setting,
                isPlaying: session.isProducingOutput,
                isProcessing: engines[session.id] != nil,
                failureMessage: engineFailures[session.id]
            )
        }
        update(\.apps, items)
        scheduleWake(at: nextWake)
    }

    private func targetDeviceUID(for session: AudioAppSession) -> String? {
        if let deviceID = session.preferredOutputDeviceID,
           let device = deviceService.device(id: deviceID),
           !device.uid.hasPrefix(HALConstants.aggregateUIDPrefix) {
            return device.uid
        }
        return currentOutputDevice?.uid
    }

    private func makeEngine(for identity: AppIdentity) -> ProcessTapEngine {
        let engine = ProcessTapEngine(appID: identity.id, displayName: identity.displayName)
        engine.onFailure = { [weak self] engine, error in
            self?.engineFailed(engine, error: error)
        }
        engines[identity.id] = engine
        return engine
    }

    private func releaseEngine(_ id: String) {
        engines.removeValue(forKey: id)?.shutdown()
        disengageDeadlines[id] = nil
    }

    private func scheduleWake(at date: Date?) {
        guard date != scheduledWake else { return }
        wakeTask?.cancel()
        scheduledWake = date
        guard let date else {
            wakeTask = nil
            return
        }
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, 0) + 0.05))
            guard !Task.isCancelled, let self else { return }
            scheduledWake = nil
            reconcile()
        }
    }

    /// Assigns only real changes, so Observation doesn't re-render unchanged views.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<MixerController, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}
