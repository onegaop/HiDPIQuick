import AppKit

/// The arrowless menu surface is a public AppKit panel, not a skinned popover.
@MainActor
final class MenuPanelController {
    private final class MenuPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private static let edge: CGFloat = 8
    private static let gap: CGFloat = 6
    private let panel = MenuPanel(
        contentRect: NSRect(origin: .zero, size: ContentView.panelSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private let outsideClickMonitor = PopoverOutsideClickMonitor()
    private var keyboardMonitor: Any?

    var isShown: Bool { panel.isVisible }

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.setAccessibilityLabel("HiDPI Quick")
    }

    func setContentViewController(_ controller: NSViewController) {
        panel.contentViewController = controller
        controller.view.wantsLayer = true
        controller.view.layer?.cornerRadius = 17
        controller.view.layer?.masksToBounds = true
    }

    func show(anchor: CGRect, visibleFrame: CGRect, viewport: PanelViewport) {
        let frame = Self.frame(size: ContentView.panelSize, anchor: anchor, visibleFrame: visibleFrame)
        if viewport.size != frame.size { viewport.size = frame.size }
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        outsideClickMonitor.start { [weak self] in self?.close() }
        if keyboardMonitor == nil {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isShown, event.window === self.panel, event.keyCode == 53 else { return event }
                self.close()
                return nil
            }
        }
    }

    func close() {
        outsideClickMonitor.stop()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        panel.orderOut(nil)
    }

    static func frame(size: NSSize, anchor: CGRect, visibleFrame: CGRect) -> CGRect {
        let width = min(size.width, max(1, visibleFrame.width - Self.edge * 2))
        let left = max(visibleFrame.minX + Self.edge, min(anchor.midX - width / 2, visibleFrame.maxX - Self.edge - width))
        let top = min(anchor.minY - Self.gap, visibleFrame.maxY)
        let height = max(1, min(size.height, top - visibleFrame.minY - Self.edge))
        return CGRect(x: left, y: top - height, width: width, height: height)
    }
}
