import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let viewModel = AppViewModel()
    private let viewport = PanelViewport()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "display.2",
                accessibilityDescription: "HiDPI Quick"
            )
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = ContentView.panelSize
        let resize: (NSSize) -> Void = { [weak self] size in
            guard let self, self.popover.contentSize != size else { return }
            self.popover.contentSize = size
        }
        if #available(macOS 26.0, *) {
            popover.contentViewController = GlassPopoverController(
                viewModel: viewModel, viewport: viewport, onSizeChange: resize
            )
        } else {
            let host = NSHostingController(
                rootView: ContentView(viewModel: viewModel, viewport: viewport, onSizeChange: resize)
            )
            host.sizingOptions = []
            popover.contentViewController = host
        }

        viewModel.onStatusChanged = { [weak self] in
            self?.updateStatusTitle()
        }
        viewModel.onDisplayConfigurationWillChange = { [weak self] in
            self?.closePopoverForDisplayChange()
        }
        viewModel.onDisplayConfigurationFailed = { [weak self] in
            DispatchQueue.main.async {
                self?.showPopover()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        viewModel.refresh()

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--preview-controls") {
            viewModel.selectedSection = .controls
        }

        if arguments.contains("--preview") || arguments.contains("--preview-controls") {
            DispatchQueue.main.async { [weak self] in
                self?.showPopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.shutdown()
        NotificationCenter.default.removeObserver(self)
    }

    func popoverWillShow(_ notification: Notification) {
        viewModel.refresh()
    }


    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            viewModel.selectedSection = .displays
            showPopover()
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        if popover.isShown {
            popover.performClose(nil)
        }
        viewModel.refreshDisplayState()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if let window = button.window, let screen = window.screen {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            let availableBelow = anchor.minY - screen.visibleFrame.minY - 20
            viewport.maximumHeight = min(450, max(1, floor(availableBelow)))
            if popover.contentSize.height > viewport.maximumHeight {
                popover.contentSize.height = viewport.maximumHeight
            }
        } else {
            viewport.maximumHeight = 450
        }
        viewModel.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusTitle() {
        let title = " \(viewModel.mainStatusText)"
        guard statusItem.button?.title != title else { return }
        statusItem.button?.title = title
    }

    private func closePopoverForDisplayChange() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
