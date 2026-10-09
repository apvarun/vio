import AppKit

// Read by the needle runtime when it initialises; must be set before the first model load.
setenv("NEEDLE_TELEMETRY", "0", 1)
setenv("DO_NOT_TRACK", "1", 1)

if CommandLine.arguments.contains("--selftest") {
    Selftest.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
