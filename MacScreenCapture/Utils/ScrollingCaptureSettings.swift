import Foundation

struct ScrollingCaptureSettings: Equatable {
    let sliceCount: Int
    let delay: Double
    let scrollLines: Int
    let direction: String

    static func normalizedSliceCount(_ value: Int) -> Int {
        guard value > 0 else { return 30 }
        return min(max(value, 2), 100)
    }

    static func normalizedDelay(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 0.8 }
        return min(max(value, 0.2), 2.0)
    }

    static func normalizedScrollLines(_ value: Int) -> Int {
        guard value > 0 else { return 12 }
        return min(max(value, 3), 40)
    }

    static func normalizedDirection(_ value: String?) -> String {
        value == "up" ? "up" : "down"
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> ScrollingCaptureSettings {
        ScrollingCaptureSettings(
            sliceCount: normalizedSliceCount(defaults.integer(forKey: "scrollingCaptureSlices")),
            delay: normalizedDelay(defaults.double(forKey: "scrollingCaptureDelay")),
            scrollLines: normalizedScrollLines(defaults.integer(forKey: "scrollingCaptureLines")),
            direction: normalizedDirection(defaults.string(forKey: "scrollingCaptureDirection"))
        )
    }
}
