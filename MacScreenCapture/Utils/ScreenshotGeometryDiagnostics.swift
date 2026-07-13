import Foundation
import CoreGraphics

enum ScreenshotGeometryDiagnostics {
    struct DisplayFrame {
        let displayID: UInt32
        let captureFrame: CGRect
        let screenFrame: CGRect
    }

    private static let logQueue = DispatchQueue(label: "com.blademainer.MacScreenCapture.screenshot-geometry-diagnostics")
    private static let maxLogFileSize = 512 * 1024
    private static let signatureLock = NSLock()
    private static var lastSignatures: [String: String] = [:]

    static func logCaptureSelectedRegion(captureRect: CGRect, displayFrames: [DisplayFrame]) {
        let displays = displayFrames
            .map { "display(id=\($0.displayID),capture=\(rect($0.captureFrame)),screen=\(rect($0.screenFrame)))" }
            .joined(separator: "|")
        append(event: "capture_selected_region", fields: [
            "capture_rect": rect(captureRect),
            "display_count": "\(displayFrames.count)",
            "displays": displays
        ])
    }

    static func logDisplayCropMapping(
        displayID: UInt32,
        displayFrame: CGRect,
        sourceRect: CGRect,
        displayImageSize: CGSize,
        pixelCropRect: CGRect
    ) {
        append(event: "display_crop_mapping", fields: [
            "display_id": "\(displayID)",
            "display_frame": rect(displayFrame),
            "source_rect": rect(sourceRect),
            "display_image_size": size(displayImageSize),
            "pixel_crop_rect": rect(pixelCropRect)
        ])
    }

    static func logCaptureSegment(
        displayID: UInt32,
        displayFrame: CGRect,
        segmentRect: CGRect,
        displayImageSize: CGSize,
        cropImageSize: CGSize
    ) {
        append(event: "capture_segment", fields: [
            "display_id": "\(displayID)",
            "display_frame": rect(displayFrame),
            "segment_rect": rect(segmentRect),
            "display_image_size": size(displayImageSize),
            "crop_image_size": size(cropImageSize)
        ])
    }

    static func logCaptureCompositeSegment(
        captureRect: CGRect,
        sourceRect: CGRect,
        drawRect: CGRect,
        segmentImageSize: CGSize
    ) {
        append(event: "capture_composite_segment", fields: [
            "capture_rect": rect(captureRect),
            "source_rect": rect(sourceRect),
            "draw_rect": rect(drawRect),
            "segment_image_size": size(segmentImageSize)
        ])
    }

    static func logCaptureResult(captureRect: CGRect, resultImageSize: CGSize, segmentCount: Int) {
        append(event: "capture_result", fields: [
            "capture_rect": rect(captureRect),
            "result_image_size": size(resultImageSize),
            "segment_count": "\(segmentCount)"
        ])
    }

    static func logEditorWindowOpened(imageSize: CGSize, windowFrame: CGRect) {
        append(event: "editor_window_opened", fields: [
            "image_size": size(imageSize),
            "window_frame": rect(windowFrame)
        ])
    }

    static func logEditorLayout(
        imageSize: CGSize,
        windowSize: CGSize,
        availableSize: CGSize,
        frameSize: CGSize,
        surfacePadding: CGFloat
    ) {
        appendDeduplicated(event: "editor_layout", fields: [
            "image_size": size(imageSize),
            "window_size": size(windowSize),
            "available_size": size(availableSize),
            "frame_size": size(frameSize),
            "surface_padding": number(surfacePadding)
        ])
    }

    static func logCanvasLayout(
        imageSize: CGSize,
        canvasBounds: CGRect,
        imageDisplayRect: CGRect,
        imageScale: CGFloat
    ) {
        appendDeduplicated(event: "canvas_layout", fields: [
            "image_size": size(imageSize),
            "canvas_bounds": rect(canvasBounds),
            "image_display_rect": rect(imageDisplayRect),
            "image_scale": number(imageScale)
        ])
    }

    private static func appendDeduplicated(event: String, fields: [String: String]) {
        let signature = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")

        signatureLock.lock()
        let shouldAppend = lastSignatures[event] != signature
        if shouldAppend {
            lastSignatures[event] = signature
        }
        signatureLock.unlock()

        guard shouldAppend else { return }
        append(event: event, fields: fields)
    }

    private static func append(event: String, fields: [String: String]) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let fieldText = fields
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let line = "\(timestamp) screenshot_geometry event=\(event) \(fieldText)\n"

        logQueue.async {
            do {
                let logURL = persistentLogURL()
                let fileManager = FileManager.default
                try fileManager.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                if let attributes = try? fileManager.attributesOfItem(atPath: logURL.path),
                   let size = attributes[.size] as? NSNumber,
                   size.intValue > maxLogFileSize {
                    try? fileManager.removeItem(at: logURL)
                }

                guard let data = line.data(using: .utf8) else { return }
                if fileManager.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: logURL, options: .atomic)
                }
            } catch {
                print("failed_to_append_screenshot_geometry_record error=\(error.localizedDescription)")
            }
        }
    }

    private static func persistentLogURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacScreenCapture", isDirectory: true)
            .appendingPathComponent("screenshot-geometry.log")
    }

    static func rect(_ rect: CGRect) -> String {
        "rect(x:\(number(rect.origin.x)),y:\(number(rect.origin.y)),w:\(number(rect.size.width)),h:\(number(rect.size.height)))"
    }

    static func size(_ size: CGSize) -> String {
        "size(w:\(number(size.width)),h:\(number(size.height)))"
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}
