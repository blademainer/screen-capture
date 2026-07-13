# iShot-Style Inline Capture Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the automatic union-of-displays gray screenshot editor with an in-place, iShot-style region editor that preserves the selected screen position.

**Architecture:** Region capture returns a `CapturedRegionContext` containing the image, Quartz selection, and display mappings. An `InlineCaptureEditorController` owns one transparent dimming window per display, one clipped image/annotation segment per intersected display, and one compact borderless toolbar; automatic region capture never enters `EditingWindowController`.

**Tech Stack:** Swift 5.9, AppKit, SwiftUI, ScreenCaptureKit, Combine, XCTest, Swift Package Manager.

## Global Constraints

- Minimum deployment target remains macOS 15.0.
- Do not add third-party dependencies.
- Keep `ImageEditingSession`, `EditingOperation`, and `FloatingEditingCanvasView` as annotation sources of truth.
- Never create an automatic screenshot editor window from the union of all `NSScreen.frame` values.
- Preserve primary, vertical-secondary, mixed-DPI, and cross-display capture mappings.
- `Escape` must cancel from selection and editing states.

---

### Task 1: Capture Geometry And Context

**Files:**
- Create: `MacScreenCapture/Core/CaptureGeometry.swift`
- Modify: `MacScreenCapture/Core/CaptureManager.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: `DisplayCoordinateSpace`, `CapturedRegionContext`, `CaptureCoordinateMapper.screenSegments(for:)`.
- Consumes: `CGDisplayBounds`, `NSScreen.frame`, and the existing fixed-region image capture.

- [ ] **Step 1: Write failing round-trip and context tests**

```swift
func testCaptureCoordinateMapperMapsVerticalDisplaySegmentToAppKitScreen() throws {
    let mapper = CaptureCoordinateMapper(spaces: [
        DisplayCoordinateSpace(
            displayID: 3,
            captureFrame: CGRect(x: 2560, y: -458, width: 1440, height: 2560),
            screenFrame: CGRect(x: 2560, y: -662, width: 1440, height: 2560)
        )
    ])
    let segment = try XCTUnwrap(mapper.screenSegments(for: CGRect(x: 2600, y: -400, width: 300, height: 500)).first)
    XCTAssertEqual(segment.screenRect, CGRect(x: 2600, y: 840, width: 300, height: 500))
    XCTAssertEqual(segment.imageRect, CGRect(x: 0, y: 0, width: 300, height: 500))
}
```

- [ ] **Step 2: Run the test and confirm missing-type failure**

Run: `swift test --filter MacScreenCaptureTests.testCaptureCoordinateMapperMapsVerticalDisplaySegmentToAppKitScreen`

- [ ] **Step 3: Implement typed geometry**

```swift
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
```

`CaptureCoordinateMapper.screenSegments(for:)` intersects each display, converts Quartz top-left Y to AppKit bottom-left Y, and derives `imageRect.y` as `selection.height - (intersection.maxY - selection.minY)`.

- [ ] **Step 4: Make region capture return `CapturedRegionContext` and rerun the test**

Run: `swift test --filter MacScreenCaptureTests.testCaptureCoordinateMapperMapsVerticalDisplaySegmentToAppKitScreen`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Core/CaptureGeometry.swift MacScreenCapture/Core/CaptureManager.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Preserve region capture geometry"
```

### Task 2: Pure Toolbar Placement

