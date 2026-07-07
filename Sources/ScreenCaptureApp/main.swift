import AppKit

if CommandLine.arguments.contains("--diagnose") {
    let diagnosticApp = NSApplication.shared
    diagnosticApp.setActivationPolicy(.accessory)
    diagnosticApp.finishLaunching()

    Task { @MainActor in
        let status = await DiagnosticRunner.run(arguments: CommandLine.arguments)
        exit(status)
    }
    RunLoop.main.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
