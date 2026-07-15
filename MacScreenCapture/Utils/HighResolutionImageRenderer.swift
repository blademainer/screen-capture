import AppKit

enum HighResolutionImageRenderer {
    static func render(
        logicalSize: CGSize,
        pixelScale: CGFloat,
        drawing: (CGRect) -> Void
    ) -> NSImage? {
        guard logicalSize.width.isFinite,
              logicalSize.height.isFinite,
              logicalSize.width > 0,
              logicalSize.height > 0 else {
            return nil
        }

        let scale = normalizedScale(pixelScale)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(logicalSize.width * scale))),
            pixelsHigh: max(1, Int(ceil(logicalSize.height * scale))),
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

    private static func largestBitmapRepresentation(of image: NSImage) -> NSBitmapImageRep? {
        image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max {
                $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh
            }
    }
}
