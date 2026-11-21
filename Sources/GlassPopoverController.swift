import Cocoa
import SwiftUI

/// Hosts the native glass surface separately from panel placement and dismissal.
@available(macOS 26.0, *)
@MainActor
final class GlassPopoverController: NSViewController {
    private let host: NSHostingController<ContentView>
    private let reduceTransparency: () -> Bool
    private var installedReduceTransparency: Bool?

    init(
        viewModel: AppViewModel,
        viewport: PanelViewport? = nil,
        onSizeChange: ((NSSize) -> Void)? = nil,
        reduceTransparency: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    ) {
        host = NSHostingController(rootView: ContentView(
            viewModel: viewModel,
            usesNativeGlass: true,
            viewport: viewport,
            onSizeChange: onSizeChange
        ))
        host.sizingOptions = []
        self.reduceTransparency = reduceTransparency
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: ContentView.panelSize))
        addChild(host)
        refreshSurface()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshSurface()
    }

    @objc private func accessibilityDisplayDidChange(_ notification: Notification) {
        refreshSurface()
    }

    /// The hosting controller stays alive when the system accessibility option
    /// changes, so the menu tab and selected display survive the transition.
    private func refreshSurface() {
        let solid = reduceTransparency()
        guard installedReduceTransparency != solid else { return }
        installedReduceTransparency = solid

        host.view.removeFromSuperview()
        view.subviews.forEach { $0.removeFromSuperview() }

        if solid {
            let background = OpaquePopoverBackground(frame: view.bounds)
            background.autoresizingMask = [.width, .height]
            view.addSubview(background)
            mountHost(in: background)
        } else {
            let glass = NSGlassEffectView(frame: view.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            glass.cornerRadius = 17
            let content = NSView(frame: glass.bounds)
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            view.addSubview(glass)
            mountHost(in: content)
        }
    }

    private func mountHost(in container: NSView) {
        host.view.frame = container.bounds
        host.view.autoresizingMask = [.width, .height]
        container.addSubview(host.view)
    }
}

// AppKit resolves this semantic color in the current drawing appearance.
final class OpaquePopoverBackground: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}
