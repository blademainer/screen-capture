# Native-Resolution Screenshot Design

## Goal

Make screenshots preserve the source display's native pixel detail. A Retina region that is 800 x 600 screen points on a 2x display must produce a 1600 x 1200 pixel image, including after annotation, cropping, styling, saving, or copying to the clipboard.

The implementation must not synthesize detail with arbitrary 2x or 3x interpolation. A 1x display remains 1x unless a selection spans displays with different scales and needs one common output pixel grid.

## Root Cause

The current ScreenCaptureKit configuration uses display and window dimensions measured in screen points as output pixel dimensions. Region composition and image editing also create `NSImage` buffers from logical sizes with `lockFocus()`. Both paths collapse Retina content to a 1x bitmap.

## Pixel Model

Every image has two related dimensions:

- Logical size in screen points, used by selection geometry, annotation coordinates, window placement, and crop operations.
- Pixel size in the backing `CGImage` or `NSBitmapImageRep`, used by capture, rendering, export, and clipboard data.

The pixel scale is `pixel width / logical width`. ScreenCaptureKit's `SCContentFilter.pointPixelScale` is the authoritative source scale for display and window filters. Invalid or unavailable scale values fall back to `CGDisplayPixelsWide / CGDisplayBounds.width`, then to 1x.

## Capture Flow

Full-display and window captures configure `SCStreamConfiguration.width` and `height` in native pixels using the content filter's point-to-pixel scale. The resulting `NSImage` keeps the content's logical point size while retaining the native-size backing representation.

Region capture continues selecting and mapping rectangles in global screen points. Each display segment is captured at that display's native scale, then cropped in pixel coordinates. A single-display region returns its native backing pixels and logical selection size directly.

For a region spanning displays with different scales, the composite uses the highest participating native scale as one consistent pixel grid. Native high-scale segments remain lossless. Lower-scale segments are resampled only where a single raster requires it; they cannot gain detail beyond their source display.

## Editing And Styling

A shared high-resolution bitmap renderer creates output representations with an explicit logical size and pixel scale. Annotation rendering, image cropping, rounded corners, shadows, device frames, and multi-segment composition use this renderer instead of implicit 1x `NSImage.lockFocus()` buffers.

Annotation coordinates and line widths remain expressed in logical points. The graphics context maps those points into the high-resolution backing bitmap, so visual sizing remains unchanged while edges and text stay sharp.

## Export And Clipboard

PNG and TIFF export use the highest-resolution bitmap representation without resizing. JPEG keeps the existing quality setting but encodes the native pixel dimensions. Clipboard TIFF data also retains those dimensions.

Geometry diagnostics record logical size, pixel size, and pixel scale at display capture, region crop, composite output, and final output boundaries.

## Failure Handling

Capture dimensions are clamped to at least one pixel. Non-finite, zero, or negative scale values fall back safely to 1x. If a native-resolution bitmap allocation fails, the operation reports the existing capture or save error instead of silently returning a lower-resolution image.

## Verification

Automated tests must prove:

- A 2x source with an 800 x 600 logical region has a 1600 x 1200 backing bitmap.
- A mixed 1x/2x multi-display selection uses a 2x output grid without changing logical geometry.
- Pen annotation and crop operations preserve the source pixel scale.
- Rounded corners, shadows, and device frames preserve the pixel scale.
- PNG, TIFF, JPEG, and clipboard TIFF preserve expected pixel dimensions.
- Existing selection coordinates and editor layout tests remain unchanged.

Runtime verification on the installed app must capture a known Retina region, save it, and inspect the resulting file's pixel dimensions. The captured file must be 2x its logical selection dimensions on the current Retina display and remain 2x after adding an annotation.
