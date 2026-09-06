import AppKit
import UniformTypeIdentifiers
import VienMarkdown

final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var activeWindow: DocumentWindowController?
  private var settingsWindow: NSWindowController?
  private var aboutWindow: AboutWindowController?
  private var quickOpen: QuickOpenPanel?

  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = MainMenu.build()
    NSWindow.allowsAutomaticWindowTabbing = true
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let env = ProcessInfo.processInfo.environment
    if env["VIEN_SNAPSHOT_DARK"] != nil { NSApp.appearance = NSAppearance(named: .darkAqua) }
    if let out = exportRequest() {
      Task { await Headless.export(out); NSApp.terminate(nil) }
      return
    }
    // Scripted runs (screenshots, benchmarks, automation) must not steal the keyboard from whoever
    // is using the Mac: a stray keystroke would land in the document.
    let scripted = env["VIEN_SCRIPT"] != nil || env["VIEN_SNAPSHOT"] != nil || env["VIEN_QUIT_WHEN_READY"] != nil
    if !scripted { NSApp.activate() }
    // Paths given on the command line (`swift run Vien file.md`).
    let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
    if !paths.isEmpty { application(NSApp, open: paths.map { URL(fileURLWithPath: $0) }) }
    if let folder = env["VIEN_WORKSPACE"] {
      // Documents open asynchronously; attach the folder once a window exists.
      Task { try? await Task.sleep(for: .milliseconds(600)); open(folder: URL(fileURLWithPath: folder)) }
    }
    if let path = env["VIEN_SNAPSHOT"] {
      Task { await Snapshot.capture(to: path) }
    }
    if let script = env["VIEN_SCRIPT"] {
      Task { await Automation.run(script) }
    }
    if env["VIEN_SCRIPT"] == nil, env["VIEN_SNAPSHOT"] == nil, env["VIEN_QUIT_WHEN_READY"] == nil {
      Task {
        try? await Task.sleep(for: .seconds(3))
        Updater.shared.checkAutomatically()
      }
    }
    if env["VIEN_QUIT_WHEN_READY"] != nil {
      // Launch benchmark: report time-to-first-window and resident memory, then quit.
      Task {
        while Snapshot.frontWindow == nil { try? await Task.sleep(for: .milliseconds(5)) }
        trace("app: first window visible")
        let wc = Snapshot.frontWindow?.windowController as? DocumentWindowController
        wc?.editor.textView.layoutSubtreeIfNeeded()
        wc?.editor.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        let ms = (Date().timeIntervalSince(processStart) * 1000).rounded()
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        let mb = kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
        print(String(format: "ready: %.0f ms · resident %.1f MB · %d bytes of text · %d paragraphs styled", ms, mb, wc?.editor.textView.string.utf8.count ?? 0, Styler.paragraphsStyled))
        NSApp.terminate(nil)
      }
    }
  }

  @IBAction func checkForUpdates(_ sender: Any?) {
    Task { await Updater.shared.check(userInitiated: true) }
  }

  /// `Vien --export html|pdf input.md output` runs without a window (used by scripts and tests).
  private func exportRequest() -> (String, URL, URL)? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--export"), i + 3 < args.count else { return nil }
    return (args[i + 1], URL(fileURLWithPath: args[i + 2]), URL(fileURLWithPath: args[i + 3]))
  }

  func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
    // An empty document is the calmer start; the sidebar still shows the last folder. Not when a
    // file was named on the command line (it opens a moment later) or the run is headless.
    let env = ProcessInfo.processInfo.environment
    let named = CommandLine.arguments.dropFirst().contains { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
    return !named && env["VIEN_SCRIPT"] == nil && env["VIEN_SNAPSHOT"] == nil && env["VIEN_QUIT_WHEN_READY"] == nil && exportRequest() == nil
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
        if let error { NSApp.presentError(error) }
      }
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

  // MARK: - Folders

  @IBAction func openFolder(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Open Folder"
    panel.begin { [self] response in
      guard response == .OK, let url = panel.url else { return }
      open(folder: url)
    }
  }

  func open(folder url: URL) {
    Workspace.shared.open(url)
    let wc: DocumentWindowController
    if let active = activeWindow ?? NSApp.mainWindow?.windowController as? DocumentWindowController
      ?? NSApp.orderedWindows.compactMap({ $0.windowController as? DocumentWindowController }).first
    {
      wc = active
    } else {
      NSDocumentController.shared.newDocument(nil)
      guard let w = NSApp.mainWindow?.windowController as? DocumentWindowController else { return }
      wc = w
    }
    wc.sidebar.files.open(folder: url)
    wc.showSidebar(.files)
    NSDocumentController.shared.noteNewRecentDocumentURL(url)
  }

  @IBAction func openRecentFolder(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? URL else { return }
    open(folder: url)
  }

  @IBAction func quickOpen(_ sender: Any?) {
    if quickOpen == nil { quickOpen = QuickOpenPanel() }
    quickOpen?.show()
  }

  // MARK: - Settings

  @IBAction func showSettings(_ sender: Any?) {
    if settingsWindow == nil { settingsWindow = SettingsWindowController() }
    settingsWindow?.showWindow(nil)
    settingsWindow?.window?.makeKeyAndOrderFront(nil)
  }

  @IBAction func showAbout(_ sender: Any?) {
    if aboutWindow == nil { aboutWindow = AboutWindowController() }
    aboutWindow?.showWindow(nil)
    aboutWindow?.window?.makeKeyAndOrderFront(nil)
  }

  var settingsPanel: NSWindow? { settingsWindow?.window }

  // MARK: - Help

  @IBAction func openMarkdownReference(_ sender: Any?) {
    NSWorkspace.shared.open(URL(string: "https://commonmark.org/help/")!)
  }

  @IBAction func openWebsite(_ sender: Any?) {
    NSWorkspace.shared.open(URL(string: "https://github.com/L0stInFades/vien")!)
  }

  @IBAction func reportIssue(_ sender: Any?) {
    NSWorkspace.shared.open(URL(string: "https://github.com/L0stInFades/vien/issues")!)
  }
}

