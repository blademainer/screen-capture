# iShot-Style Inline Screenshot Editor Design

## Problem

The current post-capture editor creates one borderless window over the union of
all displays. On the current two-display setup that window is `4000 x 2560`,
while the screenshot is centered within that virtual desktop. The primary
display therefore shows a large opaque gray surface with the captured image near
its right edge.

Geometry diagnostics prove that region selection and pixel cropping are
correct. The failure begins after capture:

- `capture_rect` and `pixel_crop_rect` match.
- `capture_result` has the expected image size.
- `editor_window_opened` uses the union of every `NSScreen.frame`.
- `EditingWindowContentView` centers a bounded canvas inside that union frame.

This cannot be fixed reliably with padding or centering adjustments. The
post-capture interaction must preserve the selected region and its display
coordinate space.

## Scope

This design covers the iShot-style screenshot workflow:

- dynamic window magnetism before dragging;
- free region selection;
- moving and resizing the selected region;
- dimensions and selection handles;
- inline annotation at the original screen position;
- save, copy, share, pin, OCR, scrolling capture, and cancel actions;
- keyboard-driven tool selection, undo, redo, completion, and cancellation;
- correct behavior on horizontal, vertical, scaled, and mixed-DPI displays.

Recording, audio recording, translation-provider behavior, and the main app
settings layout are outside this change. Their existing entry points remain.

## User Experience

### Selection

Invoking the standard screenshot shortcut creates one transparent overlay
window per active display. Each window covers only its own display. The desktop
is dimmed, while the window under the pointer or the dragged region remains
undimmed.

Before dragging, moving the pointer updates the magnetized window continuously.
Dragging switches to a free selection. After mouse-up, the selection remains in
place and shows eight resize handles plus a dimensions label. Dragging inside
the selection moves it. Dragging a handle resizes it. The selection is clamped
to the combined active-display capture area but may cross display boundaries.

### Inline editing

After mouse-up, the selected pixels are captured and rendered exactly over the
selected desktop region. The image does not move, center, or scale merely
because editing begins. Areas outside the selection remain dimmed; there is no
opaque gray editor canvas and no window spanning the virtual desktop.

A compact toolbar appears eight points below the selection. If it does not fit,
it moves above the selection. Horizontal placement is clamped to the visible
frame of the display containing the selection's active corner. If neither side
has enough room, the toolbar is placed inside the selection along its bottom
edge.

The toolbar exposes the existing annotation suite: select, pen, highlighter,
rectangle, circle, arrow, text, numbered marker, mosaic, crop, color, stroke
width, font size, undo, and redo. The action group exposes save, copy, share,
pin, OCR, scrolling capture, clear, and finish. Familiar icons are used with
tooltips; the toolbar is compact and has no title bar or close button.

`Escape` cancels immediately from every state. `Return` finishes using the
configured save and clipboard behavior. `Command-S` opens Save As. Existing
single-key annotation shortcuts remain available while the overlay is active.

### Explicit preview editing

The main window's explicit `Edit` button may still open a standalone image
editor because there is no original screen selection to return to. That editor
is sized to the image and current display. It must not use the union of all
screens and must not add an opaque full-screen gray background.

## Architecture

### `CaptureInteractionSession`

`CaptureInteractionSession` is the single state owner for one screenshot
interaction. Its states are:

1. `hovering`
2. `selecting`
3. `selected`
4. `capturing`
5. `editing`
6. `finishing`
7. `cancelled`

The session owns the selected Quartz capture rectangle, display coordinate
spaces, captured image, editing session, active tool, and completion callback.
Only legal state transitions are accepted. Completion and cancellation are
idempotent so multiple overlay windows cannot resume a continuation twice.

### `InlineCaptureOverlayController`

The controller creates one `RegionSelectionWindow` for each active display and
keeps those windows for the entire interaction. It never creates a window from
the union of display frames. It routes pointer and keyboard events to the shared
session and closes every overlay window on finish, cancel, or error.

### `InlineCaptureOverlayView`

Each view renders only the intersection between its display and the logical
selection. It draws the outside dimming mask, selection border, resize handles,
dimensions label, frozen image segment, annotations, and pointer feedback.

All drawing operations are stored in screenshot-image coordinates. A view on a
particular display maps its local event point through the shared selection
rectangle into those image coordinates. This keeps annotations aligned when a
selection crosses displays.

### `CaptureCoordinateMapper`

Coordinate conversion is isolated in a pure value type. It converts between:

- Quartz capture coordinates, with the capture origin convention used by
  `CGDisplayBounds`;
