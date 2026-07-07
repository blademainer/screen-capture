# Screen Capture

A native macOS menu bar app for screenshots and screen recording.

## Features

- Full screen, area, window, and clipboard screenshots.
- Full screen recording and selected-area video recording saved as `.mov`.
- Menu bar controls with live recording state, stop action, output folder picker, and permission shortcut.
- Options for cursor visibility, reveal-after-capture, and recording click highlights.
- macOS Screen Recording permission checks and clear user feedback.
- Automatic file naming and Finder reveal after capture.

## Menu

- `Full Screenshot`: saves the whole screen.
- `Select Area Screenshot`: uses the native macOS selection cursor.
- `Window Screenshot`: starts in native window-pick mode.
- `Copy ... to Clipboard`: captures without writing a file.
- `Start Full Screen Recording`: records immediately until `Stop Recording`.
- `Start Area Recording`: opens an overlay; drag an area, then stop from the menu.
- `Save To`: changes the output folder.
- `Request Screen Permission`: triggers the Screen Recording permission flow.

## Build

```bash
swift build
```

Build an app bundle:

```bash
./Scripts/build-app.sh
open .build/app/ScreenCapture.app
```

Run repeatable engineering checks:

```bash
./Scripts/smoke-test.sh
```

To exercise the real screenshot and recording writers:

```bash
.build/app/ScreenCapture.app/Contents/MacOS/ScreenCapture --diagnose --recording --menu
```

## CI Packaging

The project includes a GitHub Actions workflow at `.github/workflows/build.yml`.
It runs on macOS, builds the Swift package, creates the `.app` bundle, verifies
`Info.plist` and ad-hoc codesign, zips `ScreenCapture.app`, and uploads it as a
workflow artifact named `ScreenCapture-macOS`.

The CI workflow intentionally does not run real screenshot or recording capture,
because GitHub-hosted runners do not provide the same Screen Recording permission
flow as a user desktop session. Use `./Scripts/smoke-test.sh` and `--diagnose
--recording --menu` locally for runtime capture validation.

The first capture or recording may require granting Screen Recording permission in System Settings.

## Manual QA

After granting Screen Recording permission:

- Take a full screenshot and confirm the file appears in the selected save folder.
- Take an area screenshot and cancel once with Esc to confirm the cancel notification.
- Start a full screen recording, wait a few seconds, stop from the menu, and open the generated `.mov`.
- Start an area recording, drag a region, stop from the menu, and confirm the video dimensions match the selected area.
- Toggle reveal-after-capture, cursor visibility, and click highlights.