/// `VIEN_SCRIPT="type:- item|enter|tab|type:x|dump|quit"` drives the editor the way keys would, then
/// prints the resulting text. Used to check the smart-editing behaviours without a human.
enum Automation {
  static func run(_ script: String) async {
    while Snapshot.frontWindow == nil { try? await Task.sleep(for: .milliseconds(5)) }
    try? await Task.sleep(for: .milliseconds(300))
    guard let wc = Snapshot.frontWindow?.windowController as? DocumentWindowController else { NSApp.terminate(nil); return }
    let tv = wc.editor.textView!
    var elapsed: TimeInterval = 0  // of the previous step, for `time`
    var detail = "", lastDetail = ""
    for step in script.components(separatedBy: "§") {
      let parts = step.split(separator: ":", maxSplits: 1).map(String.init)
      let name = parts[0], arg = parts.count > 1 ? parts[1] : ""
      let t0 = Date()
      defer { elapsed = Date().timeIntervalSince(t0); lastDetail = detail; detail = "" }
      switch name {
      case "type": tv.insertText(arg.replacingOccurrences(of: "\\n", with: "\n"), replacementRange: tv.selectedRange())
      case "enter": tv.insertNewline(nil)
      case "tab": tv.insertTab(nil)
      case "backtab": tv.insertBacktab(nil)
      case "backspace": tv.deleteBackward(nil)
      case "select": if let a = Int(arg.split(separator: ",")[0]), let b = Int(arg.split(separator: ",")[1]) { tv.setSelectedRange(NSRange(location: a, length: b)) }
      case "goto":
        let r = (tv.string as NSString).range(of: arg)
        if r.location != NSNotFound {
          tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
          tv.scrollRangeToVisible(tv.selectedRange())
        }
      case "clicktable":
        // clicktable:row,col — clicks the centre of that cell in the first folded table on screen.
        let parts = arg.split(separator: ",").compactMap { Int($0) }
        if parts.count == 2, let lm = tv.textLayoutManager, let window = tv.window {
          lm.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            guard let table = fragment as? TableFragment, let grid = table.grid, parts[0] < grid.cells.count, parts[1] < grid.cells[parts[0]].count else { return true }
            let cell = grid.cells[parts[0]][parts[1]].frame
            let frame = table.layoutFragmentFrame
            let p = tv.convert(CGPoint(x: frame.minX + table.gridOrigin.x + cell.midX + tv.textContainerInset.width, y: frame.minY + table.gridOrigin.y + cell.midY + tv.textContainerInset.height), to: nil)
            if let event = NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
              tv.mouseDown(with: event)
            }
            return false
          }
        }
      case "end": tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
      case "bold": wc.editor.toggleBold(nil)
      case "heading": wc.editor.setHeading(Int(arg) ?? 1)
      case "bullets": wc.editor.toggleBulletList(nil)
      case "quote": wc.editor.toggleBlockQuote(nil)
      case "table": wc.editor.formatTable(nil)
      case "undo": tv.undoManager?.undo()
      case "wait": try? await Task.sleep(for: .milliseconds(Int(arg) ?? 0))
      case "pagedown":
        for _ in 0..<(Int(arg) ?? 1) {
          let styled = Styler.paragraphsStyled
          let styling = Styler.stylingTime
          let a = Date()
          tv.scrollPageDown(nil)
          tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
          let b = Date()
          tv.displayIfNeeded()
          detail = String(format: " (layout %.1f of which styling %.1f · draw %.1f · %d paragraphs)", b.timeIntervalSince(a) * 1000, (Styler.stylingTime - styling) * 1000, Date().timeIntervalSince(b) * 1000, Styler.paragraphsStyled - styled)
        }
      case "recycle": wc.editor.recycleElements()
      case "fullscreen": wc.window?.toggleFullScreen(nil)
      case "sidebar":
        if arg == "hide" { wc.hideSidebar() } else { wc.showSidebar(arg == "files" ? .files : arg == "search" ? .search : .outline, animated: false) }
      case "theme": Preferences.shared.theme = arg
      case "update":
        if arg == "install" { await Updater.shared.checkAndInstall() } else { await Updater.shared.check(userInitiated: true) }
      case "key":
        // A real key event through the application's event loop (undo grouping, key bindings).
        NSApp.activate()
        if let window = tv.window, let down = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: arg, charactersIgnoringModifiers: arg, isARepeat: false, keyCode: 0) {
          NSApp.postEvent(down, atStart: false)
        }
      case "undoinfo": print("undo: canUndo \(tv.undoManager?.canUndo ?? false) level \(tv.undoManager?.groupingLevel ?? -1) groupsByEvent \(tv.undoManager?.groupsByEvent ?? false) name '\(tv.undoManager?.undoActionName ?? "")'")
      case "inserttable":
        let n = arg.split(separator: ",").compactMap { Int($0) }
        if n.count == 2 { wc.editor.insertTable(rows: n[0], columns: n[1]) }
      case "action":
        let selector = NSSelectorFromString(arg)
        if let target = ([wc.editor, tv, wc, NSApp.delegate as? NSObject].compactMap { $0 }).first(where: { $0.responds(to: selector) }) { _ = target.perform(selector, with: nil) } else { print("unknown action \(arg)") }
      case "activate":  // for screenshots that should show an active window
        NSApp.activate(ignoringOtherApps: true)
        try? await Task.sleep(for: .milliseconds(150))
        print("active: \(NSApp.isActive) key: \(wc.window?.isKeyWindow ?? false)")
      case "snap": Snapshot.write(window: wc.window!, to: arg)
      case "doodle":
        // Drags the reader's pen across the About window in a short wave.
        if let about = NSApp.windows.first(where: { $0.title == "About Vien" }), let view = about.contentView {
          func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: about.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
          }
          let points = (0...30).map { i -> CGPoint in let t = CGFloat(i) / 30; return CGPoint(x: 70 + t * 300, y: 120 + sin(t * .pi * 2) * 30 - t * 30) }
          view.mouseDown(with: event(.leftMouseDown, points[0]))
          for p in points.dropFirst() { view.mouseDragged(with: event(.leftMouseDragged, p)); try? await Task.sleep(for: .milliseconds(12)) }
          view.mouseUp(with: event(.leftMouseUp, points[points.count - 1]))
        }
      case "top":
        // Scroll so the phrase sits 60pt below the top edge (diagrams render beneath their fence).
        // The caret stays put, so the block keeps its folded look.
        let ns = tv.string as NSString
        let r = ns.range(of: arg)
        if r.location != NSNotFound, let lm = tv.textLayoutManager, let cs = lm.textContentManager as? NSTextContentStorage, let loc = cs.location(cs.documentRange.location, offsetBy: r.location) {
          lm.ensureLayout(for: NSTextRange(location: loc))
          if let frag = lm.textLayoutFragment(for: loc) {
            let y = frag.layoutFragmentFrame.minY + tv.textContainerInset.height - 60
            wc.editor.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            wc.editor.scrollView.reflectScrolledClipView(wc.editor.scrollView.contentView)
          }
        }
      case "snapkey":
        // The most recently shown visible window other than the document (About panel, sheets…).
        let others = NSApp.windows.filter { $0.isVisible && $0 != wc.window && $0.frame.width > 50 && $0.frame.height > 50 }
        print("windows: " + others.map { "\(type(of: $0)) '\($0.title)' \(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ", "))
        Snapshot.write(window: others.last ?? wc.window!, to: arg)
      case "window":
        let n = arg.split(separator: ",").compactMap { Double($0) }
        if n.count == 2, let w = wc.window { w.setFrame(NSRect(x: w.frame.minX, y: max(0, w.frame.maxY - n[1]), width: n[0], height: n[1]), display: true) }
      case "stats":
        let scroll = wc.editor.scrollView!
        print("elements: \(wc.editor.elementsCreated) · scroll y: \(Int(tv.visibleRect.minY)) · selection: \(tv.selectedRange()) · window: \(Int(wc.window?.frame.width ?? 0))x\(Int(wc.window?.frame.height ?? 0)) · clip \(Int(scroll.contentView.bounds.origin.y)) inset \(Int(scroll.contentInsets.top)) doc \(Int(tv.frame.height)) view \(Int(scroll.contentSize.height))")
      case "time": print(String(format: "time: %.2f ms", elapsed * 1000) + lastDetail)
      case "dump": print("--- text ---\n" + tv.string + "--- end ---")
      case "selection": print("selection: \(tv.selectedRange())")
      case "quit":
        // Scripted edits stay in memory: never autosave them over the file that was opened.
        for document in NSDocumentController.shared.documents { document.updateChangeCount(.changeCleared) }
        NSApp.terminate(nil)
        return
      default: print("unknown step \(name)")
      }
      if name == "type" || name == "enter" { print(String(format: "%@: %.2f ms", name, Date().timeIntervalSince(t0) * 1000)) }
    }
    NSApp.terminate(nil)
  }
}

