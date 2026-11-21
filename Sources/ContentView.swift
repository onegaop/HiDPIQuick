import Cocoa
import SwiftUI

struct ContentView: View {
    static let panelSize = NSSize(width: 336, height: 450)
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedDisplayID: DisplaySnapshot.ID?

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)

            Picker("功能", selection: $viewModel.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.top, 1)
            .padding(.bottom, 10)

            Group {
                switch viewModel.selectedSection {
                case .displays:
                    DisplaysPane(viewModel: viewModel, selectedDisplayID: $selectedDisplayID)
                case .controls:
                    ControlsPane(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let feedback = viewModel.feedback {
                FeedbackView(feedback: feedback, onAction: viewModel.performFeedbackAction)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            PanelDivider().padding(.horizontal, 14)
            FooterView(viewModel: viewModel)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
    }
}

private struct HeaderView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "display.2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("HiDPI Quick").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if viewModel.controls.keepAwake {
                Label("防休眠已开启", systemImage: "cup.and.saucer")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .help("防休眠已开启")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.6))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

private struct DisplaysPane: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedDisplayID: DisplaySnapshot.ID?

    private var selectedDisplay: DisplaySnapshot? {
        viewModel.displays.first { $0.id == selectedDisplayID } ??
            viewModel.primaryDisplay ?? viewModel.displays.first
    }

    var body: some View {
        if let display = selectedDisplay {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.displays.count > 1 {
                        Picker("显示器", selection: Binding(
                            get: { selectedDisplay?.id ?? display.id },
                            set: { selectedDisplayID = $0 }
                        )) {
                            ForEach(viewModel.displays) { item in
                                Text(item.name).tag(item.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                    }
                    DisplaySection(
                        display: display,
                        showName: viewModel.displays.count == 1,
                        activeModeID: viewModel.activeModeID,
                        onSelect: viewModel.selectMode
                    )
                    .id(display.id)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
        } else {
            EmptyStateView(
                icon: "display.trianglebadge.exclamationmark",
                title: "未检测到显示器",
                actionTitle: "重新检测",
                action: viewModel.refresh
            )
        }
    }
}

private struct DisplaySection: View {
    let display: DisplaySnapshot
    let showName: Bool
    let activeModeID: String?
    let onSelect: (DisplayMode) -> Void
    @State private var showsAllModes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 9) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    if showName {
                        Text(display.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(display.name)
                    }
                    if let mode = display.currentMode {
                        Text(mode.logicalResolution)
                            .font(.headline)
                            .monospacedDigit()
                        Text("渲染尺寸 \(mode.backingResolution)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("无法读取分辨率").font(.callout)
                    }
                }
                Spacer(minLength: 6)
                if let mode = display.currentMode {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(mode.isHiDPI ? "2× HiDPI" : "非 HiDPI")
                            .font(.caption.weight(.semibold))
                        Text(mode.refreshRate > 0 ? mode.refreshRateText : "自动刷新率")
                            .font(.caption)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(currentStatusLabel)

            PanelDivider().padding(.vertical, 3)

            if display.modes.isEmpty {
                Text("当前没有可选的 HiDPI 分辨率")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                SectionLabel(title: "2× HiDPI 分辨率")
                modeRows(display.featuredModes)
                if !display.additionalModes.isEmpty {
                    DisclosureGroup("其他 HiDPI 模式（\(display.additionalModes.count)）", isExpanded: $showsAllModes) {
                        modeRows(display.additionalModes)
                            .padding(.top, 4)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var currentStatusLabel: String {
        guard let mode = display.currentMode else { return "\(display.name)，无法读取当前分辨率" }
        let scale = mode.isHiDPI ? "2× HiDPI" : "非 HiDPI"
        return "\(display.name)，当前 \(mode.logicalResolution)，\(scale)，渲染尺寸 \(mode.backingResolution)，\(mode.refreshRateText)"
    }

    private func modeRows(_ modes: [DisplayMode]) -> some View {
        VStack(spacing: 2) {
            ForEach(modes) { mode in
                ModeRow(
                    mode: mode,
                    isSelected: display.currentMode?.matches(mode) == true,
                    showsRefreshRate: display.modes.contains {
                        $0.width == mode.width && $0.height == mode.height && $0.id != mode.id
                    },
                    isBusy: activeModeID == mode.id,
                    isDisabled: activeModeID != nil || display.currentMode == nil,
                    action: { onSelect(mode) }
                )
            }
        }
    }
}

private struct ModeRow: View {
    let mode: DisplayMode
    let isSelected: Bool
    let showsRefreshRate: Bool
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(mode.logicalResolution)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .monospacedDigit()
                Spacer(minLength: 6)
                if showsRefreshRate {
                    Text(mode.refreshRate > 0 ? compactRefresh : "自动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Group {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 16)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.primary.opacity(0.055) :
                (isHovered && !isDisabled ? Color.primary.opacity(0.06) : Color.clear),
            in: RoundedRectangle(cornerRadius: 5)
        )
        .onHover { isHovered = $0 }
        .disabled(isDisabled)
        .help("渲染 \(mode.backingResolution) · \(mode.refreshRateText)")
        .accessibilityLabel("\(mode.logicalResolution)，HiDPI，\(mode.refreshRate > 0 ? compactRefresh : mode.refreshRateText)")
        .accessibilityValue(isBusy ? "正在切换" : (isSelected ? "当前分辨率" : ""))
        .accessibilityHint(isSelected || isDisabled ? "" : "立即切换并关闭菜单")
    }

    private var compactRefresh: String {
        let value = mode.refreshRate.formatted(.number.precision(.fractionLength(0...2)))
        return "\(value) Hz"
    }
}

private struct ControlsPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "系统开关")

                VStack(spacing: 0) {
                    ToggleControlRow(
                        icon: "cup.and.saucer.fill",
                        title: "防休眠",
                        subtitle: viewModel.controls.keepAwake ? "已启用，退出 App 时自动关闭" : "阻止系统休眠和自动屏保",
                        isOn: binding(viewModel.controls.keepAwake, action: viewModel.setKeepAwake),
                        isBusy: viewModel.activeControl == .keepAwake,
                        isInteractionDisabled: viewModel.activeControl != nil
                    )
                    rowDivider
                    ToggleControlRow(
                        icon: "moon.fill",
                        title: "深色模式",
                        subtitle: viewModel.controls.darkMode ? "当前使用深色外观" : "当前使用浅色外观",
                        isOn: binding(viewModel.controls.darkMode, action: viewModel.setDarkMode),
                        isBusy: viewModel.activeControl == .darkMode,
                        isInteractionDisabled: viewModel.activeControl != nil
                    )
                    rowDivider
                    ToggleControlRow(
                        icon: "desktopcomputer",
                        title: "隐藏桌面图标",
                        subtitle: viewModel.controls.desktopIconsHidden ? "桌面图标已隐藏" : "桌面图标正常显示",
                        isOn: binding(viewModel.controls.desktopIconsHidden, action: viewModel.setDesktopIconsHidden),
                        isBusy: viewModel.activeControl == .desktopIcons,
                        isInteractionDisabled: viewModel.activeControl != nil
                    )
                    rowDivider
                    ToggleControlRow(
                        icon: "eye.fill",
                        title: "显示隐藏文件",
                        subtitle: viewModel.controls.hiddenFilesVisible ? "Finder 正在显示隐藏项目" : "Finder 当前不显示隐藏文件",
                        isOn: binding(viewModel.controls.hiddenFilesVisible, action: viewModel.setHiddenFilesVisible),
                        isBusy: viewModel.activeControl == .hiddenFiles,
                        isInteractionDisabled: viewModel.activeControl != nil
                    )
                    rowDivider
                    ToggleControlRow(
                        icon: "dock.rectangle",
                        title: "Dock 自动隐藏",
                        subtitle: viewModel.controls.dockAutoHide ? "移到屏幕边缘时显示 Dock" : "Dock 保持显示",
                        isOn: binding(viewModel.controls.dockAutoHide, action: viewModel.setDockAutoHide),
                        isBusy: viewModel.activeControl == .dockAutoHide,
                        isInteractionDisabled: viewModel.activeControl != nil
                    )
                }
                .controlGroupStyle()

                SectionLabel(title: "快捷动作")

                VStack(spacing: 0) {
                    ActionRow(
                        icon: "play.rectangle.fill",
                        title: "启动屏幕保护程序",
                        isBusy: viewModel.activeControl == .screenSaver,
                        isInteractionDisabled: viewModel.activeControl != nil,
                        action: viewModel.startScreenSaver
                    )
                    rowDivider
                    ActionRow(
                        icon: "moon.zzz.fill",
                        title: "立即关闭显示器",
                        isBusy: viewModel.activeControl == .displaySleep,
                        isInteractionDisabled: viewModel.activeControl != nil,
                        action: viewModel.sleepDisplays
                    )
                }
                .controlGroupStyle()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var rowDivider: some View {
        PanelDivider().padding(.leading, 36)
    }

    private func binding(
        _ value: Bool,
        action: @escaping @MainActor (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { newValue in
                Task { @MainActor in
                    action(newValue)
                }
            }
        )
    }
}

private struct ToggleControlRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let isBusy: Bool
    let isInteractionDisabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            ControlIcon(name: icon)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            ProgressView()
                .controlSize(.small)
                .frame(width: 14, height: 14)
                .opacity(isBusy ? 1 : 0)
                .accessibilityHidden(!isBusy)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isInteractionDisabled)
                .accessibilityLabel(title)
                .accessibilityHint(isBusy ? "正在应用设置" : "")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
    }
}

private struct ActionRow: View {
    let icon: String
    let title: String
    let isBusy: Bool
    let isInteractionDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ControlIcon(name: icon)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()

                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
                    .opacity(isBusy ? 1 : 0)
                    .accessibilityHidden(!isBusy)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isInteractionDisabled)
        .accessibilityLabel(title)
    }
}

