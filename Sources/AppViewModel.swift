import Cocoa
import CoreGraphics
import Foundation
import ServiceManagement

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedSection: AppSection = .displays
    @Published private(set) var displays: [DisplaySnapshot] = []
    @Published private(set) var controls = SystemControlSnapshot(
        keepAwake: false,
        darkMode: false,
        desktopIconsHidden: false,
        hiddenFilesVisible: false,
        dockAutoHide: false
    )
    @Published private(set) var activeControl: ControlIdentifier?
    @Published private(set) var activeModeID: String?
    @Published private(set) var feedback: AppFeedback?
    @Published private(set) var controlFeedback: ControlFeedback?

    var onStatusChanged: (() -> Void)?
    var onDisplayConfigurationWillChange: (() -> Void)?
    var onDisplayConfigurationFailed: (() -> Void)?

    private let systemController = SystemController()
    private var feedbackDismissal: DispatchWorkItem?
    private var controlFeedbackDismissal: Task<Void, Never>?
    private var controlsRefreshTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?

    init() {
        refresh()
    }

    var primaryDisplay: DisplaySnapshot? {
        displays.first(where: { $0.id == CGMainDisplayID() }) ?? displays.first
    }

    var mainStatusText: String {
        guard let display = primaryDisplay else { return "无显示器" }
        return display.isHiDPIActive ? "HiDPI" : "非 2x"
    }

    var mainSummary: String {
        guard let display = primaryDisplay else { return "未检测到活动显示器" }
        guard let mode = display.currentMode else { return display.name }
        return "\(display.name) / \(mode.logicalResolution) / \(mode.refreshRateText)"
    }

    func refresh() {
        refreshDisplays()
        refreshControls()
    }

    func selectMode(_ mode: DisplayMode) {
        guard activeModeID == nil else { return }
        guard
            let display = displays.first(where: { $0.id == mode.displayID }),
            let currentMode = display.currentMode,
            !currentMode.matches(mode)
        else {
            return
        }

        activeModeID = mode.id
        feedback = nil
        onDisplayConfigurationWillChange?()

        // Give AppKit one run-loop turn to close the popover before the display
        // coordinate space changes underneath it.
        DispatchQueue.main.async { [weak self] in
            self?.applySelectedMode(mode)
        }
    }

    func setKeepAwake(_ enabled: Bool) {
        performToggle(
            .keepAwake,
            optimisticValue: enabled,
            success: enabled ? "已开启防休眠" : "已关闭防休眠",
            expectedState: { $0.keepAwake == enabled },
            operation: { try $0.setKeepAwake(enabled) }
        )
    }

    func setDarkMode(_ enabled: Bool) {
        performToggle(
            .darkMode,
            optimisticValue: enabled,
            success: enabled ? "已切换为深色模式" : "已切换为浅色模式",
            verificationDelay: 0.35,
            expectedState: { $0.darkMode == enabled },
            operation: { try $0.setDarkMode(enabled) }
        )
    }

    func setDesktopIconsHidden(_ hidden: Bool) {
        performToggle(
            .desktopIcons,
            optimisticValue: hidden,
            success: hidden ? "已隐藏桌面图标" : "已显示桌面图标",
            verificationDelay: 0.2,
            expectedState: { $0.desktopIconsHidden == hidden },
            operation: { try $0.setDesktopIconsHidden(hidden) }
        )
    }

    func setHiddenFilesVisible(_ visible: Bool) {
        performToggle(
            .hiddenFiles,
            optimisticValue: visible,
            success: visible ? "已显示隐藏文件" : "已隐藏系统隐藏文件",
            verificationDelay: 0.2,
            expectedState: { $0.hiddenFilesVisible == visible },
            operation: { try $0.setHiddenFilesVisible(visible) }
        )
    }

    func setDockAutoHide(_ enabled: Bool) {
        performToggle(
            .dockAutoHide,
            optimisticValue: enabled,
            success: enabled ? "已开启 Dock 自动隐藏" : "已关闭 Dock 自动隐藏",
            verificationDelay: 0.2,
            expectedState: { $0.dockAutoHide == enabled },
            operation: { try $0.setDockAutoHide(enabled) }
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard controls.loginLaunch != .unavailable else { return }
        performToggle(
            .launchAtLogin,
            optimisticValue: enabled,
            success: enabled ? "已开启登录时启动" : "已关闭登录时启动",
            verificationDelay: 0.25,
            expectedState: { enabled ? $0.loginLaunch.isRequested : $0.loginLaunch == .off },
            operation: { try $0.setLaunchAtLogin(enabled) }
        )
    }

    func startScreenSaver() {
        performAction(.screenSaver, success: "已请求启动屏幕保护程序") {
            try $0.startScreenSaver()
        }
    }

    func sleepDisplays() {
        performAction(.displaySleep, success: "已发送显示器休眠请求") {
            try $0.sleepDisplays()
        }
    }

    func openDisplaysSettings() {
        guard DisplayManager.openDisplaysSettings() else {
            showFeedback("无法打开显示器设置", tone: .warning)
            return
        }
    }

    func performFeedbackAction(_ action: FeedbackAction) {
        switch action {
        case .openAutomationSettings:
            let candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation"
            ]
            for value in candidates {
                guard let url = URL(string: value) else { continue }
                if NSWorkspace.shared.open(url) { return }
            }
        case .openLoginItems:
            dismissControlFeedback()
            SMAppService.openSystemSettingsLoginItems()
        case .openDisplaysSettings:
            openDisplaysSettings()
        }
    }

    func dismissFeedback() {
        feedbackDismissal?.cancel()
        feedback = nil
    }

    func dismissControlFeedback() {
        controlFeedbackDismissal?.cancel()
        controlFeedback = nil
    }

    func shutdown() {
        feedbackDismissal?.cancel()
        controlFeedbackDismissal?.cancel()
        controlsRefreshTask?.cancel()
        controlTask?.cancel()
        systemController.shutdown()
    }

    func refreshDisplayState() {
        refreshDisplays()
    }

    private func refreshDisplays() {
        displays = DisplayManager.snapshots()
        onStatusChanged?()
    }

    private func refreshControls() {
        controlsRefreshTask?.cancel()
        let controller = systemController
        controlsRefreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                controller.snapshot
            }.value
            guard !Task.isCancelled else { return }
            guard let self, self.activeControl == nil, self.controls != snapshot else { return }
            self.controls = snapshot
        }
    }

    private func applySelectedMode(_ mode: DisplayMode) {
        let error = DisplayManager.applyMode(mode, option: .permanently)
        activeModeID = nil
        refreshDisplays()

        guard error == .success else {
            showFeedback(
                "系统无法应用这个分辨率，请在显示器设置中检查连接。",
                tone: .warning,
                action: .openDisplaysSettings
            )
            onDisplayConfigurationFailed?()
            return
        }

        announce("已切换到 \(mode.logicalResolution)")
    }

    private func performToggle(
        _ identifier: ControlIdentifier,
        optimisticValue: Bool,
        success message: String,
        verificationDelay: TimeInterval = 0.1,
        expectedState: @escaping @Sendable (SystemControlSnapshot) -> Bool,
        operation: @escaping @Sendable (SystemController) throws -> Void
    ) {
        guard activeControl == nil else { return }
        controlsRefreshTask?.cancel()
        dismissControlFeedback()
        dismissFeedback()
        let previousControls = controls
        activeControl = identifier
        controls = controls.updating(identifier, to: optimisticValue)

        let controller = systemController
        controlTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                () -> Result<SystemControlSnapshot, Error> in
                do {
                    try operation(controller)
                    if verificationDelay > 0 {
                        try await Task.sleep(
                            nanoseconds: UInt64(verificationDelay * 1_000_000_000)
                        )
                    }
                    let snapshot = controller.snapshot
                    guard expectedState(snapshot) else {
                        throw SystemControlError.stateNotApplied("系统没有应用这个设置，请刷新后重试。")
                    }
                    return .success(snapshot)
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            self.activeControl = nil
            switch result {
            case .success(let snapshot):
                self.controls = snapshot
                if identifier == .launchAtLogin && snapshot.loginLaunch == .pendingApproval {
                    self.showControlFeedback(
                        identifier, message: "请在「登录项」中允许 HiDPI Quick。批准前不会自动启动。",
                        tone: .warning, action: .openLoginItems
                    )
                } else {
                    self.showControlFeedback(identifier, message: message, tone: .success)
                }
            case .failure(let error):
                self.controls = previousControls
                self.showControlFailure(identifier, error: error)
                self.refreshControls()
            }
        }
    }

    private func performAction(
        _ identifier: ControlIdentifier,
        success message: String,
        operation: @escaping @Sendable (SystemController) throws -> Void
    ) {
        guard activeControl == nil else { return }
        dismissControlFeedback()
        dismissFeedback()
        activeControl = identifier

        let controller = systemController
        controlTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try operation(controller) }
            }.value

            guard let self, !Task.isCancelled else { return }
            self.activeControl = nil
            switch result {
            case .success:
                self.showControlFeedback(identifier, message: message, tone: .success)
            case .failure(let error):
                self.showControlFailure(identifier, error: error)
            }
        }
    }

    private func showControlFailure(_ identifier: ControlIdentifier, error: Error) {
        let action = feedbackAction(for: error)
        let message = action == .openAutomationSettings
            ? "无法切换外观。请在「隐私与安全性 → 自动化」中允许 HiDPI Quick 控制「系统事件」。"
            : error.localizedDescription
        showControlFeedback(identifier, message: message, tone: .warning, action: action)
    }

    private func showControlFeedback(
        _ identifier: ControlIdentifier,
        message: String,
        tone: FeedbackTone,
        action: FeedbackAction? = nil
    ) {
        dismissControlFeedback()
        let item = AppFeedback(message: message, tone: tone, action: action)
        controlFeedback = ControlFeedback(control: identifier, feedback: item)
        announce(message)
        guard tone == .success else { return }
        controlFeedbackDismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, self?.controlFeedback?.feedback.id == item.id else { return }
            self?.controlFeedback = nil
        }
    }

    private func feedbackAction(for error: Error) -> FeedbackAction? {
        guard let error = error as? SystemControlError else { return nil }
        if case .automationDenied = error {
            return .openAutomationSettings
        }
        return nil
    }

    private func showFeedback(
        _ message: String,
        tone: FeedbackTone,
        action: FeedbackAction? = nil
    ) {
        feedbackDismissal?.cancel()
        feedback = AppFeedback(message: message, tone: tone, action: action)
        announce(message)

        guard action == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.feedback = nil
        }
        feedbackDismissal = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}
