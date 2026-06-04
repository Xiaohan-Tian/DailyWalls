import AppKit

// The canonical SPM entry point for AppKit menu-bar apps.
// main.swift is the only file allowed to have top-level executable code.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
