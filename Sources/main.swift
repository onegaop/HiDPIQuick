import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let viewModel = AppViewModel()

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
        popover.contentViewController = NSHostingController(
            rootView: ContentView(viewModel: viewModel)
        )

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
