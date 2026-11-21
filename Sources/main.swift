import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = MenuPanelController()
    private let viewModel = AppViewModel()
    private let viewport = PanelViewport()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.image = StatusMenuGlyph.standard
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("HiDPI Quick")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        if #available(macOS 26.0, *) {
            panel.setContentViewController(
                GlassPopoverController(viewModel: viewModel, viewport: viewport)
            )
        } else {
            let host = NSHostingController(
                rootView: ContentView(viewModel: viewModel, viewport: viewport)
            )
            host.sizingOptions = []
            panel.setContentViewController(host)
        }

        viewModel.onStatusChanged = { [weak self] in
            self?.updateStatusItem()
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
        panel.close()
        viewModel.shutdown()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if panel.isShown {
            panel.close()
        } else {
            viewModel.selectedSection = .displays
            showPopover()
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        if panel.isShown {
            panel.close()
        }
        viewModel.refreshDisplayState()
    }

    private func showPopover() {
        guard let button = statusItem.button, let window = button.window, let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        viewModel.refresh()
        panel.show(anchor: anchor, visibleFrame: screen.visibleFrame, viewport: viewport)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let status = viewModel.mainStatusText
        let image = viewModel.primaryDisplay?.isHiDPIActive == true ? StatusMenuGlyph.hiDPI : StatusMenuGlyph.standard
        let tooltip = "HiDPI Quick · \(status)"
        guard button.toolTip != tooltip || button.image !== image else { return }
        button.image = image
        button.toolTip = tooltip
        button.setAccessibilityValue(status)
    }

    private func closePopoverForDisplayChange() {
        guard panel.isShown else { return }
        panel.close()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