**Files:**
- Create: `MacScreenCapture/Utils/CaptureOverlayLayout.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: `CaptureOverlayLayout.toolbarFrame(selection:toolbarSize:visibleFrame:)`.
- Consumes: AppKit screen-space rectangles.

- [ ] **Step 1: Write failing below/above/clamped tests**

```swift
func testCaptureOverlayToolbarMovesAboveSelectionWhenBelowDoesNotFit() {
    let frame = CaptureOverlayLayout.toolbarFrame(
        selection: CGRect(x: 100, y: 10, width: 500, height: 300),
        toolbarSize: CGSize(width: 420, height: 52),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
    )
    XCTAssertEqual(frame.origin, CGPoint(x: 140, y: 318))
}
```

- [ ] **Step 2: Run the test and confirm missing-type failure**

Run: `swift test --filter MacScreenCaptureTests.testCaptureOverlayToolbarMovesAboveSelectionWhenBelowDoesNotFit`

- [ ] **Step 3: Write placement with an 8-point gap**

The algorithm centers horizontally, clamps to `visibleFrame.insetBy(dx: 8, dy: 8)`, uses below when `selection.minY - 8 - toolbarHeight` fits, otherwise above, and finally places the toolbar inside the selection bottom edge.

```swift
static func toolbarFrame(selection: CGRect, toolbarSize: CGSize, visibleFrame: CGRect) -> CGRect {
    let safe = visibleFrame.insetBy(dx: 8, dy: 8)
    let x = min(max(selection.midX - toolbarSize.width / 2, safe.minX), safe.maxX - toolbarSize.width)
    if selection.minY - 8 - toolbarSize.height >= safe.minY {
        return CGRect(origin: CGPoint(x: x, y: selection.minY - 8 - toolbarSize.height), size: toolbarSize)
    }
    if selection.maxY + 8 + toolbarSize.height <= safe.maxY {
        return CGRect(origin: CGPoint(x: x, y: selection.maxY + 8), size: toolbarSize)
    }
    return CGRect(origin: CGPoint(x: x, y: max(safe.minY, selection.minY + 8)), size: toolbarSize)
}
```

- [ ] **Step 4: Run the focused test**

Run: `swift test --filter MacScreenCaptureTests.testCaptureOverlayToolbarMovesAboveSelectionWhenBelowDoesNotFit`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Utils/CaptureOverlayLayout.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Add inline capture toolbar layout"
```

### Task 3: Inline Editor Window Topology

**Files:**
- Create: `MacScreenCapture/Core/InlineCaptureEditorController.swift`
- Create: `MacScreenCapture/Views/InlineCaptureSegmentView.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: `InlineCaptureEditorController(context:completion:)`, `show()`, and `cancel()`.
- Consumes: `CapturedRegionContext`, `CaptureCoordinateMapper`, `ImageEditingSession`, `FloatingEditingCanvasView`.

- [ ] **Step 1: Write a failing source contract test**

```swift
func testInlineEditorUsesPerDisplayTransparentWindows() throws {
    let source = try repositoryFileContents("MacScreenCapture/Core/InlineCaptureEditorController.swift")
    XCTAssertTrue(source.contains("mapper.screenSegments(for: context.captureRect)"))
    XCTAssertTrue(source.contains("window.backgroundColor = .clear"))
    XCTAssertTrue(source.contains("window.isOpaque = false"))
    XCTAssertFalse(source.contains("reduce(CGRect.null)"))
}
```

- [ ] **Step 2: Run the test and confirm the new file is missing**

Run: `swift test --filter MacScreenCaptureTests.testInlineEditorUsesPerDisplayTransparentWindows`

- [ ] **Step 3: Write the controller and clipped segment view**

For each active display create a mouse-ignoring dim window at exactly `screenFrame`; for each intersecting `CaptureScreenSegment` create an editor window at exactly `segment.screenRect`. The segment view installs an `NSImageView` and `FloatingEditingCanvasView` at the full selection size, offset by `-segment.imageRect.minX/-segment.imageRect.minY`, and clips to its own bounds.

```swift
for segment in mapper.screenSegments(for: context.captureRect) {
    let window = InlineCaptureWindow(contentRect: segment.screenRect, styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = InlineCaptureSegmentView(model: model, segment: segment, selectionSize: context.captureRect.size)
    segmentWindows.append(window)
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter MacScreenCaptureTests.testInlineEditorUsesPerDisplayTransparentWindows`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Core/InlineCaptureEditorController.swift MacScreenCapture/Views/InlineCaptureSegmentView.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Add in-place screenshot editor windows"
```

### Task 4: Compact Annotation And Action Toolbar

**Files:**
- Create: `MacScreenCapture/Views/InlineCaptureToolbarView.swift`
- Modify: `MacScreenCapture/Core/InlineCaptureEditorController.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: tool bindings plus finish, cancel, copy, save, share, pin, OCR, and scrolling callbacks.
- Consumes: existing `EditingTool.icon`, `ImageEditingSession.undo/redo`, and `CaptureOverlayLayout`.

- [ ] **Step 1: Write a failing toolbar capability test**

```swift
func testInlineToolbarExposesIShotEditingAndOutputActions() throws {
    let source = try repositoryFileContents("MacScreenCapture/Views/InlineCaptureToolbarView.swift")
    for token in ["EditingTool.allCases", "onUndo", "onRedo", "onCopy", "onSave", "onShare", "onPin", "onOCR", "onScrolling", "onFinish", "onCancel"] {
        XCTAssertTrue(source.contains(token), "Missing \(token)")
    }
}
```

- [ ] **Step 2: Run the test and confirm the toolbar file is missing**

Run: `swift test --filter MacScreenCaptureTests.testInlineToolbarExposesIShotEditingAndOutputActions`

- [ ] **Step 3: Write a borderless two-row icon toolbar**

Use SF Symbols with `.help(...)`; use a color swatch for color, sliders for width/font size, icon buttons for commands, and no title or close-button chrome. The toolbar panel uses `.borderless`, clear background, and a rounded `NSVisualEffectView` hosting surface.

```swift
HStack(spacing: 6) {
    ForEach(EditingTool.allCases, id: \.self) { tool in
        Button { model.selectedTool = tool } label: {
            Image(systemName: tool.icon).frame(width: 28, height: 28)
        }.buttonStyle(.plain).help(tool.name)
    }
    Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }.help("撤销")
    Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }.help("重做")
    Button(action: onFinish) { Image(systemName: "checkmark") }.help("完成")
    Button(action: onCancel) { Image(systemName: "xmark") }.help("取消")
}
```

- [ ] **Step 4: Run focused test**

Run: `swift test --filter MacScreenCaptureTests.testInlineToolbarExposesIShotEditingAndOutputActions`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Views/InlineCaptureToolbarView.swift MacScreenCapture/Core/InlineCaptureEditorController.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Add inline screenshot editing toolbar"
```

