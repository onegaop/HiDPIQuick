import AppKit

/// AppKit's transient popovers do not dismiss for every other app's menu or
/// nonactivating panel. Observe only mouse-down events while our panel is open.
@MainActor
final class PopoverOutsideClickMonitor {
    typealias Install = (@escaping () -> Void) -> (() -> Void)?

    private let install: Install
    private var generation: UUID?
    private var remove: (() -> Void)?

    convenience init() {
        self.init(install: { handler in Self.installAppKitMonitor(handler: handler) })
    }

    init(install: @escaping Install) {
        self.install = install
    }

    func start(onOutsideClick: @escaping () -> Void) {
        guard generation == nil else { return }
        let token = UUID()
        generation = token
        remove = install { [weak self] in
            guard self?.generation == token else { return }
            onOutsideClick()
        }
        if remove == nil { generation = nil }
    }

    func stop() {
        generation = nil
        let dispose = remove
        remove = nil
        dispose?()
    }

    private static func installAppKitMonitor(handler: @escaping () -> Void) -> (() -> Void)? {
        // A global monitor only receives events delivered to other apps. Do not
        // consume events or register a keyboard monitor/permission.
        guard let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown],
            handler: { _ in handler() }
        ) else { return nil }
        return { NSEvent.removeMonitor(monitor) }
    }
}
