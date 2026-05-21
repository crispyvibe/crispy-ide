import AppKit
import SwiftUI

struct ProjectColorTag: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    init(color: Color) {
        let nsColor = NSColor(color)
        let srgb = nsColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor(srgbRed: 0.21, green: 0.56, blue: 0.91, alpha: 1.0)
        self.init(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    var storageToken: String {
        Self.hexString(red: red, green: green, blue: blue, alpha: alpha)
    }

    init?(storageToken: String) {
        guard let parsedHex = Self.fromHex(storageToken) else {
            return nil
        }
        self = parsedHex
    }

    private static func clamp(_ value: Double) -> Double {
        max(0.0, min(1.0, value))
    }

    private static func componentToByte(_ value: Double) -> Int {
        Int((clamp(value) * 255.0).rounded())
    }

    private static func hexString(red: Double, green: Double, blue: Double, alpha: Double) -> String {
        let r = componentToByte(red)
        let g = componentToByte(green)
        let b = componentToByte(blue)
        let a = componentToByte(alpha)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    private static func fromHex(_ rawValue: String) -> ProjectColorTag? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6 || hex.count == 8 else { return nil }
        guard let value = UInt64(hex, radix: 16) else { return nil }

        if hex.count == 6 {
            let r = Double((value & 0xFF0000) >> 16) / 255.0
            let g = Double((value & 0x00FF00) >> 8) / 255.0
            let b = Double(value & 0x0000FF) / 255.0
            return ProjectColorTag(red: r, green: g, blue: b, alpha: 1.0)
        }

        let r = Double((value & 0xFF000000) >> 24) / 255.0
        let g = Double((value & 0x00FF0000) >> 16) / 255.0
        let b = Double((value & 0x0000FF00) >> 8) / 255.0
        let a = Double(value & 0x000000FF) / 255.0
        return ProjectColorTag(red: r, green: g, blue: b, alpha: a)
    }

}

extension ProjectColorTag {
    var nsColor: NSColor {
        let srgb = NSColor(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
        return srgb
    }

    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        let r = channel(red)
        let g = channel(green)
        let b = channel(blue)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
