import AppKit

/// An original, monochrome display mark. The same footprint in both states
/// keeps AppKit's native status-item hit region stable when the marker changes.
@MainActor
enum StatusMenuGlyph {
    static let canvas = NSSize(width: 20, height: 18)
    static let standard = make(isHiDPI: false)
    static let hiDPI = make(isHiDPI: true)

    private static func make(isHiDPI: Bool) -> NSImage {
        let image = NSImage(size: canvas, flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // In AppKit's bottom-up coordinates the visible ink is centered on
            // the 20 × 18 canvas. Half-point stroke centers preserve full-pixel
            // horizontal/vertical edges at standard and Retina scale.
            let display = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 5.5, width: 15, height: 10),
                                       xRadius: 1.5, yRadius: 1.5)
            display.lineWidth = 1
            display.stroke()

            NSRect(x: 9, y: 3, width: 2, height: 2).fill()
            NSRect(x: 6, y: 2, width: 8, height: 1).fill()

            if isHiDPI {
                // Two centered, separated pixels read as a quiet 2× hint.
                NSRect(x: 7, y: 10, width: 2, height: 2).fill()
                NSRect(x: 11, y: 10, width: 2, height: 2).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
