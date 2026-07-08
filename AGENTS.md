# Agent Workflow Notes

## Local macOS app install

After compiling or packaging this project for manual testing, install the built app bundle to:

`/Applications/MacScreenCapture.app`

Use that installed app as the runtime target for user testing instead of leaving the app running from `.build/.../MacScreenCapture`. Keeping the app bundle path and bundle identifier stable avoids repeated macOS permission prompts.

The expected installed bundle identifier is:

`com.blademainer.MacScreenCapture`