- AppKit screen coordinates used by `NSScreen` and `NSWindow`;
- display-local overlay coordinates;
- screenshot-image coordinates.

No view performs ad hoc Y-axis flipping. The mapper is initialized from the
existing `DisplayCoordinateSpace` values and is covered by multi-display tests.

### `CaptureOverlayLayout`

This pure layout component calculates resize handles, dimensions-label
placement, toolbar placement, and per-display selection intersections. It has no
AppKit window ownership and can be tested with synthetic monitor arrangements.

### Existing editor reuse

`ImageEditingSession` and the annotation rendering operations remain the source
of truth for edits. The reusable AppKit canvas is extracted from
`FloatingWindowContentView.swift` so both inline overlays and explicit preview
editing use the same operation rendering and hit testing.

`EditingWindowController.fullScreenEditingFrame()` and the automatic
post-capture path through `EditingWindowContentView` are removed. The compact
standalone editor remains only for explicit editing of an already-created
image.

## Data Flow

1. The hotkey asks `CaptureManager` to begin a screenshot interaction.
2. `CaptureManager` builds display coordinate spaces and window candidates.
3. `InlineCaptureOverlayController` opens one transparent window per display.
4. Pointer movement updates the magnetized region in the shared session.
5. Dragging or clicking commits a selected capture rectangle.
6. `CaptureManager` captures that rectangle and returns both image and capture
   metadata as `CapturedRegionContext`.
7. The session enters `editing`; overlay views render the image at the exact
   selected rectangle and show the contextual toolbar.
8. Annotation operations update the shared `ImageEditingSession` and every
   intersecting overlay redraws its segment.
9. Finish generates the edited image once, applies configured styling, writes
   clipboard/local outputs, and closes all overlays.
10. Cancel closes all overlays without saving or showing another editor.

`CapturedRegionContext` contains at least the image, Quartz capture rectangle,
display coordinate spaces, and the display ID containing the active selection
corner. Passing this context prevents the location data from being discarded.

## Error Handling

- Capture failure keeps the selection visible and presents a nonblocking error
  near the toolbar. The user may retry or press `Escape`.
- A disconnected display causes the layout to be recomputed from the remaining
  screens. If the selection no longer intersects a screen, the interaction is
  cancelled cleanly.
- A failed save leaves the overlay open and preserves edits.
- Clipboard, OCR, pin, and scrolling actions report errors without creating a
  modal run loop.
- Every exit path removes event monitors, closes all overlay windows, restores
  the cursor, and resumes the capture continuation at most once.

## Testing

### Unit tests

- Quartz/AppKit/image coordinate round trips for the current horizontal plus
  vertical monitor arrangement.
- Selection movement and eight-handle resizing.
- Toolbar below, above, clamped, and inside placements.
- Per-display intersections for selections crossing two displays.
- Annotation point mapping at 1x and 2x image scale.
- Idempotent finish and cancel transitions.

### Integration tests

- Region capture retains `capture_rect` through `CapturedRegionContext`.
- Automatic screenshot completion does not call
  `WindowManager.showEditingWindow(for:)`.
- No capture overlay window frame equals the union of all display frames.
- `Escape` closes every overlay and leaves no active event monitor.
- Save and copy use the same edited image produced by the inline session.

### Visual acceptance

Computer Use screenshots are required on the primary landscape display and the
secondary vertical display. The checks are:

- captured content remains at the original selected screen rectangle within one
  point;
- only the area outside the selection is dimmed;
- no opaque full-screen gray canvas is visible;
- the toolbar is fully visible and adjacent to the selection;
- the image and annotation canvas have identical bounds;
- `Escape` exits and returns focus without leaving an overlay;
- the installed Release app reproduces the same layout as the test build.

Geometry diagnostics continue to record selection, image, per-display segment,
annotation viewport, and toolbar frames so future coordinate regressions are
observable.

## Acceptance Criteria

The change is complete only when all of the following are true:

1. A region selected on the left side of the primary display remains on the
   left side when editing starts.
2. Screenshot editing never opens the current `4000 x 2560` union-frame window.
3. No opaque gray editor background appears behind a centered or offset image.
4. Selection, magnetic window detection, resizing, movement, annotation,
   save/copy/share/pin/OCR/scroll actions, and cancellation work in one inline
   interaction.
5. Primary, vertical secondary, and cross-display selections preserve pixel and
   annotation coordinates.
6. `Escape` exits from every interaction state.
7. Full tests, Release build, code signing, installed-app visual checks, and
   geometry-log checks pass before the change is pushed to `main`.
