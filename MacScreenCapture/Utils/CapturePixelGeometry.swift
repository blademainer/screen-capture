import CoreGraphics

enum CapturePixelGeometry {
    static func logicalContentSize(contentRect: CGRect, fallback: CGSize) -> CGSize {
        guard !contentRect.isNull,
              !contentRect.isEmpty,
              contentRect.width.isFinite,
              contentRect.height.isFinite,
              contentRect.width > 0,
              contentRect.height > 0 else {
            return fallback
        }
        return contentRect.size
    }

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

    static func displayID(containing rect: CGRect) -> CGDirectDisplayID? {
        guard !rect.isNull, !rect.isEmpty else { return nil }

        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let error = displays.withUnsafeMutableBufferPointer { buffer in
            CGGetDisplaysWithRect(
                rect,
                UInt32(buffer.count),
                buffer.baseAddress,
                &count
            )
        }
        guard error == .success, count > 0 else { return nil }

        return displays.prefix(Int(count)).max { first, second in
            CGDisplayBounds(first).intersection(rect).area < CGDisplayBounds(second).intersection(rect).area
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
