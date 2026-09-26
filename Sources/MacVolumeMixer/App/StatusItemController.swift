import AppKit
import MixerCore
import SwiftUI

/// Owns the menu bar icon and the mixer popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let viewModel: MixerViewModel
    private let preferences: AppPreferences
    private let popover = NSPopover()
    /// Kept for the lifetime of the app, which is the lifetime of this controller; hiding the
    /// status item is handled by the guard in the monitor itself.
    private var menuBarEventMonitor: Any?
    private var statusItem: NSStatusItem?
    /// A transient popover closes on mouse-down outside it, which includes the status item
    /// itself; without this the same click would immediately reopen it.
    private var lastCloseDate = Date.distantPast

    init(viewModel: MixerViewModel, preferences: AppPreferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        super.init()

        let hostingController = NSHostingController(rootView: MixerPanelView(model: viewModel))
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        observeContinuously { [weak self] in
            _ = self?.viewModel.controller.masterVolume
            _ = self?.viewModel.controller.isMasterMuted
            _ = self?.viewModel.controller.captureAuthorization
        } onChange: { [weak self] in
            self?.updateIcon()
        }
        installMenuBarEventMonitor()
    }

    /// Scroll over the icon to change the master volume, middle-click to mute.
    ///
    /// A *local* monitor only sees events destined for this app's own windows — including the
    /// status item's — so unlike a global monitor it needs no Accessibility permission.
    private func installMenuBarEventMonitor() {
        menuBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .otherMouseDown]) { [weak self] event in
            guard let self, preferences.scrollOnMenuBarIcon,
                  let button = statusItem?.button, event.window === button.window else { return event }
            switch event.type {
            case .scrollWheel:
                adjustMasterVolume(with: event)
                return nil
            case .otherMouseDown:
                viewModel.toggleMasterMute()
                return nil
            default:
                return event
            }
        }
    }

    private func adjustMasterVolume(with event: NSEvent) {
        guard let volume = viewModel.controller.masterVolume else { return }
        // A mouse wheel reports whole lines, a trackpad reports points; scale each so one wheel
        // click is about 2 %.
        let delta = Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.0025 : 0.02)
        guard delta != 0 else { return }
        viewModel.setMasterVolume(min(max(Double(volume) + delta, 0), 1))
    }

    var isVisible: Bool { statusItem != nil }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePanel(_:))
            item.button?.setAccessibilityTitle("Mac Volume Mixer")
            item.button?.toolTip = "Mac Volume Mixer"
            statusItem = item
            updateIcon()
        } else if !visible, let item = statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func showPanel() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func togglePanel(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if Date().timeIntervalSince(lastCloseDate) > 0.25 {
            showPanel()
        }
    }

    private func updateIcon() {
        let controller = viewModel.controller
        let symbol = VolumeGlyph.speakerSymbol(volume: Double(controller.masterVolume ?? 1), isMuted: controller.isMasterMuted)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Mac Volume Mixer")
        image?.isTemplate = true
        statusItem?.button?.image = image
        // Say so on hover when per-app volume is inactive, instead of silently doing nothing.
        let needsPermission = !controller.isTapProcessingDisabled && controller.captureAuthorization != .authorized
        statusItem?.button?.toolTip = needsPermission
            ? "Mac Volume Mixer — per-app volume needs System Audio Recording access"
            : "Mac Volume Mixer"
    }

    func popoverDidShow(_ notification: Notification) {
        viewModel.panelDidOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        viewModel.panelDidClose()
    }
}
