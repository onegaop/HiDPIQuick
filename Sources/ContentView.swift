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
    // The system overlay scroller can grow on hover. Keep it off the row surface.
    static let modeScrollerClearance: CGFloat = 4
}

/// Shared typographic roles across the three routes of the panel.
private enum PanelType {
    static let reading: Font = .system(size: 13)
    static let action: Font = reading.weight(.medium)
    static let selected: Font = reading.weight(.semibold)
    static let heading: Font = .system(size: 15, weight: .semibold)
    static let resolution: Font = .system(size: 20, weight: .medium)
    static let detail: Font = .system(size: 12)
    static let label: Font = detail.weight(.medium)
    static let detailInk = Color.primary.opacity(0.80)
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

    private var trailingContentInset: CGFloat {
        // Legacy scrollers already reserve layout width. Only overlay rails
        // share the content viewport and need supplemental clearance.
        let usesOverlayModes = viewModel.selectedSection == .allModes &&
            NSScroller.preferredScrollerStyle == .overlay
        return PanelGrid.edge + (usesOverlayModes ? PanelGrid.modeScrollerClearance : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .measurePanelHeight(.header)

            ScrollView(.vertical, showsIndicators: viewModel.selectedSection == .allModes) {
                pageBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, PanelGrid.edge)
                    .padding(.trailing, trailingContentInset)
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
                    .font(PanelType.heading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Button {
                        viewModel.selectedSection = .displays
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .focused($navigationFocus, equals: .back)
                    .accessibilityLabel("返回显示器首页")
                    .help("返回")

                    Text(viewModel.selectedSection.title)
                        .font(PanelType.heading)
                        .accessibilityAddTraits(.isHeader)
                }

                if viewModel.selectedSection == .allModes, let display = selectedDisplay {
                    modeContext(for: display)
                }
            }
            .padding(.horizontal, PanelGrid.rowInset)
            .padding(.top, 10)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelGrid.edge)
        }
    }

    private func modeContext(for display: DisplaySnapshot) -> some View {
        let name = displayName(display)
        let resolution = display.currentMode.map { "当前 \($0.logicalResolution)" }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(name).fixedSize()
                if let resolution {
                    Spacer(minLength: 4)
                    Text(resolution).monospacedDigit().fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let resolution { Text(resolution).monospacedDigit() }
            }
        }
        .font(PanelType.detail)
        .foregroundStyle(PanelType.detailInk)
        .help(name)
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
                        Text(displayName(display)).font(PanelType.action).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("选择显示器")
                    .accessibilityValue(displayName(display))
                    .help(displayName(display))
                } else {
                    Text(displayName(display))
                        .font(PanelType.action).lineLimit(1).help(displayName(display))
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
                        .font(PanelType.resolution).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Text(mode.isHiDPI ? "当前 · 2× HiDPI" : "当前 · 非 HiDPI")
                        .font(PanelType.detail)
                        .foregroundStyle(PanelType.detailInk)
                        .fixedSize()
                    Text(mode.presentationRefresh)
                        .font(PanelType.detail).monospacedDigit()
                        .foregroundStyle(PanelType.detailInk)
                        .fixedSize()
                    Color.clear.frame(width: PanelGrid.markWidth, height: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("当前分辨率 \(mode.logicalResolution)，\(mode.isHiDPI ? "2× HiDPI" : "非 HiDPI")，\(mode.presentationRefresh)，渲染尺寸 \(mode.backingResolution)")
                .help("渲染尺寸 \(mode.backingResolution)")
            } else {
                Text("无法读取当前分辨率").font(PanelType.reading).foregroundStyle(.secondary)
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
                        .font(PanelType.reading).foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    SectionLabel(title: viewModel.selectedSection == .displays ? "快捷分辨率" : "2× HiDPI 分辨率")
                        .padding(.leading, PanelGrid.rowInset)
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
                    routeButton("系统工具", icon: "gearshape", section: .controls, focus: .tools)
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
                Text(title).font(PanelType.action)
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
        case "moon": CGSize(width: 1, height: -1)
        default: .zero
        }
    }

    var body: some View {
        Group {
            if name == "displayOff" {
                DisplayOffGlyph()
                    .frame(width: 17, height: 16)
            } else {
                Image(systemName: name)
                    .font(.system(size: role.size, weight: .medium))
                    .symbolRenderingMode(.monochrome)
            }
        }
            .frame(width: role.slot, height: 20)
            .offset(x: opticalOffset.width, y: opticalOffset.height)
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }
}