### Task 5: Route Automatic Region Capture Inline

**Files:**
- Modify: `MacScreenCapture/Core/CaptureManager.swift`
- Modify: `MacScreenCapture/Core/WindowManager.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: automatic region flow `select -> capture context -> inline edit -> finalize(showEditor: false)`.
- Consumes: `InlineCaptureEditorController` completion outcomes.

- [ ] **Step 1: Write a failing integration source test**

```swift
func testAutomaticRegionCaptureNeverOpensStandaloneEditingWindow() throws {
    let source = try repositoryFileContents("MacScreenCapture/Core/CaptureManager.swift")
    let start = try XCTUnwrap(source.range(of: "private func captureRegionScreenshot("))
    let end = try XCTUnwrap(source.range(of: "/// 捕获指定区域", range: start.lowerBound..<source.endIndex))
    let function = String(source[start.lowerBound..<end.lowerBound])
    XCTAssertTrue(function.contains("presentInlineEditor"))
    XCTAssertTrue(function.contains("showEditor: false"))
    XCTAssertFalse(function.contains("showEditor: true"))
}
```

- [ ] **Step 2: Run the test and confirm current `showEditor: true` failure**

Run: `swift test --filter MacScreenCaptureTests.testAutomaticRegionCaptureNeverOpensStandaloneEditingWindow`

- [ ] **Step 3: Write the new flow and result routing**

`finish` applies configured save/copy once; `copy` forces clipboard output; `save` forces local save; `pin` opens `FloatingWindowManager`; `ocr` recognizes the edited image; `scrolling` closes overlays before starting scrolling capture; `cancel` throws `regionSelectionCancelled`.

```swift
let context = try await captureSelectedRegionContext(preferWindowUnderMouse: true)
let outcome = try await presentInlineEditor(context)
switch outcome {
case .finish(let image): return try await finalizeCapturedImage(image, showEditor: false)
case .copy(let image):
    await MainActor.run { copyImageToPasteboard(image) }
    return try await finalizeCapturedImage(image, showEditor: false)
case .save(let image): return try await finalizeCapturedImage(image, showEditor: false, forceSave: true)
case .cancel: throw CaptureError.regionSelectionCancelled
}
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Core/CaptureManager.swift MacScreenCapture/Core/WindowManager.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Use inline editor for region screenshots"
```

### Task 6: Selection Handles, Movement, And Escape

**Files:**
- Create: `MacScreenCapture/Utils/CaptureSelectionGeometry.swift`
- Modify: `MacScreenCapture/Core/InlineCaptureEditorController.swift`
- Modify: `MacScreenCapture/Views/InlineCaptureSegmentView.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: eight resize handles, clamped move/resize, idempotent escape cancellation.
- Consumes: capture bounds and existing editor windows.

- [ ] **Step 1: Write failing resize and clamping tests**

```swift
func testCaptureSelectionGeometryResizesFromTopLeftHandle() {
    let result = CaptureSelectionGeometry.resize(
        CGRect(x: 100, y: 100, width: 400, height: 300),
        handle: .topLeft,
        to: CGPoint(x: 80, y: 70),
        bounds: CGRect(x: 0, y: 0, width: 1000, height: 800),
        minimumSize: CGSize(width: 16, height: 16)
    )
    XCTAssertEqual(result, CGRect(x: 80, y: 70, width: 420, height: 330))
}
```

