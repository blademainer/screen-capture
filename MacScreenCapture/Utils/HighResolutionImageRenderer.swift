import AppKit

enum HighResolutionImageRenderer {
    static let maximumPixelCount = 80_000_000

    static func canRender(logicalSize: CGSize, pixelScale: CGFloat) -> Bool {
        pixelDimensions(logicalSize: logicalSize, pixelScale: pixelScale) != nil
    }

    static func render(
        logicalSize: CGSize,
        pixelScale: CGFloat,
        drawing: (CGRect) -> Void
    ) -> NSImage? {
        guard let dimensions = pixelDimensions(
            logicalSize: logicalSize,
            pixelScale: pixelScale
        ) else { return nil }

        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: dimensions.width,
            pixelsHigh: dimensions.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        representation.size = logicalSize
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(origin: .zero, size: logicalSize))
        drawing(CGRect(origin: .zero, size: logicalSize))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: logicalSize)
        image.addRepresentation(representation)
        return image
    }

    static func pixelSize(of image: NSImage) -> CGSize {
        if let bitmap = largestBitmapRepresentation(of: image) {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    static func pixelScale(of image: NSImage) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        let pixels = pixelSize(of: image)
        return normalizedScale(max(
            pixels.width / image.size.width,
            pixels.height / image.size.height
        ))
    }

    static func bitmapRepresentation(of image: NSImage) -> NSBitmapImageRep? {
        if let bitmap = largestBitmapRepresentation(of: image),
           let cgImage = bitmap.cgImage {
            let representation = NSBitmapImageRep(cgImage: cgImage)
            representation.size = image.size
            return representation
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = image.size
        return representation
    }

    static func normalizedScale(_ scale: CGFloat) -> CGFloat {
        scale.isFinite && scale > 0 ? scale : 1
    }

    private static func pixelDimensions(
        logicalSize: CGSize,
        pixelScale: CGFloat
    ) -> (width: Int, height: Int)? {
        guard logicalSize.width.isFinite,
              logicalSize.height.isFinite,
              logicalSize.width > 0,
              logicalSize.height > 0 else {
            return nil
        }

        let scale = normalizedScale(pixelScale)
        let rawWidth = ceil(logicalSize.width * scale)
        let rawHeight = ceil(logicalSize.height * scale)
        guard rawWidth.isFinite,
              rawHeight.isFinite,
              rawWidth <= CGFloat(Int.max),
              rawHeight <= CGFloat(Int.max) else {
            return nil
        }

        let width = max(1, Int(rawWidth))
        let height = max(1, Int(rawHeight))
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow, pixelCount <= maximumPixelCount else { return nil }
        return (width, height)
    }

    private static func largestBitmapRepresentation(of image: NSImage) -> NSBitmapImageRep? {
        image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max {
                $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
            }
    }
}
