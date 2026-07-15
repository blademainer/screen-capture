# Native-Resolution Screenshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve native Retina pixels from ScreenCaptureKit through region composition, editing, styling, export, and clipboard output.

**Architecture:** Add one focused AppKit bitmap utility that separates logical point size from backing pixel size. Capture paths request native pixels from `SCContentFilter.pointPixelScale`; all later raster operations render into explicit high-resolution bitmap representations using the source scale.

**Tech Stack:** Swift 5.9, AppKit, CoreGraphics, ScreenCaptureKit, XCTest, Swift Package Manager.

## Global Constraints

- Keep selection, annotation, crop, and window geometry in screen points.
- Use native source pixels; do not invent a fixed 2x or 3x upscale.
- Mixed-scale composites use the highest participating native scale.
- A 1x source remains 1x unless it participates in a mixed-scale composite.
- Preserve existing PNG/JPEG/TIFF settings and JPEG compression factor `0.9`.
- Do not add third-party dependencies.

---

### Task 1: Explicit Logical And Pixel Geometry

**Files:**
- Create: `MacScreenCapture/Utils/HighResolutionImageRenderer.swift`
- Modify: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: `HighResolutionImageRenderer.pixelSize(of:) -> CGSize`
- Produces: `HighResolutionImageRenderer.pixelScale(of:) -> CGFloat`
- Produces: `HighResolutionImageRenderer.render(logicalSize:pixelScale:drawing:) -> NSImage?`
- Produces: `HighResolutionImageRenderer.bitmapRepresentation(of:) -> NSBitmapImageRep?`

- [ ] **Step 1: Write failing utility tests**

Add tests that create a 2x image with logical size `100 x 50`, assert a `200 x 100` backing bitmap, render another image at the inferred scale, and verify the result remains `200 x 100`.