- [ ] **Step 2: Run the test and confirm missing-type failure**

Run: `swift test --filter MacScreenCaptureTests.testCaptureSelectionGeometryResizesFromTopLeftHandle`

- [ ] **Step 3: Write pure move/resize geometry and wire editor drag events**

When the selection changes, recapture the new region, rebuild segment frames, and reposition the toolbar. All windows share one local event monitor; key code 53 calls `cancel()` once and removes the monitor before closing windows.

```swift
case .topLeft:
    let minX = min(point.x, rect.maxX - minimumSize.width)
    let minY = min(point.y, rect.maxY - minimumSize.height)
    return CGRect(x: minX, y: minY, width: rect.maxX - minX, height: rect.maxY - minY).intersection(bounds)
```

- [ ] **Step 4: Run focused and full tests**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Utils/CaptureSelectionGeometry.swift MacScreenCapture/Core/InlineCaptureEditorController.swift MacScreenCapture/Views/InlineCaptureSegmentView.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Add inline selection adjustment"
```

### Task 7: Compact Explicit Editor

**Files:**
- Modify: `MacScreenCapture/Core/EditingWindowController.swift`
- Modify: `MacScreenCapture/Views/EditingWindowContentView.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: image-sized standalone editor for explicit Edit only.

- [ ] **Step 1: Replace existing source expectations with a failing compact-window test**

```swift
func testExplicitEditingWindowNeverUsesAllScreenUnion() throws {
    let source = try repositoryFileContents("MacScreenCapture/Core/EditingWindowController.swift")
    XCTAssertFalse(source.contains("fullScreenEditingFrame"))
    XCTAssertFalse(source.contains("reduce(CGRect.null)"))
    XCTAssertTrue(source.contains("visibleFrame"))
}
```

- [ ] **Step 2: Run and confirm failure on `fullScreenEditingFrame`**

Run: `swift test --filter MacScreenCaptureTests.testExplicitEditingWindowNeverUsesAllScreenUnion`

- [ ] **Step 3: Size the standalone editor to the image within the current screen visible frame**

The content size is the aspect-fit image plus compact toolbar/action heights, clamped to 960 by 760 and the current `visibleFrame`; background is `windowBackgroundColor`, not a full-screen opaque gray mask.

```swift
let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
let width = min(960, visibleFrame.width - 80)
let imageHeight = width * screenshot.size.height / max(1, screenshot.size.width)
let contentRect = NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.midY - min(760, imageHeight + 120) / 2, width: width, height: min(760, imageHeight + 120))
```

- [ ] **Step 4: Run full tests**

Run: `swift test`

- [ ] **Step 5: Commit**

```bash
git add MacScreenCapture/Core/EditingWindowController.swift MacScreenCapture/Views/EditingWindowContentView.swift MacScreenCaptureTests/MacScreenCaptureTests.swift
git commit -m "Constrain explicit screenshot editor"
```

### Task 8: Release And Visual Acceptance

**Files:**
- Modify: `MacScreenCapture/Utils/ScreenshotGeometryDiagnostics.swift`
- Test: `MacScreenCaptureTests/MacScreenCaptureTests.swift`

**Interfaces:**
- Produces: installed, signed app plus geometry evidence for selection, image segment, and toolbar frames.

- [ ] **Step 1: Add log assertions for `inline_segment_layout` and `inline_toolbar_layout`**

```swift
XCTAssertTrue(diagnosticsSource.contains("inline_segment_layout"))
XCTAssertTrue(diagnosticsSource.contains("inline_toolbar_layout"))
```

- [ ] **Step 2: Run all tests and production build**

Run: `swift test && swift build -c release`

- [ ] **Step 3: Install, ad-hoc sign, and restart**

```bash
/usr/bin/install -m 755 .build/release/MacScreenCapture /Applications/MacScreenCapture.app/Contents/MacOS/MacScreenCapture
codesign --force --deep --sign - /Applications/MacScreenCapture.app
open /Applications/MacScreenCapture.app
```

- [ ] **Step 4: Use Computer Use on primary, vertical secondary, and cross-display selections**

Verify the selected image stays within one point of the logged original screen rect, only outside areas are dim, toolbar is adjacent and visible, annotations align, and Escape leaves no overlay.

- [ ] **Step 5: Push verified commits to `main`**

```bash
git push origin main
```
