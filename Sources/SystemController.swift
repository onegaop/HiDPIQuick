import AppKit
import Foundation

enum SystemControlError: LocalizedError {
    case commandFailed(String)
    case automationDenied
    case automationFailed(String)
    case actionUnavailable(String)
    case stateNotApplied(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message.isEmpty ? "系统命令执行失败" : message
        case .automationDenied:
            return "未获得控制系统事件的权限"
        case .automationFailed(let message):
            return message.isEmpty ? "自动化操作失败，请检查系统权限" : message
        case .actionUnavailable(let message), .stateNotApplied(let message):
            return message
        }
    }
}

final class SystemController: @unchecked Sendable {
    private let processLock = NSLock()
    private var caffeinateProcess: Process?

    var snapshot: SystemControlSnapshot {
        SystemControlSnapshot(
            keepAwake: isKeepingAwake,
            darkMode: readDarkMode(),
            desktopIconsHidden: !readBooleanPreference(
                domain: "com.apple.finder",
                key: "CreateDesktop",
                fallback: true
            ),
            hiddenFilesVisible: readBooleanPreference(
                domain: "com.apple.finder",
                key: "AppleShowAllFiles",
                fallback: false
            ),
            dockAutoHide: readBooleanPreference(
                domain: "com.apple.dock",
                key: "autohide",
                fallback: false
            )
        )
    }

    func setKeepAwake(_ enabled: Bool) throws {
        processLock.lock()
        defer { processLock.unlock() }

        if enabled {
            guard caffeinateProcess?.isRunning != true else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            process.arguments = ["-dimsu"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            caffeinateProcess = process
        } else {
            stopKeepingAwakeLocked()
        }
    }

    func setDarkMode(_ enabled: Bool) throws {
        let scriptSource = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(enabled ? "true" : "false")
            end tell
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else {
            throw SystemControlError.automationFailed("无法创建深色模式自动化脚本")
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            // -1743 is Apple Events' permission denial, not a generic script failure.
            if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
                throw SystemControlError.automationDenied
            }
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "请允许 HiDPI Quick 控制系统事件"
            throw SystemControlError.automationFailed(message)
        }
    }

    func setDesktopIconsHidden(_ hidden: Bool) throws {
        try writeBooleanPreference(
            domain: "com.apple.finder",
            key: "CreateDesktop",
            value: !hidden,
            restartApplication: "Finder"
        )
    }

    func setHiddenFilesVisible(_ visible: Bool) throws {
        try writeBooleanPreference(
            domain: "com.apple.finder",
            key: "AppleShowAllFiles",
            value: visible,
            restartApplication: "Finder"
        )
    }

    func setDockAutoHide(_ enabled: Bool) throws {
        try writeBooleanPreference(
            domain: "com.apple.dock",
            key: "autohide",
            value: enabled,
            restartApplication: "Dock"
        )
    }

    func startScreenSaver() throws {
        let path = "/System/Library/CoreServices/ScreenSaverEngine.app"
        guard FileManager.default.fileExists(atPath: path) else {
            throw SystemControlError.actionUnavailable("系统没有找到屏幕保护程序")
        }
        _ = try runCommand(executable: "/usr/bin/open", arguments: [path])
    }

    func sleepDisplays() throws {
        _ = try runCommand(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"])
    }

    func shutdown() {
        processLock.lock()
        defer { processLock.unlock() }
        stopKeepingAwakeLocked()
    }

    private var isKeepingAwake: Bool {
        processLock.lock()
        defer { processLock.unlock() }
        return caffeinateProcess?.isRunning == true
    }

    private func stopKeepingAwakeLocked() {
        if caffeinateProcess?.isRunning == true {
            caffeinateProcess?.terminate()
        }
        caffeinateProcess = nil
    }

    private func readDarkMode() -> Bool {
        guard let output = try? runCommand(
            executable: "/usr/bin/defaults",
            arguments: ["read", "-g", "AppleInterfaceStyle"]
        ) else {
            return false
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "dark"
    }

    private func readBooleanPreference(domain: String, key: String, fallback: Bool) -> Bool {
        guard let output = try? runCommand(
            executable: "/usr/bin/defaults",
            arguments: ["read", domain, key]
        ) else {
            return fallback
        }

        switch output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return fallback
        }
    }

    private func writeBooleanPreference(
        domain: String,
        key: String,
        value: Bool,
        restartApplication: String
    ) throws {
        _ = try runCommand(
            executable: "/usr/bin/defaults",
            arguments: ["write", domain, key, "-bool", value ? "true" : "false"]
        )
        _ = try? runCommand(executable: "/usr/bin/killall", arguments: [restartApplication])
    }

    private func runCommand(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw SystemControlError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()
        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw SystemControlError.commandFailed(
                errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}
