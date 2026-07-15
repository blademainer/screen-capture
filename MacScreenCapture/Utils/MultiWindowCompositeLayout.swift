import CoreGraphics
import Foundation

struct MultiWindowCompositeLayout {
    struct WindowPlacement: Equatable {
        let sourceRect: CGRect
        let drawRect: CGRect
    }

    struct BackdropSegment: Equatable {
        let visibleRect: CGRect
        let drawRect: CGRect
    }

    static func outputRect(for windowFrames: [CGRect], displayBounds: CGRect, padding: CGFloat = 24) -> CGRect? {
        let usableFrames = windowFrames.filter { $0.width > 1 && $0.height > 1 }
        guard var outputRect = usableFrames.first, !displayBounds.isNull, !displayBounds.isEmpty else {
            return nil
        }

        for frame in usableFrames.dropFirst() {
            outputRect = outputRect.union(frame)
        }

        let padded = outputRect.insetBy(dx: -padding, dy: -padding).intersection(displayBounds).integral
        guard padded.width > 1, padded.height > 1 else {
            return nil
        }
        return padded
    }

    static func drawRect(for screenRect: CGRect, in outputRect: CGRect) -> CGRect? {
        let visibleRect = screenRect.intersection(outputRect)
        guard visibleRect.width > 1, visibleRect.height > 1 else {
            return nil
        }

        return CGRect(
            x: visibleRect.minX - outputRect.minX,
            y: outputRect.height - (visibleRect.maxY - outputRect.minY),
            width: visibleRect.width,
            height: visibleRect.height
        )
    }

    static func windowPlacement(
        for windowRect: CGRect,
        in outputRect: CGRect,
        imageSize: CGSize
    ) -> WindowPlacement? {
        let visibleRect = windowRect.intersection(outputRect)
        guard visibleRect.width > 1,
              visibleRect.height > 1,
              windowRect.width > 0,
              windowRect.height > 0,
              imageSize.width > 0,
              imageSize.height > 0,
              let drawRect = drawRect(for: visibleRect, in: outputRect) else {
            return nil
        }

        let scaleX = imageSize.width / windowRect.width
        let scaleY = imageSize.height / windowRect.height
        let sourceRect = CGRect(
            x: (visibleRect.minX - windowRect.minX) * scaleX,
            y: (windowRect.maxY - visibleRect.maxY) * scaleY,
            width: visibleRect.width * scaleX,
            height: visibleRect.height * scaleY
        )
        return WindowPlacement(sourceRect: sourceRect, drawRect: drawRect)
    }

    static func backdropSegments(for displayBounds: [CGRect], outputRect: CGRect) -> [BackdropSegment] {
        displayBounds.compactMap { displayRect in
            let visibleRect = outputRect.intersection(displayRect)
            guard visibleRect.width > 1, visibleRect.height > 1,
                  let drawRect = drawRect(for: visibleRect, in: outputRect) else {
                return nil
            }
            return BackdropSegment(visibleRect: visibleRect, drawRect: drawRect)
        }
    }
}
