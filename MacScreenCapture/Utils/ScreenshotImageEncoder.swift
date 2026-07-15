import AppKit

enum ScreenshotImageEncoder {
    static func data(
        for image: NSImage,
        fileType: NSBitmapImageRep.FileType,
        properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
    ) -> Data? {
        HighResolutionImageRenderer.bitmapRepresentation(of: image)?
            .representation(using: fileType, properties: properties)
    }
}
