import AppKit
import CoreGraphics

struct DisplayCoordinateSpace: Equatable {
    let displayID: CGDirectDisplayID
    let captureFrame: CGRect
    let screenFrame: CGRect
}

struct CapturedRegionContext {
    let image: NSImage
    let captureRect: CGRect
    let coordinateSpaces: [DisplayCoordinateSpace]
}

struct CaptureScreenSegment: Equatable {
    let displayID: CGDirectDisplayID
    let captureRect: CGRect
    let screenRect: CGRect
    let imageRect: CGRect
}

struct CaptureCoordinateMapper {
    let spaces: [DisplayCoordinateSpace]

    func screenSegments(for captureRect: CGRect) -> [CaptureScreenSegment] {
        spaces.compactMap { space in
            let intersection = captureRect.intersection(space.captureFrame)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }

            let screenRect = CGRect(
                x: space.screenFrame.minX + (intersection.minX - space.captureFrame.minX),
                y: space.screenFrame.maxY - (intersection.maxY - space.captureFrame.minY),
                width: intersection.width,
                height: intersection.height
            )
            let imageRect = CGRect(
                x: intersection.minX - captureRect.minX,
                y: captureRect.height - (intersection.maxY - captureRect.minY),
                width: intersection.width,
                height: intersection.height
            )

            return CaptureScreenSegment(
                displayID: space.displayID,
                captureRect: intersection,
                screenRect: screenRect,
                imageRect: imageRect
            )
        }
    }
}

extension CGRect {
    func distanceSquared(to point: CGPoint) -> CGFloat {
        let clampedX = min(max(point.x, minX), maxX)
        let clampedY = min(max(point.y, minY), maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return dx * dx + dy * dy
    }
}