/// A monitor crossed out, distinct from the crescent used for appearance.
private struct DisplayOffGlyph: View {
    var body: some View {
        Path { path in
            // Break the outline where the slash crosses rather than drawing on top of it.
            path.move(to: CGPoint(x: 7, y: 3))
            path.addLine(to: CGPoint(x: 14, y: 3))
            path.addQuadCurve(to: CGPoint(x: 15.5, y: 4.5), control: CGPoint(x: 15.5, y: 3))
            path.addLine(to: CGPoint(x: 15.5, y: 11))
            path.move(to: CGPoint(x: 1.5, y: 6))
            path.addLine(to: CGPoint(x: 1.5, y: 10.5))
            path.addQuadCurve(to: CGPoint(x: 3, y: 12), control: CGPoint(x: 1.5, y: 12))
            path.addLine(to: CGPoint(x: 10, y: 12))
            path.move(to: CGPoint(x: 8, y: 12))
            path.addLine(to: CGPoint(x: 8, y: 14.5))
            path.move(to: CGPoint(x: 5.5, y: 14.5))
            path.addLine(to: CGPoint(x: 10.5, y: 14.5))
            path.move(to: CGPoint(x: 2, y: 1.5))
            path.addLine(to: CGPoint(x: 15, y: 14.5))
        }
        .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
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
            HStack(alignment: .firstTextBaseline, spacing: PanelGrid.columnGap) {
                Text(mode.logicalResolution)
                    .font(isSelected ? PanelType.selected : PanelType.reading)
                    .monospacedDigit()
                Spacer(minLength: 6)
                Text(showsRefreshRate ? (mode.refreshRate > 0 ? compactRefresh : "自动") : "")
                    .font(PanelType.detail)
                    .foregroundStyle(PanelType.detailInk)
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
                .frame(width: PanelGrid.markWidth, height: 18)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
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
            toolSectionLabel("系统开关")

            VStack(spacing: 0) {
                ToggleControlRow(
                    icon: "cup.and.saucer",
                    title: "防休眠",
                    subtitle: viewModel.controls.keepAwake ? "退出 App 时自动关闭" : "阻止系统休眠和自动屏保",
                    isOn: binding(viewModel.controls.keepAwake, action: viewModel.setKeepAwake),
                    isBusy: viewModel.activeControl == .keepAwake,
                    isInteractionDisabled: viewModel.activeControl != nil
                )
                rowDivider
                ToggleControlRow(
                    icon: "moon",
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
                    icon: "eye",
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

            toolSectionLabel("快捷动作")

            VStack(spacing: 0) {
                ActionRow(
                    icon: "play.rectangle",
                    title: "启动屏幕保护程序",
                    isBusy: viewModel.activeControl == .screenSaver,
                    isInteractionDisabled: viewModel.activeControl != nil,
                    action: viewModel.startScreenSaver
                )
                rowDivider
                ActionRow(
                    icon: "displayOff",
                    title: "立即关闭显示器",
                    isBusy: viewModel.activeControl == .displaySleep,
                    isInteractionDisabled: viewModel.activeControl != nil,
                    action: viewModel.sleepDisplays
                )
            }
            .controlGroupStyle()
        }
    }

    private func toolSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(PanelType.label)
            .foregroundStyle(PanelType.detailInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, PanelGrid.rowInset)
            .accessibilityAddTraits(.isHeader)
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
                    .font(PanelType.action)
                Text(subtitle)
                    .font(PanelType.detail)
                    .foregroundStyle(PanelType.detailInk)
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
        .frame(minHeight: 42)
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
                    .font(PanelType.action)
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
            .font(PanelType.label)
            .foregroundStyle(PanelType.detailInk)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(PanelType.detail)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if let action = feedback.action {
                Button(action.title) {
                    onAction(action)
                }
                .buttonStyle(.link)
                .font(PanelType.action)
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
                .font(PanelType.action)
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
            .font(PanelType.action)
            .foregroundStyle(.primary)
            .frame(minWidth: 28, minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}
