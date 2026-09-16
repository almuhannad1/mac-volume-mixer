import AppKit
import MixerCore
import SwiftUI

/// Owns the menu bar icon and the mixer popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let viewModel: MixerViewModel
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    /// A transient popover closes on mouse-down outside it, which includes the status item
    /// itself; without this the same click would immediately reopen it.
    private var lastCloseDate = Date.distantPast

    init(viewModel: MixerViewModel) {
        self.viewModel = viewModel
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
        } onChange: { [weak self] in
            self?.updateIcon()
        }
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
    }

    func popoverDidShow(_ notification: Notification) {
        viewModel.panelDidOpen()
    }

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        viewModel.panelDidClose()
    }
}
