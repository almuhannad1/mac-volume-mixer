import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences: AppPreferences
    private let loginItems: LoginItemService
    private let controller: MixerController
    private let viewModel: MixerViewModel
    private let statusItemController: StatusItemController
    private let settingsWindowController: SettingsWindowController

    override init() {
        let preferences = AppPreferences()
        let loginItems = LoginItemService()
        let controller = MixerController(
            preferences: preferences,
            disableTaps: CommandLine.arguments.contains("--disable-taps")
        )
        let viewModel = MixerViewModel(controller: controller)

        self.preferences = preferences
        self.loginItems = loginItems
        self.controller = controller
        self.viewModel = viewModel
        statusItemController = StatusItemController(viewModel: viewModel)
        settingsWindowController = SettingsWindowController {
            SettingsView(preferences: preferences, loginItems: loginItems, controller: controller)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel.openSettingsAction = { [weak self] in self?.showSettings() }
        controller.start()

        statusItemController.setVisible(preferences.showMenuBarIcon)
        observeContinuously { [weak self] in
            _ = self?.preferences.showMenuBarIcon
        } onChange: { [weak self] in
            guard let self else { return }
            statusItemController.setVisible(preferences.showMenuBarIcon)
        }

        if preferences.openMixerAtLaunch {
            // Wait one run loop turn so the status item has a frame to anchor the popover.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.openMixer() }
            }
        } else if !preferences.showMenuBarIcon {
            showSettings()
        }
    }

    /// Launching the app again (Finder, Spotlight) opens Settings, which is the way back when
    /// the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    private func openMixer() {
        if statusItemController.isVisible {
            statusItemController.showPanel()
        } else {
            showSettings()
        }
    }

    private func showSettings() {
        settingsWindowController.show()
    }
}
