import SwiftUI
import AppKit

enum AnnotationStylePreset: String, CaseIterable {
    case professional = "professional"
    case highContrast = "high_contrast"
    case presentation = "presentation"

    var displayName: String {
        switch self {
        case .professional: return "专业"
        case .highContrast: return "高对比"
        case .presentation: return "演示"
        }
    }

    var colorHex: String {
        switch self {
        case .professional: return "#FF3B30"
        case .highContrast: return "#FFD60A"
        case .presentation: return "#0A84FF"
        }
    }

    var lineWidth: Double {
        switch self {
        case .professional: return 2
        case .highContrast: return 4
        case .presentation: return 5
        }
    }

    var textOutlined: Bool {
        switch self {
        case .professional: return false
        case .highContrast, .presentation: return true
        }
    }
}

extension Color {
    static func annotationDefault(hex: String) -> Color {
        guard let nsColor = NSColor.annotationDefault(hex: hex) else {
            return .red
        }
        return Color(nsColor: nsColor)
    }
}

extension NSColor {
    static func annotationDefault(hex: String) -> NSColor? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }

        guard clean.count == 6, let value = Int(clean, radix: 16) else {
            return nil
        }

        return NSColor(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