```swift
func testHighResolutionRendererSeparatesLogicalAndPixelSizes() throws {
    let image = try XCTUnwrap(HighResolutionImageRenderer.render(
        logicalSize: CGSize(width: 100, height: 50),
        pixelScale: 2
    ) { rect in
        NSColor.red.setFill()
        rect.fill()
    })

    XCTAssertEqual(image.size, CGSize(width: 100, height: 50))
    XCTAssertEqual(HighResolutionImageRenderer.pixelSize(of: image), CGSize(width: 200, height: 100))
    XCTAssertEqual(HighResolutionImageRenderer.pixelScale(of: image), 2)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `swift test --filter MacScreenCaptureTests.testHighResolutionRendererSeparatesLogicalAndPixelSizes`

Expected: compile failure because `HighResolutionImageRenderer` does not exist.

- [ ] **Step 3: Implement the bitmap renderer**

Create a renderer that validates finite positive sizes/scales, allocates `NSBitmapImageRep` at `ceil(logicalSize * scale)`, assigns `representation.size = logicalSize`, creates `NSGraphicsContext(bitmapImageRep:)`, and invokes the drawing closure in logical coordinates. Build the returned `NSImage(size: logicalSize)` by adding that representation.

```swift
enum HighResolutionImageRenderer {
    static func render(
        logicalSize: CGSize,
        pixelScale: CGFloat,
        drawing: (CGRect) -> Void
    ) -> NSImage? {
        guard logicalSize.width.isFinite, logicalSize.height.isFinite,
              logicalSize.width > 0, logicalSize.height > 0 else { return nil }
        let scale = pixelScale.isFinite && pixelScale > 0 ? pixelScale : 1
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
        ) else { return nil }
        representation.size = logicalSize
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawing(CGRect(origin: .zero, size: logicalSize))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: logicalSize)
        image.addRepresentation(representation)
        return image
    }

    static func pixelSize(of image: NSImage) -> CGSize {
        let bitmap = image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
        if let bitmap {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    static func pixelScale(of image: NSImage) -> CGFloat {
        let pixels = pixelSize(of: image)
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        let scale = max(pixels.width / image.size.width, pixels.height / image.size.height)
        return scale.isFinite && scale > 0 ? scale : 1
    }

    static func bitmapRepresentation(of image: NSImage) -> NSBitmapImageRep? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = image.size
        return representation
    }
}
```

Add this shared test helper in `MacScreenCaptureTests`:

```swift
private func makeTestImage(logicalSize: CGSize, scale: CGFloat) -> NSImage? {
    HighResolutionImageRenderer.render(logicalSize: logicalSize, pixelScale: scale) { rect in
        NSColor.white.setFill()
        rect.fill()
    }
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter MacScreenCaptureTests.testHighResolutionRendererSeparatesLogicalAndPixelSizes && swift test`

Expected: focused test passes; existing 105 tests also pass.

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Utils/HighResolutionImageRenderer.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Add high-resolution image renderer"
```

### Task 2: Native-Pixel ScreenCaptureKit Capture And Region Composition

**Files:**
- Modify: `MacScreenCapture/Core/CaptureManager.swift`
- Modify: `MacScreenCapture/Utils/ScreenshotGeometryDiagnostics.swift`
- Modify: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Consumes: `HighResolutionImageRenderer.render`, `pixelScale`, and `pixelSize`
- Produces: `CapturePixelGeometry.normalizedScale(_:) -> CGFloat`
- Produces: `CapturePixelGeometry.outputPixelSize(logicalSize:scale:) -> CGSize`
- Produces: native-resolution `captureDisplayImageWithoutSaving`, `captureWindowImage`, `cropDisplayImage`, and `captureFixedRegionImage`

- [ ] **Step 1: Write failing capture geometry tests**

Add pure tests for scale normalization and mixed-scale output sizing, plus source checks that capture configuration uses `filter.pointPixelScale` and `.best` resolution.

```swift
func testCapturePixelGeometryUsesNativeAndMixedDisplayScales() {
    XCTAssertEqual(CapturePixelGeometry.normalizedScale(2), 2)
    XCTAssertEqual(CapturePixelGeometry.normalizedScale(.nan), 1)
    XCTAssertEqual(
        CapturePixelGeometry.outputPixelSize(
            logicalSize: CGSize(width: 800, height: 600),
            scale: 2
        ),
        CGSize(width: 1600, height: 1200)
    )
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run: `swift test --filter MacScreenCaptureTests.testCapturePixelGeometryUsesNativeAndMixedDisplayScales`

Expected: compile failure because `CapturePixelGeometry` does not exist.

- [ ] **Step 3: Implement native capture dimensions**

Add `CapturePixelGeometry` near the existing coordinate geometry types. For display and window filters, calculate scale from `CGFloat(filter.pointPixelScale)`, fall back to `CGDisplayPixelsWide / CGDisplayBounds.width` for displays, set `configuration.width/height` to logical dimensions times scale, and set `configuration.captureResolution = .best`.

```swift
enum CapturePixelGeometry {
    static func normalizedScale(_ scale: CGFloat, fallback: CGFloat = 1) -> CGFloat {
        if scale.isFinite, scale > 0 { return scale }
        if fallback.isFinite, fallback > 0 { return fallback }
        return 1
    }

    static func outputPixelSize(logicalSize: CGSize, scale: CGFloat) -> CGSize {
        let normalized = normalizedScale(scale)
        return CGSize(
            width: max(1, ceil(logicalSize.width * normalized)),
            height: max(1, ceil(logicalSize.height * normalized))
        )
    }
}
```

Wrap each returned `CGImage` in an `NSImage` whose `size` remains the logical content size:

```swift
let nativeScale = CapturePixelGeometry.normalizedScale(CGFloat(filter.pointPixelScale))
configuration.width = max(1, Int(ceil(logicalSize.width * nativeScale)))
configuration.height = max(1, Int(ceil(logicalSize.height * nativeScale)))
configuration.captureResolution = .best
return NSImage(cgImage: cgImage, size: logicalSize)
```

- [ ] **Step 4: Preserve scale through crop and multi-display composition**

Set cropped images' logical size to the selected Quartz segment size. For multi-segment regions, choose `segments.map { pixelScale(of: $0.image) }.max() ?? 1` and render the logical `captureRect.size` through `HighResolutionImageRenderer.render`. Draw each segment into its existing logical `drawRect`.

Extend geometry diagnostics with logical size, backing pixel size, and scale fields at capture, crop, and composite boundaries.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter MacScreenCaptureTests.testCapturePixelGeometryUsesNativeAndMixedDisplayScales && swift test`

Expected: all tests pass with no resolution regressions.

- [ ] **Step 6: Commit**

```bash
git add MacScreenCapture/Core/CaptureManager.swift MacScreenCapture/Utils/ScreenshotGeometryDiagnostics.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Capture screenshots at native display resolution"
```

### Task 3: Preserve Pixel Scale During Editing And Cropping

**Files:**
- Modify: `MacScreenCapture/Core/FloatingWindowController.swift`
- Modify: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Consumes: `HighResolutionImageRenderer.render` and `pixelScale`
- Produces: `ImageEditingSession.currentImage` with unchanged backing scale after annotations and logical crops

- [ ] **Step 1: Write failing annotation and crop tests**

Create a 2x base image, add a pen operation, and assert logical size stays `100 x 50` while pixel size stays `200 x 100`. Add a crop operation from `100 x 50` to `40 x 20` points and assert backing pixels become `80 x 40`.

```swift
@MainActor
func testImageEditingSessionPreservesRetinaScaleAfterAnnotationAndCrop() throws {
    let source = try XCTUnwrap(makeTestImage(logicalSize: CGSize(width: 100, height: 50), scale: 2))
    let session = ImageEditingSession(originalImage: source)
    session.addOperation(EditingOperation(type: .pen, points: [.zero, CGPoint(x: 20, y: 20)]))
    XCTAssertEqual(HighResolutionImageRenderer.pixelSize(of: session.currentImage), CGSize(width: 200, height: 100))
    session.addOperation(EditingOperation(type: .crop, rect: CGRect(x: 0, y: 0, width: 40, height: 20)))
    XCTAssertEqual(session.currentImage.size, CGSize(width: 40, height: 20))
    XCTAssertEqual(HighResolutionImageRenderer.pixelSize(of: session.currentImage), CGSize(width: 80, height: 40))
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `swift test --filter MacScreenCaptureTests.testImageEditingSessionPreservesRetinaScaleAfterAnnotationAndCrop`

Expected: assertion failure showing a 1x backing bitmap after editing.

- [ ] **Step 3: Replace implicit 1x editing buffers**

In `renderImage(_:applying:)` and `cropImage(_:to:)`, render with the source image's `pixelScale` through `HighResolutionImageRenderer`. Keep all operation coordinates and line widths in logical points.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter MacScreenCaptureTests.testImageEditingSessionPreservesRetinaScaleAfterAnnotationAndCrop && swift test`

Expected: Retina scale test and all existing editing tests pass.

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Core/FloatingWindowController.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Preserve Retina pixels while editing screenshots"
```

### Task 4: Preserve Pixel Scale Through Styling, Composites, And Exports

**Files:**
- Modify: `MacScreenCapture/Utils/ScreenshotStyleRenderer.swift`
- Modify: `MacScreenCapture/Utils/ScrollingImageStitcher.swift`
- Modify: `MacScreenCapture/Core/CaptureManager.swift`
- Modify: `MacScreenCapture/Core/FloatingWindowController.swift`
- Modify: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Consumes: all `HighResolutionImageRenderer` APIs
- Produces: native-pixel rounded, shadowed, framed, scrolling, multi-window, saved, and clipboard images

- [ ] **Step 1: Write failing style and encoding tests**

Verify rounded output remains 2x, shadow/device-frame output pixel dimensions equal their logical dimensions times 2, vertical stitching preserves the maximum source scale, and PNG/JPEG/TIFF bitmap representations retain native pixels.

```swift
func testScreenshotStyleRendererPreservesRetinaScale() throws {
    let source = try XCTUnwrap(makeTestImage(logicalSize: CGSize(width: 100, height: 50), scale: 2))
    let rounded = ScreenshotStyleRenderer.renderRoundedImage(source, radius: 8)
    XCTAssertEqual(HighResolutionImageRenderer.pixelSize(of: rounded), CGSize(width: 200, height: 100))
}
```

- [ ] **Step 2: Run focused tests and confirm RED**

Run: `swift test --filter MacScreenCaptureTests.testScreenshotStyleRendererPreservesRetinaScale`

Expected: assertion failure showing the styled image was rasterized at 1x.

- [ ] **Step 3: Replace remaining implicit 1x buffers**

Use the maximum participating source scale with `HighResolutionImageRenderer.render` in:

- `ScreenshotStyleRenderer.renderRoundedImage`
- `ScreenshotStyleRenderer.renderShadowedImage`
- `ScreenshotStyleRenderer.renderDeviceFrame`
- `ScrollingImageStitcher.stitchImagesVertically`
- `CaptureManager.renderMultiWindowComposite`

Keep each existing logical layout calculation unchanged.

- [ ] **Step 4: Encode the native bitmap directly**

Replace TIFF round-trips in `CaptureManager.saveScreenshot` and `FloatingWindowController.writeImage` with `HighResolutionImageRenderer.bitmapRepresentation(of:)`. Use that representation for PNG, JPEG, and TIFF. Update clipboard writing to use the native bitmap representation's TIFF data.

```swift
guard let bitmapRep = HighResolutionImageRenderer.bitmapRepresentation(of: image) else {
    throw CaptureError.failedToSaveImage
}
let imageData = bitmapRep.representation(using: fileType, properties: properties)
```

- [ ] **Step 5: Run full verification**

Run: `swift test`

Expected: all tests pass, including native pixel tests for capture geometry, editing, styling, stitching, and encoding.

- [ ] **Step 6: Commit**

```bash
git add MacScreenCapture/Utils/ScreenshotStyleRenderer.swift MacScreenCapture/Utils/ScrollingImageStitcher.swift MacScreenCapture/Core/CaptureManager.swift MacScreenCapture/Core/FloatingWindowController.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Keep native pixels through screenshot output"
```

### Task 5: Installed-App Runtime Verification

**Files:**
- Modify only if runtime evidence exposes a defect.

**Interfaces:**
- Verifies the installed `/Applications/MacScreenCapture.app` end to end.

- [ ] **Step 1: Build and install the signed release app**

Run: `./scripts/install-local.sh`

Expected: build succeeds, code signature verifies, and `/Applications/MacScreenCapture.app` opens without resetting screen-capture permission.

- [ ] **Step 2: Capture an unedited Retina region**

Capture a region with known logical dimensions, save as PNG, and inspect it with:

```bash
sips -g pixelWidth -g pixelHeight /path/to/screenshot.png
```

Expected: pixel width and height equal logical selection dimensions times the display's native scale.

- [ ] **Step 3: Capture and annotate the same Retina region**

Add one pen stroke, save as PNG, and inspect dimensions again.

Expected: annotation is visible and output remains at the same native pixel scale.

- [ ] **Step 4: Verify diagnostics and application behavior**

Inspect `~/Library/Application Support/MacScreenCapture/screenshot-geometry.log` for logical size, pixel size, and scale. Verify Esc exits, clipboard output is readable, and no crash or permission regression occurs.

- [ ] **Step 5: Final repository and remote verification**

Run:

```bash
swift test
git diff --check
git status --short
git push origin main
git rev-parse HEAD
git rev-parse origin/main
```

Expected: all tests pass, worktree is clean, push succeeds, and local/remote revisions match.
