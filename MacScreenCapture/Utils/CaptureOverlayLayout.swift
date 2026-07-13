import CoreGraphics

enum CaptureOverlayLayout {
    static let edgeInset: CGFloat = 8
    static let toolbarGap: CGFloat = 8

    static func toolbarFrame(
        selection: CGRect,
        toolbarSize: CGSize,
        visibleFrame: CGRect
    ) -> CGRect {
        let safeFrame = visibleFrame.insetBy(dx: edgeInset, dy: edgeInset)
        let maximumX = max(safeFrame.minX, safeFrame.maxX - toolbarSize.width)
        let centeredX = selection.midX - toolbarSize.width / 2
        let x = min(max(centeredX, safeFrame.minX), maximumX)

        let belowY = selection.minY - toolbarGap - toolbarSize.height
        if belowY >= safeFrame.minY {
            return CGRect(origin: CGPoint(x: x, y: belowY), size: toolbarSize)
        }

        let aboveY = selection.maxY + toolbarGap
        if aboveY + toolbarSize.height <= safeFrame.maxY {
            return CGRect(origin: CGPoint(x: x, y: aboveY), size: toolbarSize)
        }

        let insideY = min(
            max(selection.minY + toolbarGap, safeFrame.minY),
            max(safeFrame.minY, safeFrame.maxY - toolbarSize.height)
        )
        return CGRect(origin: CGPoint(x: x, y: insideY), size: toolbarSize)
    }
}
