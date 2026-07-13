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

    var captureBounds: CGRect {
        spaces.map(\.captureFrame).reduce(CGRect.null) { partial, frame in
            partial.isNull ? frame : partial.union(frame)
        }
    }

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

enum CaptureResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

struct CaptureSelectionGeometry {
    let initialRect: CGRect
    let bounds: CGRect
    let minimumSize: CGSize

    func moving(by delta: CGPoint) -> CGRect {
        let maxX = max(bounds.minX, bounds.maxX - initialRect.width)
        let maxY = max(bounds.minY, bounds.maxY - initialRect.height)
        return CGRect(
            x: min(max(initialRect.minX + delta.x, bounds.minX), maxX),
            y: min(max(initialRect.minY + delta.y, bounds.minY), maxY),
            width: initialRect.width,
            height: initialRect.height
        ).integral
    }

    func resizing(handle: CaptureResizeHandle, by delta: CGPoint) -> CGRect {
        var minX = initialRect.minX
        var minY = initialRect.minY
        var maxX = initialRect.maxX
        var maxY = initialRect.maxY

        if handle.affectsLeft {
            minX = min(max(initialRect.minX + delta.x, bounds.minX), initialRect.maxX - minimumSize.width)
        }
        if handle.affectsRight {
            maxX = max(min(initialRect.maxX + delta.x, bounds.maxX), initialRect.minX + minimumSize.width)
        }
        if handle.affectsTop {
            minY = min(max(initialRect.minY + delta.y, bounds.minY), initialRect.maxY - minimumSize.height)
        }
        if handle.affectsBottom {
            maxY = max(min(initialRect.maxY + delta.y, bounds.maxY), initialRect.minY + minimumSize.height)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }
}

private extension CaptureResizeHandle {
    var affectsLeft: Bool { self == .topLeft || self == .bottomLeft || self == .left }
    var affectsRight: Bool { self == .topRight || self == .bottomRight || self == .right }
    var affectsTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var affectsBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
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
