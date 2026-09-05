import AppKit

// Entry point. Menus, windows and documents are created in code; there is no storyboard.
nonisolated(unsafe) let processStart = Date()
nonisolated(unsafe) let traceEnabled = ProcessInfo.processInfo.environment["VIEN_TRACE"] != nil
/// Prints `label` with milliseconds since launch when VIEN_TRACE is set.
func trace(_ label: @autoclosure () -> String) {
  guard traceEnabled else { return }
  print(String(format: "%6.0f ms  %@", Date().timeIntervalSince(processStart) * 1000, label()))
}
_ = VienDocumentController()  // must exist before NSApplication finishes launching
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
if Bundle.main.bundleIdentifier == nil { app.setActivationPolicy(.regular) }  // `swift run` without a bundle
app.run()
