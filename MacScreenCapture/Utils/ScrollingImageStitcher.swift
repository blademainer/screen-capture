import AppKit
import Foundation

struct ScrollingImageStitcher {
    static func orderedImages(_ images: [NSImage], direction: String) -> [NSImage] {
        direction == "up" ? Array(images.reversed()) : images
    }

    static func canStitch(_ images: [NSImage], trimOverlap: Bool) -> Bool {
        let normalizedImages = trimOverlap ? removeOverlappingScrollRegions(from: images) : images
        guard let geometry = outputGeometry(for: normalizedImages) else { return false }
        return HighResolutionImageRenderer.canRender(
            logicalSize: geometry.size,
            pixelScale: geometry.pixelScale
        )
    }

    static func stitchImagesVertically(_ images: [NSImage], trimOverlap: Bool) -> NSImage? {
        guard !images.isEmpty else { return nil }
        let normalizedImages = trimOverlap ? removeOverlappingScrollRegions(from: images) : images
        guard let geometry = outputGeometry(for: normalizedImages),
              HighResolutionImageRenderer.canRender(
                logicalSize: geometry.size,
                pixelScale: geometry.pixelScale
              ) else {
            return nil
        }

        return HighResolutionImageRenderer.render(
            logicalSize: geometry.size,
            pixelScale: geometry.pixelScale
        ) { _ in
            var y = geometry.size.height
            for image in normalizedImages {
                let scaledHeight = image.size.height * geometry.size.width / max(image.size.width, 1)
                y -= scaledHeight
                image.draw(in: NSRect(x: 0, y: y, width: geometry.size.width, height: scaledHeight))
            }
        }
    }

    static func imagesAreVisuallySimilar(_ previous: NSImage, _ next: NSImage) -> Bool {
        guard let previousCG = previous.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let nextCG = next.cgImage(forProposedRect: nil, context: nil, hints: nil),
              previousCG.width == nextCG.width,
              previousCG.height == nextCG.height,
              let previousBuffer = rgbaBuffer(from: previousCG),
              let nextBuffer = rgbaBuffer(from: nextCG) else {
            return false
        }

        let width = previousCG.width
        let height = previousCG.height
        let sampleXStride = max(8, width / 96)
        let sampleYStride = max(8, height / 96)
        var totalDifference = 0
        var samples = 0
        var changedSamples = 0

        for y in stride(from: 0, to: height, by: sampleYStride) {
            for x in stride(from: 0, to: width, by: sampleXStride) {
                let offset = (y * width + x) * 4
                let difference =
                    abs(Int(previousBuffer[offset]) - Int(nextBuffer[offset])) +
                    abs(Int(previousBuffer[offset + 1]) - Int(nextBuffer[offset + 1])) +
                    abs(Int(previousBuffer[offset + 2]) - Int(nextBuffer[offset + 2]))

                totalDifference += difference
                samples += 3
                if difference > 18 {
                    changedSamples += 1
                }
            }
        }

        guard samples > 0 else { return false }
        let averageDifference = Double(totalDifference) / Double(samples)
        let changedRatio = Double(changedSamples) / Double(max(1, samples / 3))
        return averageDifference < 1.8 && changedRatio < 0.015
    }

    static func detectedVerticalOverlap(previous: NSImage, next: NSImage) -> Int {
        guard let previousCG = previous.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let nextCG = next.cgImage(forProposedRect: nil, context: nil, hints: nil),
              previousCG.width == nextCG.width,
              previousCG.height == nextCG.height,
              let previousBuffer = rgbaBuffer(from: previousCG),
              let nextBuffer = rgbaBuffer(from: nextCG) else {
            return 0
        }

        let width = previousCG.width
        let height = previousCG.height
        let minOverlap = max(24, height / 20)
        let maxOverlap = max(minOverlap, height * 3 / 4)
        let step = max(4, height / 160)
        let sampleXStride = max(8, width / 96)
        let sampleYStride = max(4, height / 160)

        var bestOverlap = 0
        var bestScore = Double.greatestFiniteMagnitude

        for overlap in stride(from: minOverlap, through: maxOverlap, by: step) {
            var totalDifference = 0
            var samples = 0

            for y in stride(from: 0, to: overlap, by: sampleYStride) {
                let previousY = height - overlap + y
                let nextY = y

                for x in stride(from: 0, to: width, by: sampleXStride) {
                    let previousOffset = (previousY * width + x) * 4
                    let nextOffset = (nextY * width + x) * 4

                    totalDifference += abs(Int(previousBuffer[previousOffset]) - Int(nextBuffer[nextOffset]))
                    totalDifference += abs(Int(previousBuffer[previousOffset + 1]) - Int(nextBuffer[nextOffset + 1]))
                    totalDifference += abs(Int(previousBuffer[previousOffset + 2]) - Int(nextBuffer[nextOffset + 2]))
                    samples += 3
                }
            }

            guard samples > 0 else { continue }
            let score = Double(totalDifference) / Double(samples)

            if score < bestScore {
                bestScore = score
                bestOverlap = overlap
            }
        }

        return bestScore < 16 ? bestOverlap : 0
    }

    static func cropTopPixels(_ pixels: Int, from image: NSImage) -> NSImage {
        guard pixels > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              pixels < cgImage.height - 1 else {
            return image
        }

        let cropRect = CGRect(
            x: 0,
            y: pixels,
            width: cgImage.width,
            height: cgImage.height - pixels
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return image
        }

        let scale = HighResolutionImageRenderer.pixelScale(of: image)
        return NSImage(
            cgImage: croppedCGImage,
            size: NSSize(
                width: CGFloat(croppedCGImage.width) / scale,
                height: CGFloat(croppedCGImage.height) / scale
            )
        )
    }

    private static func removeOverlappingScrollRegions(from images: [NSImage]) -> [NSImage] {
        guard images.count > 1 else { return images }

        var result: [NSImage] = []
        var previous = images[0]
        result.append(previous)

        for image in images.dropFirst() {
            let overlap = detectedVerticalOverlap(previous: previous, next: image)
            let cropped = cropTopPixels(overlap, from: image)
            result.append(cropped)
            previous = image
        }

        return result
    }

    private static func outputGeometry(for images: [NSImage]) -> (size: CGSize, pixelScale: CGFloat)? {
        guard let first = images.first else { return nil }
        let width = images.map { $0.size.width }.min() ?? first.size.width
        guard width.isFinite, width > 0 else { return nil }

        let height = images.reduce(CGFloat(0)) {
            $0 + ($1.size.height * width / max($1.size.width, 1))
        }
        guard height.isFinite, height > 0 else { return nil }

        let pixelScale = images
            .map { HighResolutionImageRenderer.pixelScale(of: $0) }
            .max() ?? 1
        return (CGSize(width: width, height: height), pixelScale)
    }

    private static func rgbaBuffer(from image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