private struct ControlIcon: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 24)
            .accessibilityHidden(true)
    }
}

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

private struct ControlGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.primary.opacity(0.028), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func controlGroupStyle() -> some View {
        modifier(ControlGroupModifier())
    }
}

private struct FeedbackView: View {
    let feedback: AppFeedback
    let onAction: (FeedbackAction) -> Void

    var body: some View {
        let isSuccess = feedback.tone == .success

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .padding(.top, 1)
                Text(feedback.message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let action = feedback.action {
                Button(action.title) {
                    onAction(action)
                }
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
                .accessibilityHint("打开对应的系统设置页面")
            }
        }
        .foregroundStyle(isSuccess ? Color.green : Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
            RoundedRectangle(cornerRadius: 8)
                .fill((isSuccess ? Color.green : Color.orange).opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder((isSuccess ? Color.green : Color.orange).opacity(0.16))
        }
    }
}

private struct EmptyStateView: View {
    let icon: String
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.medium))
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct FooterView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 6) {
            FooterButton(
                icon: "display",
                label: "打开显示器设置",
                title: "显示器设置",
                action: viewModel.openDisplaysSettings
            )
            FooterButton(
                icon: "arrow.clockwise",
                label: "刷新状态",
                action: viewModel.refresh
            )

            Spacer()

            FooterButton(
                icon: "power",
                label: "退出 HiDPI Quick",
                action: { NSApp.terminate(nil) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct FooterButton: View {
    let icon: String
    let label: String
    var title: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                if let title { Text(title) }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.primary.opacity(0.68))
            .frame(minWidth: 28, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}
