import Cocoa
import SwiftUI

/// Keeps the popover anchored to AppKit's status item; only its content height changes.
@MainActor
final class PanelViewport: ObservableObject {
    @Published var maximumHeight: CGFloat = 450
}

private struct PanelHeights: PreferenceKey {
    static let defaultValue: [Part: CGFloat] = [:]

    enum Part: Hashable { case header, body, footer }

    static func reduce(value: inout [Part: CGFloat], nextValue: () -> [Part: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

private extension View {
    func measurePanelHeight(_ part: PanelHeights.Part) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: PanelHeights.self, value: [part: geometry.size.height])
            }
        }
    }
}

private enum PanelGrid {
    static let edge: CGFloat = 14
    static let rowInset: CGFloat = 8
    static let columnGap: CGFloat = 8
    static let markWidth: CGFloat = 16
}

@MainActor
struct ContentView: View {
    static let panelSize = NSSize(width: 336, height: 312)
    @ObservedObject var viewModel: AppViewModel
    var usesNativeGlass = false
    @ObservedObject var viewport: PanelViewport
    var onSizeChange: ((NSSize) -> Void)?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.displayScale) private var displayScale
    @State private var selectedDisplayID: DisplaySnapshot.ID?
    @State private var measuredHeight: CGFloat = 0
    @FocusState private var navigationFocus: NavigationFocus?
    @State private var returnFocus: NavigationFocus?

    init(
        viewModel: AppViewModel,
        usesNativeGlass: Bool = false,
        viewport: PanelViewport? = nil,
        onSizeChange: ((NSSize) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.usesNativeGlass = usesNativeGlass
        self.viewport = viewport ?? PanelViewport()
        self.onSizeChange = onSizeChange
    }

    private enum NavigationFocus: Hashable { case allModes, tools, back }

    private var selectedDisplay: DisplaySnapshot? {
        viewModel.displays.first { $0.id == selectedDisplayID } ??
            viewModel.primaryDisplay ?? viewModel.displays.first
    }

    private var layoutHeight: CGFloat {
        min(viewport.maximumHeight, measuredHeight > 0 ? measuredHeight : Self.panelSize.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .measurePanelHeight(.header)

            ScrollView(.vertical, showsIndicators: viewModel.selectedSection == .allModes) {
                pageBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
                    .padding(.bottom, 14)
                    .measurePanelHeight(.body)
            }
            .id(ScrollIdentity(section: viewModel.selectedSection, displayID: selectedDisplay?.id))
            .frame(maxHeight: .infinity)

            footer
                .fixedSize(horizontal: false, vertical: true)
                .measurePanelHeight(.footer)
        }
        .frame(width: Self.panelSize.width, height: layoutHeight)
        .background {
            if !usesNativeGlass {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
        }
        .onPreferenceChange(PanelHeights.self) { heights in
            if heights.count == 3 {
                let scale = max(displayScale, 1)
                let height = ceil(heights.values.reduce(0, +) * scale) / scale
                if height.isFinite && height > 0 { measuredHeight = height }
            }
        }
        .onChange(of: layoutHeight) { height in
            onSizeChange?(NSSize(width: Self.panelSize.width, height: height))
        }
        .onChange(of: viewModel.selectedSection) { section in
            // The target is part of the newly mounted route, not the departing view.
            Task { @MainActor in
                guard viewModel.selectedSection == section else { return }
                navigationFocus = section == .displays ? returnFocus : .back
            }
        }
    }

    private struct ScrollIdentity: Hashable {
        let section: AppSection
        let displayID: DisplaySnapshot.ID?
    }

    @ViewBuilder private var header: some View {
        if viewModel.selectedSection == .displays {
            if let display = selectedDisplay {
                VStack(spacing: 0) {
                    displaySummary(display)
                        .padding(.top, 15)
                        .padding(.bottom, 12)
                    PanelDivider()
                }
                .padding(.horizontal, PanelGrid.edge)
            } else {
                Text("HiDPI Quick")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    viewModel.selectedSection = .displays
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("返回").font(.caption.weight(.medium))
                    }
                    .frame(minHeight: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .focused($navigationFocus, equals: .back)
                .accessibilityLabel("返回显示器首页")

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedSection.title).font(.headline).accessibilityAddTraits(.isHeader)
                    if viewModel.selectedSection == .allModes, let display = selectedDisplay {
                        HStack(spacing: 6) {
                            Text(displayName(display)).lineLimit(1).help(displayName(display))
                            if let mode = display.currentMode {
                                Text("当前 \(mode.logicalResolution)")
                                    .monospacedDigit().fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, PanelGrid.rowInset)
            .padding(.top, 9)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelGrid.edge)
        }
    }

    private func displayName(_ display: DisplaySnapshot) -> String {
        let matching = viewModel.displays.filter { $0.name == display.name }
        guard matching.count > 1, let index = matching.firstIndex(where: { $0.id == display.id }) else {
            return display.name
        }
        return "\(display.name) · \(index + 1)"
    }

    private func displaySummary(_ display: DisplaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PanelGlyph(display.isBuiltin ? "laptopcomputer" : "display", role: .brand)
                    .foregroundStyle(.secondary)
                if viewModel.displays.count > 1 {
                    Menu {
                        ForEach(viewModel.displays) { item in
                            Button {
                                selectedDisplayID = item.id
                            } label: {
                                if item.id == display.id {
                                    Label(displayName(item), systemImage: "checkmark")
                                } else {
                                    Text(displayName(item))
                                }
                            }
                        }
                    } label: {
                        Text(displayName(display)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("选择显示器")
                    .accessibilityValue(displayName(display))
                    .help(displayName(display))
                } else {
                    Text(displayName(display))
                        .font(.subheadline.weight(.semibold)).lineLimit(1).help(displayName(display))
                }
                Spacer(minLength: 0)
                if viewModel.controls.keepAwake {
                    PanelGlyph("cup.and.saucer", role: .utility, label: "防休眠已开启")
                        .foregroundStyle(.secondary)
                        .help("防休眠已开启")
                }
            }

            if let mode = display.currentMode {
                HStack(alignment: .firstTextBaseline, spacing: PanelGrid.columnGap) {
                    Text(mode.logicalResolution)
                        .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text("当前").font(.caption).foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 0)
                    Text(mode.isHiDPI ? "2× HiDPI" : "非 HiDPI")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(mode.presentationRefresh)
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .foregroundStyle(.secondary)
                    Color.clear.frame(width: PanelGrid.markWidth, height: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("当前分辨率 \(mode.logicalResolution)，\(mode.isHiDPI ? "2× HiDPI" : "非 HiDPI")，\(mode.presentationRefresh)，渲染尺寸 \(mode.backingResolution)")
                .help("渲染尺寸 \(mode.backingResolution)")
            } else {
                Text("无法读取当前分辨率").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, PanelGrid.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var pageBody: some View {
        if viewModel.selectedSection == .controls {
            ControlsPane(viewModel: viewModel)
        } else if let display = selectedDisplay {
            VStack(alignment: .leading, spacing: 5) {
                if display.modes.isEmpty {
                    Text("当前没有可选的 HiDPI 分辨率")
                        .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    SectionLabel(title: viewModel.selectedSection == .displays ? "快捷分辨率" : "2× HiDPI 分辨率")
                        .padding(.leading, PanelGrid.rowInset - 2)
                        .accessibilityAddTraits(.isHeader)
                    let modes = viewModel.selectedSection == .displays ? display.featuredModes : display.modes
                    ForEach(modes) { mode in
                        ModeRow(
                            mode: mode,
                            isSelected: display.currentMode?.matches(mode) == true,
                            showsRefreshRate: display.modes.contains {
                                $0.width == mode.width && $0.height == mode.height && $0.id != mode.id
                            },
                            isBusy: viewModel.activeModeID == mode.id,
                            isDisabled: viewModel.activeModeID != nil || display.currentMode == nil,
                            action: { viewModel.selectMode(mode) }
                        )
                    }
                }
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

    private var footer: some View {
        VStack(spacing: 0) {
            if let feedback = viewModel.feedback {
                FeedbackView(feedback: feedback, onAction: viewModel.performFeedbackAction)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            PanelDivider().padding(.horizontal, 14)
            if viewModel.selectedSection == .displays {
                HStack(spacing: 8) {
                    routeButton("全部模式", icon: "list.bullet", section: .allModes, focus: .allModes)
                        .disabled(selectedDisplay?.modes.isEmpty != false)
                    routeButton("系统工具", icon: "slider.horizontal.3", section: .controls, focus: .tools)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 10)
            } else {
                FooterView(viewModel: viewModel)
            }
        }
    }

    private func routeButton(_ title: String, icon: String, section: AppSection, focus: NavigationFocus) -> some View {
        Button {
            returnFocus = focus
            viewModel.selectedSection = section
        } label: {
            HStack(spacing: 4) {
                PanelGlyph(icon, role: .utility)
                Text(title).font(.callout.weight(.medium))
                Spacer(minLength: 0)
                PanelGlyph("chevron.right", role: .utility).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focused($navigationFocus, equals: focus)
    }
}

private extension DisplayMode {
    var presentationRefresh: String {
        guard refreshRate > 0 else { return "自动刷新率" }
        return "\(refreshRate.formatted(.number.precision(.fractionLength(0...2)))) Hz"
    }
}

/// A hairline tracks the hosting screen's scale and snaps to a device-pixel row.
private struct PanelDivider: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        let pixel = 1 / max(1, scale)
        GeometryReader { geometry in
            let y = geometry.frame(in: .global).minY
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.72))
                .offset(y: (y / pixel).rounded() * pixel - y)
        }
        .frame(height: pixel)
        .accessibilityHidden(true)
    }
}

private struct PanelGlyph: View {
    enum Role {
        case utility, feature, brand

        var size: CGFloat { self == .feature ? 14 : 12 }
        var slot: CGFloat {
            switch self {
            case .utility: 16
            case .feature: 24
            case .brand: 20
            }
        }
    }

    let name: String
    var role: Role = .feature
    var label: String? = nil

    init(_ name: String, role: Role = .feature, label: String? = nil) {
        self.name = name
        self.role = role
        self.label = label
    }

    private var opticalOffset: CGSize {
        // Crescent glyphs are bottom-left heavy at both supported raster scales.
        switch name {
        case "moon.fill", "moon.zzz.fill": CGSize(width: 1, height: -1)
        default: .zero
        }
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: role.size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .frame(width: role.slot, height: 20)
            .offset(x: opticalOffset.width, y: opticalOffset.height)
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
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
            HStack(spacing: PanelGrid.columnGap) {
                Text(mode.logicalResolution)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .monospacedDigit()
                Spacer(minLength: 6)
                Text(showsRefreshRate ? (mode.refreshRate > 0 ? compactRefresh : "自动") : "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 62, alignment: .trailing)
                    .accessibilityHidden(true)
                ZStack {
                    Color.clear
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else if isSelected {
                        PanelGlyph("checkmark", role: .utility)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 16, height: 18)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, PanelGrid.rowInset)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.primary.opacity(0.045) :
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
        mode.presentationRefresh
    }
}

private struct ControlsPane: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
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
    }

    private var rowDivider: some View {
        PanelDivider().padding(.leading, 46)
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
            PanelGlyph(icon).foregroundStyle(.secondary)

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

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var canInteract: Bool { isEnabled && !isInteractionDisabled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PanelGlyph(icon).foregroundStyle(.secondary)
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
        .focused($isFocused)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(canInteract && isHovered ? Color.primary.opacity(0.06) : .clear)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
        }
        .overlay {
            if canInteract && isFocused {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onHover { isHovered = $0 }
        .disabled(isInteractionDisabled)
        .accessibilityLabel(title)
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
                label: "退出 HiDPI Quick",
                title: "退出",
                action: { NSApp.terminate(nil) }
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

private struct FooterButton: View {
    var icon: String? = nil
    let label: String
    var title: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { PanelGlyph(icon, role: .utility) }
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
