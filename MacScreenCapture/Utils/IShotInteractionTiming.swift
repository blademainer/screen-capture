import Foundation

struct IShotInteractionTiming {
    static let defaultDelayedScreenshotSeconds = 5
    static let defaultDoubleOptionInterval: TimeInterval = 0.45
    static let defaultDoubleOptionCooldown: TimeInterval = 1.0

    static func delayedScreenshotSeconds(_ value: Int) -> Int {
        value == 0 ? defaultDelayedScreenshotSeconds : min(max(value, 1), 30)
    }

    static func doubleOptionInterval(_ value: TimeInterval) -> TimeInterval {
        value == 0 ? defaultDoubleOptionInterval : min(max(value, 0.25), 1.2)
    }

    static func doubleOptionCooldown(_ value: TimeInterval) -> TimeInterval {
        value == 0 ? defaultDoubleOptionCooldown : min(max(value, 0.5), 3.0)
    }

    struct DoubleOptionDetector {
        private(set) var lastPressAt: Date?
        private(set) var lastActionAt: Date?

        mutating func registerPress(at now: Date, interval: TimeInterval, cooldown: TimeInterval) -> Bool {
            let normalizedInterval = IShotInteractionTiming.doubleOptionInterval(interval)
            let normalizedCooldown = IShotInteractionTiming.doubleOptionCooldown(cooldown)

            if let lastActionAt, now.timeIntervalSince(lastActionAt) < normalizedCooldown {
                lastPressAt = now
                return false
            }

            if let lastPressAt, now.timeIntervalSince(lastPressAt) <= normalizedInterval {
                self.lastPressAt = nil
                self.lastActionAt = now
                return true
            }

            lastPressAt = now
            return false
        }
    }
}