/// Headless conversions for scripts: the same code paths the menu uses.
enum Headless {
  static func export(_ request: (String, URL, URL)) async {
    let (format, input, output) = request
    do {
      let doc = try MarkdownFile(contentsOf: input, ofType: MarkdownFile.markdownType)
      switch format {
      case "html":
        let html = await HTMLExport.document(for: doc, title: input.deletingPathExtension().lastPathComponent)
        try html.write(to: output, atomically: true, encoding: .utf8)
      case "pdf":
        try HTMLExport.pdf(for: doc).write(to: output)
      default:
        FileHandle.standardError.write(Data("unknown export format \(format)\n".utf8))
      }
    } catch {
      FileHandle.standardError.write(Data("export failed: \(error)\n".utf8))
    }
  }
}

/// `VIEN_SNAPSHOT=/path.png` renders the front window to a PNG shortly after launch and quits.
/// Used by scripts to look at the app without a human at the screen.
enum Snapshot {
  /// The document window to drive, whether or not the app is frontmost.
  static var frontWindow: NSWindow? {
    NSApp.mainWindow ?? NSApp.orderedWindows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) && $0.windowController is DocumentWindowController })
  }

  static func capture(to path: String) async {
    try? await Task.sleep(for: .milliseconds(1800))
    if ProcessInfo.processInfo.environment["VIEN_SNAPSHOT_SETTINGS"] != nil {
      (NSApp.delegate as? AppDelegate)?.showSettings(nil)
      try? await Task.sleep(for: .milliseconds(800))
      if let w = (NSApp.delegate as? AppDelegate)?.settingsPanel, let v = w.contentView?.superview {
        v.displayIfNeeded()
        if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
          v.cacheDisplay(in: v.bounds, to: rep)
          try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
      }
      NSApp.terminate(nil)
      return
    }
    if ProcessInfo.processInfo.environment["VIEN_SNAPSHOT_QUICKOPEN"] != nil {
      (NSApp.delegate as? AppDelegate)?.quickOpen(nil)
      try? await Task.sleep(for: .milliseconds(700))
      if let w = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible }), let v = w.contentView {
        v.displayIfNeeded()
        if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
          v.cacheDisplay(in: v.bounds, to: rep)
          try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
      }
      NSApp.terminate(nil)
      return
    }
    if let pane = ProcessInfo.processInfo.environment["VIEN_SNAPSHOT_SIDEBAR"], let wc = frontWindow?.windowController as? DocumentWindowController {
      let p: SidebarViewController.Pane = pane == "files" ? .files : pane == "search" ? .search : .outline
      wc.showSidebar(p, animated: false)
      if pane == "search", let q = ProcessInfo.processInfo.environment["VIEN_SNAPSHOT_QUERY"] { wc.sidebar.search.run(query: q) }
      try? await Task.sleep(for: .milliseconds(600))
    }
    guard let window = frontWindow, window.contentView?.superview != nil else {
      NSLog("snapshot: no window")
      NSApp.terminate(nil)
      return
    }
    // Optionally scroll to a phrase first (VIEN_SNAPSHOT_AT="## Diagram").
    if let phrase = ProcessInfo.processInfo.environment["VIEN_SNAPSHOT_AT"], let wc = window.windowController as? DocumentWindowController {
      let ns = wc.editor.textView.string as NSString
      let r = ns.range(of: phrase)
      if r.location != NSNotFound {
        wc.editor.textView.setSelectedRange(NSRange(location: r.location, length: 0))
        wc.editor.textView.scrollRangeToVisible(NSRange(location: r.location, length: 0))
        // Put the phrase near the top: scroll so the caret line sits 60pt below the top edge.
        if let lm = wc.editor.textView.textLayoutManager, let cs = lm.textContentManager as? NSTextContentStorage,
          let loc = cs.location(cs.documentRange.location, offsetBy: r.location)
        {
          lm.ensureLayout(for: NSTextRange(location: loc))
          if let frag = lm.textLayoutFragment(for: loc) {
            let y = frag.layoutFragmentFrame.minY + wc.editor.textView.textContainerInset.height - 60
            wc.editor.scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, y)))
            wc.editor.scrollView.reflectScrolledClipView(wc.editor.scrollView.contentView)
          }
        }
      }
    }
    // Wait for diagrams that may still be rendering, then force a layout pass for the viewport.
    try? await Task.sleep(for: .milliseconds(1200))
    Snapshot.write(window: window, to: path)
    NSApp.terminate(nil)
  }

  /// Lays out the viewport and writes the window (with any attached sheet composited on top) as a PNG.
  static func write(window: NSWindow, to path: String) {
    guard let view = window.contentView?.superview else { return }
    if let wc = window.windowController as? DocumentWindowController {
      wc.editor.textView.layoutSubtreeIfNeeded()
      wc.editor.textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
      wc.editor.textView.needsDisplay = true
    }
    func image(of v: NSView) -> NSImage? {
      v.layoutSubtreeIfNeeded()
      v.displayIfNeeded()
      guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return nil }
      v.cacheDisplay(in: v.bounds, to: rep)
      let img = NSImage(size: v.bounds.size)
      img.addRepresentation(rep)
      return img
    }
    guard let base = image(of: view) else { return }
    let composite = NSImage(size: base.size)
    composite.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: base.size))
    for sheet in window.sheets {
      guard let sv = sheet.contentView?.superview, let img = image(of: sv) else { continue }
      let origin = NSPoint(x: sheet.frame.minX - window.frame.minX, y: sheet.frame.minY - window.frame.minY)
      img.draw(in: NSRect(origin: origin, size: img.size))
    }
    composite.unlockFocus()
    if let tiff = composite.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
      try? png.write(to: URL(fileURLWithPath: path))
    }
  }
}
