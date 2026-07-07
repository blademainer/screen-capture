import CoreGraphics
import Foundation

struct OCRTextOrderer {
    struct TextBox: Equatable {
        let text: String
        let boundingBox: CGRect
    }

    static func sortedTextBoxes(_ boxes: [TextBox]) -> [TextBox] {
        boxes.sorted { lhs, rhs in
            let lhsBox = lhs.boundingBox
            let rhsBox = rhs.boundingBox
            let lineTolerance = max(lhsBox.height, rhsBox.height) * 0.5
            let verticalDelta = lhsBox.midY - rhsBox.midY

            if abs(verticalDelta) > lineTolerance {
                return lhsBox.midY > rhsBox.midY
            }

            return lhsBox.minX < rhsBox.minX
        }
    }

    static func joinedText(_ boxes: [TextBox], separator: String = "\n") -> String {
        sortedTextBoxes(boxes)
            .map(\.text)
            .joined(separator: separator)
    }
}
