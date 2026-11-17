# Idle Energy Investigation (2026-11-17)

## Confirmed In Source

- Startup previously held a process activity for the entire application lifetime,
  including user-initiated and latency-critical options.
- The application plist disabled App Nap globally.
- A repeating five-second dispatch timer updated a diagnostic heartbeat even
  without capture work. This timer did not collect screen images.

These policies unnecessarily prevented normal idle behavior. They are a plausible
contributor to the reported macOS significant-energy indication, not a measurement
of its total cause on the user's MacBook Air.

## Changes

- Removed the startup/shutdown activity and global App Nap opt-out.
- Removed the idle timer. Hotkey diagnostics now report the interval since the
  previous actual hotkey event (`previous_hotkey_gap_ms`), not a heartbeat gap.
- Kept a scoped user-initiated activity during hotkey actions, without the
  latency-critical flag. A defer releases it after success or failure.
- Left capture geometry, recording frame rate, image quality, and annotation UI
  unchanged.

## Verification

- The updated idle-policy regression test failed against the original code.
- `swift test`: 133 tests passed, including activity lifetime tests with injected
  acquisition/release callbacks and an idle diagnostics test.
- `plutil -lint MacScreenCapture/Info.plist` passed.
- Existing SwiftPM unhandled-file warnings for the plist and entitlements remain.

## MacBook Air Validation Still Required

Compare the same app version and workload on battery power in Activity Monitor's
Energy and CPU panes. Compare idle-to-idle and recording-to-recording, not their
different workloads. Close capture/editor windows for the idle comparison.

Check App Nap eligibility, current Energy Impact, CPU, and wakeups after settling;
the 12-hour energy average includes earlier activity and is not an immediate
post-fix measurement. Also test capture hotkeys after prolonged inactivity and
sleep/wake. Capture/encode workloads can still legitimately consume significant
energy. No battery-life improvement or disappearance of the system indication has
yet been measured on the user's Air.
