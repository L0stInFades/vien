import AppKit

// Entry point. Menus, windows and documents are created in code; there is no storyboard.
nonisolated(unsafe) let processStart = Date()
_ = VienDocumentController()  // must exist before NSApplication finishes launching
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
if Bundle.main.bundleIdentifier == nil { app.setActivationPolicy(.regular) }  // `swift run` without a bundle
app.run()
