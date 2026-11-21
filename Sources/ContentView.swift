import Cocoa
import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)

            Divider()

            Picker("功能", selection: $viewModel.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Group {
                switch viewModel.selectedSection {
                case .displays:
                    DisplaysPane(viewModel: viewModel)
                case .controls:
                    ControlsPane(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if let feedback = viewModel.feedback {
                    FeedbackView(
                        feedback: feedback,
                        onAction: viewModel.performFeedbackAction
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
            }

            Divider()
            FooterView(viewModel: viewModel)
        }
        .frame(width: 420, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HeaderView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "display.2")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("HiDPI Quick")
                    .font(.headline)
                Text(viewModel.mainSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: viewModel.mainStatusText,
                isActive: viewModel.primaryDisplay?.isHiDPIActive == true
            )
        }
        .padding(14)
    }
}

private struct DisplaysPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        if viewModel.displays.isEmpty {
            EmptyStateView(
                icon: "display.trianglebadge.exclamationmark",
                title: "未检测到显示器",
                actionTitle: "重新检测",
                action: viewModel.refresh
            )
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(viewModel.displays) { display in
                        DisplaySection(
                            display: display,
                            activeModeID: viewModel.activeModeID,
                            onSelect: viewModel.selectMode
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14 + (viewModel.feedback == nil ? 0 : 54))
            }
        }
    }
}

private struct DisplaySection: View {
    let display: DisplaySnapshot
    let activeModeID: String?
    let onSelect: (DisplayMode) -> Void
    @State private var showsAllModes = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(display.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(displaySubtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(display.isHiDPIActive ? Color.green : Color.secondary)
                    Text(currentModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                StatusBadge(
                    text: display.isHiDPIActive ? "2x" : "非 2x",
                    isActive: display.isHiDPIActive
                )
            }
            .padding(12)

            Divider()

            if display.modes.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text("当前没有可用的 2x HiDPI 分辨率")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else {
                modeRows(display.featuredModes)

                if !display.additionalModes.isEmpty {
                    Divider().padding(.leading, 12)

                    DisclosureGroup(isExpanded: $showsAllModes) {
                        VStack(spacing: 0) {
                            Divider().padding(.leading, 12)
                            modeRows(display.additionalModes)
                        }
                    } label: {
                        Text("其他 \(display.additionalModes.count) 个 HiDPI 模式")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
        }
    }

    private var currentModeDescription: String {
        guard let mode = display.currentMode else {
            return "无法读取当前分辨率"
        }
        return "\(mode.logicalResolution) → \(mode.backingResolution) · \(mode.refreshRateText)"
    }

    private var displaySubtitle: String {
        let kind = display.isBuiltin ? "内建显示器" : "外接显示器"
        return display.isHiDPIActive ? "\(kind) · 真正 2x HiDPI" : "\(kind) · 当前不是 2x 模式"
    }

    @ViewBuilder
    private func modeRows(_ modes: [DisplayMode]) -> some View {
        ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
            ModeRow(
                mode: mode,
                context: context(for: mode, in: modes),
                isSelected: display.currentMode?.matches(mode) == true,
                isBusy: activeModeID == mode.id,
                isDisabled: activeModeID != nil,
                action: { onSelect(mode) }
            )

            if index < modes.count - 1 {
                Divider().padding(.leading, 12)
            }
        }
    }

    private func context(for mode: DisplayMode, in modes: [DisplayMode]) -> String? {
        if display.currentMode?.matches(mode) == true {
            return "当前"
        }
        if mode.id == display.modes.first?.id {
            return "更多空间"
        }
        if mode.id == modes.last?.id,
           let currentMode = display.currentMode,
           mode.width < currentMode.width {
            return "较大文字"
        }
        return nil
    }
}

private struct ModeRow: View {
    let mode: DisplayMode
    let context: String?
    let isSelected: Bool
    let isBusy: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.logicalResolution)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                        .monospacedDigit()
                    Text("\(mode.refreshRateText) / 渲染 \(mode.backingResolution)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 8)

                if let context {
                    Text(context)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }

                if isBusy {
                    ProgressView().controlSize(.small)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("当前分辨率")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        .disabled(isDisabled)
        .accessibilityLabel(
            "\(mode.logicalResolution)，2x HiDPI，渲染 \(mode.backingResolution)，\(mode.refreshRateText)"
        )
        .accessibilityValue(isSelected ? "当前选中" : "可选择")
        .accessibilityHint("选择后立即切换分辨率并关闭菜单")
    }
}

private struct ControlsPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(.bottom, 14 + (viewModel.feedback == nil ? 0 : 54))
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 50)
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
                .allowsHitTesting(!isInteractionDisabled)
                .accessibilityLabel(title)
                .accessibilityHint(isBusy ? "正在应用设置" : "")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
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
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isInteractionDisabled)
        .accessibilityLabel(title)
    }
}

private struct ControlIcon: View {
    let name: String

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
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
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35))
            }
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

private struct StatusBadge: View {
    let text: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? Color.green : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            (isActive ? Color.green : Color.secondary).opacity(0.11),
            in: Capsule()
        )
        .accessibilityElement(children: .combine)
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
        .padding(.vertical, 8)
    }
}

private struct FooterButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}
