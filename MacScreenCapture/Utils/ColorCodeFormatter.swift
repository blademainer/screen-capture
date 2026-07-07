import AppKit
import Foundation

struct ColorCodeFormatter {
    static func formattedColorCode(for color: NSColor, format: String, customTemplate: String = "{hex}") -> String {
        let components = sRGBComponents(for: color)
        let hex = hexString(red: components.red255, green: components.green255, blue: components.blue255)
        let rgb = "rgb(\(components.red255), \(components.green255), \(components.blue255))"

        switch format {
        case "RGB":
            return rgb
        case "SwiftUI":
            return String(
                format: "Color(red: %.3f, green: %.3f, blue: %.3f)",
                components.red,
                components.green,
                components.blue
            )
        case "Custom":
            return customTemplate
                .replacingOccurrences(of: "{hex}", with: hex)
                .replacingOccurrences(of: "{rgb}", with: rgb)
                .replacingOccurrences(of: "{r255}", with: "\(components.red255)")
                .replacingOccurrences(of: "{g255}", with: "\(components.green255)")
                .replacingOccurrences(of: "{b255}", with: "\(components.blue255)")
                .replacingOccurrences(of: "{r}", with: String(format: "%.3f", components.red))
                .replacingOccurrences(of: "{g}", with: String(format: "%.3f", components.green))
                .replacingOccurrences(of: "{b}", with: String(format: "%.3f", components.blue))
        default:
            return hex
        }
    }

    static func approximateColorName(for color: NSColor) -> String {
        let components = sRGBComponents(for: color)
        return palette.min { lhs, rhs in
            colorDistanceSquared(components.red255, components.green255, components.blue255, lhs) <
                colorDistanceSquared(components.red255, components.green255, components.blue255, rhs)
        }?.name ?? "未知颜色"
    }

    static func colorFromHex(_ hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespacesAndNewlines))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        return NSColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static let palette: [(name: String, r: Int, g: Int, b: Int)] = [
        ("黑色", 0, 0, 0), ("白色", 255, 255, 255), ("灰色", 128, 128, 128),
        ("红色", 220, 38, 38), ("橙色", 249, 115, 22), ("黄色", 234, 179, 8),
        ("绿色", 34, 197, 94), ("青色", 6, 182, 212), ("蓝色", 59, 130, 246),
        ("矢车菊蓝", 100, 149, 237), ("紫色", 147, 51, 234), ("粉色", 236, 72, 153),
        ("棕色", 120, 72, 35), ("米色", 245, 245, 220), ("深蓝", 30, 64, 175)
    ]

    private static func sRGBComponents(for color: NSColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, red255: Int, green255: Int, blue255: Int) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let red = clamp01(rgb.redComponent)
        let green = clamp01(rgb.greenComponent)
        let blue = clamp01(rgb.blueComponent)
        return (
            red,
            green,
            blue,
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
    }

    private static func hexString(red: Int, green: Int, blue: Int) -> String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func colorDistanceSquared(_ red: Int, _ green: Int, _ blue: Int, _ candidate: (name: String, r: Int, g: Int, b: Int)) -> Int {
        let dr = red - candidate.r
        let dg = green - candidate.g
        let db = blue - candidate.b
        return dr * dr + dg * dg + db * db
    }

    private static func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
