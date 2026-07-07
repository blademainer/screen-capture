import AppKit
import Foundation

struct FloatingWindowConfiguration: Equatable {
    static let defaultOpacity: CGFloat = 0.95
    static let minimumOpacity: CGFloat = 0.3
    static let maximumOpacity: CGFloat = 1.0
    static let maximumImageSize = CGSize(width: 800, height: 600)
    static let minimumWindowSize = CGSize(width: 400, height: 300)
    static let chromeHeight: CGFloat = 120

    let alwaysOnTop: Bool
    let showShadow: Bool
    let opacity: CGFloat
    let closeAfterSave: Bool

    var windowLevel: NSWindow.Level {
        alwaysOnTop ? .floating : .normal
    }

    init(
        alwaysOnTop: Bool = true,
        showShadow: Bool = true,
        opacity: Double = Double(defaultOpacity),
        closeAfterSave: Bool = false
    ) {
        self.alwaysOnTop = alwaysOnTop
        self.showShadow = showShadow
        self.opacity = Self.normalizedOpacity(opacity)
        self.closeAfterSave = closeAfterSave
    }

    static func fromDefaults(_ defaults: UserDefaults = .standard) -> FloatingWindowConfiguration {
        FloatingWindowConfiguration(
            alwaysOnTop: defaults.object(forKey: "floatingWindowAlwaysOnTop") as? Bool ?? true,
            showShadow: defaults.object(forKey: "floatingWindowShowShadow") as? Bool ?? true,
            opacity: defaults.double(forKey: "floatingWindowOpacity"),
            closeAfterSave: defaults.bool(forKey: "floatingWindowCloseAfterSave")
        )
    }

    static func normalizedOpacity(_ value: Double) -> CGFloat {
        guard value.isFinite, value > 0 else {
            return defaultOpacity
        }
        return min(max(CGFloat(value), minimumOpacity), maximumOpacity)
    }

    static func preferredWindowSize(
        for imageSize: CGSize,
        maximumImageSize: CGSize = maximumImageSize,
        minimumWindowSize: CGSize = minimumWindowSize,
        chromeHeight: CGFloat = chromeHeight
    ) -> CGSize {
        guard imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0
        else {
            return minimumWindowSize
        }

        let scale = min(
            1,
            maximumImageSize.width / imageSize.width,
            maximumImageSize.height / imageSize.height
        )
        let imageWindowSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGSize(
            width: max(minimumWindowSize.width, imageWindowSize.width),
            height: max(minimumWindowSize.height, imageWindowSize.height + chromeHeight)
        )
    }
}

enum FloatingWindowLayout {
    static let cascadeOffset: CGFloat = 30

    static func origin(
        for windowSize: CGSize,
        existingWindowFrames: [CGRect],
        visibleFrame: CGRect,
        cascadeOffset: CGFloat = cascadeOffset
    ) -> CGPoint {
        guard let firstFrame = existingWindowFrames.first else {
            return centeredOrigin(for: windowSize, in: visibleFrame)
        }

        let offset = cascadeOffset * CGFloat(existingWindowFrames.count)
        let proposedOrigin = CGPoint(
            x: firstFrame.origin.x + offset,
            y: firstFrame.origin.y - offset
        )
        return clampedOrigin(
            proposedOrigin,
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )
    }

    static func centeredOrigin(for windowSize: CGSize, in visibleFrame: CGRect) -> CGPoint {
        clampedOrigin(
            CGPoint(
                x: visibleFrame.midX - windowSize.width / 2,
                y: visibleFrame.midY - windowSize.height / 2
            ),
            windowSize: windowSize,
            visibleFrame: visibleFrame
        )
    }

    static func clampedOrigin(
        _ origin: CGPoint,
        windowSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        return CGPoint(
            x: min(max(origin.x, visibleFrame.minX), maxX),
            y: min(max(origin.y, visibleFrame.minY), maxY)
        )
    }
}
