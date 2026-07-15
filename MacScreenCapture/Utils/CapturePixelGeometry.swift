import CoreGraphics

enum CapturePixelGeometry {
    static func normalizedScale(_ scale: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        if scale.isFinite, scale > 0 {
            return scale
        }
        if fallback.isFinite, fallback > 0 {
            return fallback
        }
        return 1
    }

    static func outputPixelSize(logicalSize: CGSize, scale: CGFloat) -> CGSize {
        let normalized = normalizedScale(scale)
        return CGSize(
            width: max(1, ceil(logicalSize.width * normalized)),
            height: max(1, ceil(logicalSize.height * normalized))
        )
    }

    static func displayFallbackScale(displayID: CGDirectDisplayID) -> CGFloat {
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0, bounds.height > 0 else { return 1 }

        let scaleX = CGFloat(CGDisplayPixelsWide(displayID)) / bounds.width
        let scaleY = CGFloat(CGDisplayPixelsHigh(displayID)) / bounds.height
        return normalizedScale(max(scaleX, scaleY))
    }
}
