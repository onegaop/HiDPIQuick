import Cocoa
import CoreGraphics
import IOKit
import IOKit.graphics

enum DisplayManager {
    static func snapshots() -> [DisplaySnapshot] {
        activeDisplays().map { display in
            let currentMode = CGDisplayCopyDisplayMode(display.id).map {
                DisplayMode(displayID: display.id, mode: $0)
            }

            return DisplaySnapshot(
                id: display.id,
                name: display.name,
                isBuiltin: display.isBuiltin,
                currentMode: currentMode,
                modes: hiDPIModes(for: display.id)
            )
        }
    }

    static func applyMode(_ mode: DisplayMode, option: CGConfigureOption) -> CGError {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard
            let allModes = CGDisplayCopyAllDisplayModes(mode.displayID, options) as? [CGDisplayMode],
            let target = allModes.first(where: { matches($0, mode) })
        else {
            return .failure
        }

        var configuration: CGDisplayConfigRef?
        let beginError = CGBeginDisplayConfiguration(&configuration)
        guard beginError == .success else {
            return beginError
        }

        let configureError = CGConfigureDisplayWithDisplayMode(
            configuration,
            mode.displayID,
            target,
            nil
        )
        guard configureError == .success else {
            CGCancelDisplayConfiguration(configuration)
            return configureError
        }

        return CGCompleteDisplayConfiguration(configuration, option)
    }

    @discardableResult
    static func openDisplaysSettings() -> Bool {
        let candidates = [
            "x-apple.systempreferences:com.apple.Displays-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.displays"
        ]

        for value in candidates {
            guard let url = URL(string: value) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }

    private struct DisplayIdentity {
        let id: CGDirectDisplayID
        let name: String
        let isBuiltin: Bool
    }

    private static func activeDisplays() -> [DisplayIdentity] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }

        return ids.map { displayID in
            DisplayIdentity(
                id: displayID,
                name: displayName(for: displayID),
                isBuiltin: CGDisplayIsBuiltin(displayID) != 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.isBuiltin != rhs.isBuiltin {
                return !lhs.isBuiltin
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func hiDPIModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let allModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else {
            return []
        }

        var bestByLogicalSize: [String: CGDisplayMode] = [:]
        for mode in allModes where isHiDPI(mode) && mode.isUsableForDesktopGUI() {
            guard mode.width >= 1000 || CGDisplayIsBuiltin(displayID) != 0 else { continue }

            let key = "\(mode.width)x\(mode.height)"
            if let current = bestByLogicalSize[key], current.refreshRate >= mode.refreshRate {
                continue
            }
            bestByLogicalSize[key] = mode
        }

        return bestByLogicalSize.values
            .sorted {
                if $0.width == $1.width {
                    return $0.height > $1.height
                }
                return $0.width > $1.width
            }
            .map { DisplayMode(displayID: displayID, mode: $0) }
    }

    private static func isHiDPI(_ mode: CGDisplayMode) -> Bool {
        mode.pixelWidth == mode.width * 2 && mode.pixelHeight == mode.height * 2
    }

    private static func matches(_ lhs: CGDisplayMode, _ rhs: DisplayMode) -> Bool {
        lhs.ioDisplayModeID == rhs.modeID &&
            lhs.width == rhs.width &&
            lhs.height == rhs.height &&
            lhs.pixelWidth == rhs.pixelWidth &&
            lhs.pixelHeight == rhs.pixelHeight &&
            abs(lhs.refreshRate - rhs.refreshRate) < 0.01
    }

    private static func displayName(for displayID: CGDirectDisplayID) -> String {
        if let localizedName = NSScreen.screens.first(where: { screen in
            guard
                let screenNumber = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? NSNumber
            else {
                return false
            }
            return screenNumber.uint32Value == displayID
        })?.localizedName, !localizedName.isEmpty {
            return localizedName
        }

        if let name = displayNameFromIOKit(
            vendorID: CGDisplayVendorNumber(displayID),
            productID: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID)
        ) {
            return name
        }

        if CGDisplayIsBuiltin(displayID) != 0 {
            return "内建显示器"
        }

        let vendor = String(CGDisplayVendorNumber(displayID), radix: 16)
        let product = String(CGDisplayModelNumber(displayID), radix: 16)
        return "显示器 \(vendor):\(product)"
    }

    private static func displayNameFromIOKit(
        vendorID: UInt32,
        productID: UInt32,
        serialNumber: UInt32
    ) -> String? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            let info = IODisplayCreateInfoDictionary(
                service,
                IOOptionBits(kIODisplayOnlyPreferredName)
            ).takeRetainedValue() as NSDictionary

            let serviceVendorID = (info["DisplayVendorID"] as? NSNumber)?.uint32Value
            let serviceProductID = (info["DisplayProductID"] as? NSNumber)?.uint32Value
            let serviceSerialNumber = (info["DisplaySerialNumber"] as? NSNumber)?.uint32Value
            let matchesDisplay =
                serviceVendorID == vendorID &&
                serviceProductID == productID &&
                (serialNumber == 0 || serviceSerialNumber == nil || serviceSerialNumber == serialNumber)

            if
                matchesDisplay,
                let names = info["DisplayProductName"] as? [String: String],
                let name = names.values.first,
                !name.isEmpty
            {
                IOObjectRelease(service)
                return name
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return nil
    }
}
