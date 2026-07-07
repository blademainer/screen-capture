import AVFoundation
import Foundation

struct RecordingSettings {
    static let defaultFrameRate = 60
    static let defaultQuality = "高"
    static let defaultFileFormat = "MOV"

    static func normalizedFrameRate(_ value: Double) -> Int {
        guard value > 0, value.isFinite else {
            return defaultFrameRate
        }
        return min(60, max(15, Int(value.rounded())))
    }

    static func normalizedQuality(_ value: String?) -> String {
        guard let value, ["低", "中", "高", "超高"].contains(value) else {
            return defaultQuality
        }
        return value
    }

    static func normalizedFileFormat(_ value: String?) -> String {
        switch value?.uppercased() {
        case "MP4":
            return "MP4"
        default:
            return defaultFileFormat
        }
    }

    static func fileExtension(for format: String?) -> String {
        normalizedFileFormat(format).lowercased()
    }

    static func avFileType(for format: String?) -> AVFileType {
        normalizedFileFormat(format) == "MP4" ? .mp4 : .mov
    }

    static func videoBitRate(width: Int, height: Int, frameRate: Int, quality: String) -> Int {
        let normalizedFrameRate = min(60, max(15, frameRate))
        let pixelsPerSecond = Double(max(1, width) * max(1, height) * normalizedFrameRate)
        let bitsPerPixel: Double

        switch normalizedQuality(quality) {
        case "低":
            bitsPerPixel = 0.04
        case "中":
            bitsPerPixel = 0.07
        case "超高":
            bitsPerPixel = 0.16
        default:
            bitsPerPixel = 0.11
        }

        let calculatedBitRate = Int(pixelsPerSecond * bitsPerPixel)
        return min(max(calculatedBitRate, 2_000_000), 60_000_000)
    }
}
