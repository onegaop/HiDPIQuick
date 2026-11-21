import CoreGraphics
import Foundation

struct DisplayMode: Identifiable, Equatable {
    let id: String
    let displayID: CGDirectDisplayID
    let modeID: Int32
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double

    init(displayID: CGDirectDisplayID, mode: CGDisplayMode) {
        self.displayID = displayID
        self.modeID = mode.ioDisplayModeID
        self.width = mode.width
        self.height = mode.height
        self.pixelWidth = mode.pixelWidth
        self.pixelHeight = mode.pixelHeight
        self.refreshRate = mode.refreshRate
        self.id = [
            String(displayID),
            String(mode.ioDisplayModeID),
            String(mode.width),
            String(mode.height),
            String(mode.pixelWidth),
            String(mode.pixelHeight),
            String(format: "%.2f", mode.refreshRate)
        ].joined(separator: "-")
    }

    var isHiDPI: Bool {
        pixelWidth == width * 2 && pixelHeight == height * 2
    }

    var logicalResolution: String {
        "\(width) × \(height)"
    }

    var backingResolution: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var refreshRateText: String {
        refreshRate > 0 ? "\(Int(refreshRate.rounded())) Hz" : "刷新率由系统管理"
    }

    func matches(_ other: DisplayMode) -> Bool {
        modeID == other.modeID &&
            width == other.width &&
            height == other.height &&
            pixelWidth == other.pixelWidth &&
            pixelHeight == other.pixelHeight &&
            abs(refreshRate - other.refreshRate) < 0.01
    }
}

struct DisplaySnapshot: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let currentMode: DisplayMode?
    let modes: [DisplayMode]

    var isHiDPIActive: Bool {
        currentMode?.isHiDPI == true
    }

    var featuredModes: [DisplayMode] {
        guard !modes.isEmpty else { return [] }

        var indexes = Set([0])
        if let currentMode, let currentIndex = modes.firstIndex(where: { currentMode.matches($0) }) {
            indexes.insert(max(0, currentIndex - 1))
            indexes.insert(currentIndex)
            indexes.insert(min(modes.count - 1, currentIndex + 1))
        } else {
            indexes.formUnion(0..<min(3, modes.count))
        }

        for index in modes.indices where indexes.count < min(3, modes.count) {
            indexes.insert(index)
        }
        return indexes.sorted().prefix(4).map { modes[$0] }
    }

    var additionalModes: [DisplayMode] {
        let featuredIDs = Set(featuredModes.map(\.id))
        return modes.filter { !featuredIDs.contains($0.id) }
    }
}

struct SystemControlSnapshot: Equatable {
    let keepAwake: Bool
    let darkMode: Bool
    let desktopIconsHidden: Bool
    let hiddenFilesVisible: Bool
    let dockAutoHide: Bool

    func updating(_ identifier: ControlIdentifier, to value: Bool) -> SystemControlSnapshot {
        SystemControlSnapshot(
            keepAwake: identifier == .keepAwake ? value : keepAwake,
            darkMode: identifier == .darkMode ? value : darkMode,
            desktopIconsHidden: identifier == .desktopIcons ? value : desktopIconsHidden,
            hiddenFilesVisible: identifier == .hiddenFiles ? value : hiddenFilesVisible,
            dockAutoHide: identifier == .dockAutoHide ? value : dockAutoHide
        )
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case displays
    case allModes
    case controls

    var id: String { rawValue }

    var title: String {
        switch self {
        case .displays: return "显示器"
        case .allModes: return "全部模式"
        case .controls: return "系统工具"
        }
    }
}

enum ControlIdentifier: String {
    case keepAwake
    case darkMode
    case desktopIcons
    case hiddenFiles
    case dockAutoHide
    case screenSaver
    case displaySleep
}

enum FeedbackTone {
    case success
    case warning
}

enum FeedbackAction {
    case openAutomationSettings
    case openDisplaysSettings

    var title: String {
        switch self {
        case .openAutomationSettings: return "打开权限设置"
        case .openDisplaysSettings: return "打开显示器设置"
        }
    }
}

struct AppFeedback: Identifiable {
    let id = UUID()
    let message: String
    let tone: FeedbackTone
    let action: FeedbackAction?
}
