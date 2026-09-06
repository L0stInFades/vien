import AppKit
import VienMarkdown

/// One document window: a collapsible sidebar (files / outline / search) beside the editor.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
  private(set) var editor: EditorViewController!
  private(set) var sidebar: SidebarViewController!
  private var split: NSSplitViewController!

  var markdownFile: MarkdownFile { document as! MarkdownFile }

  init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.minSize = NSSize(width: 480, height: 320)
    window.tabbingMode = .preferred
    window.tabbingIdentifier = "app.vien.document"
    window.titlebarSeparatorStyle = .automatic
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.delegate = self
    shouldCascadeWindows = true
    windowFrameAutosaveName = "VienDocumentWindow"
  }

  required init?(coder: NSCoder) { fatalError() }

  override var document: AnyObject? {
    didSet {
      guard let file = document as? MarkdownFile, editor == nil else { return }
      build(for: file)
    }
  }

  private func build(for file: MarkdownFile) {
    editor = EditorViewController(document: file)
    sidebar = SidebarViewController(window: self)
    split = NSSplitViewController()
    let side = NSSplitViewItem(sidebarWithViewController: sidebar)
    side.minimumThickness = 200
    side.maximumThickness = 420
    side.canCollapse = true
    side.isCollapsed = true
    side.allowsFullHeightLayout = true
    side.titlebarSeparatorStyle = .automatic
    let main = NSSplitViewItem(viewController: editor)
    main.minimumThickness = 360
    split.addSplitViewItem(side)
    split.addSplitViewItem(main)
    split.splitView.autosaveName = "VienSplit"
    // Attaching the content resizes the window to the split view's fitting size; put the saved
    // (or default 1040×760) frame back.
    let initial = window?.frame
    split.view.frame = NSRect(origin: .zero, size: initial?.size ?? NSSize(width: 1040, height: 760))
    contentViewController = split
    if window?.setFrameUsingName(windowFrameAutosaveName) != true, let initial { window?.setFrame(initial, display: false) }

    let toolbar = NSToolbar(identifier: "app.vien.document.toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    window?.toolbar = toolbar

    editor.onStatsChange = { [weak self] wc in
      self?.window?.subtitle = "\(wc.words.formatted()) words · \(wc.characters.formatted()) characters"
      self?.sidebar.outlineChanged()
    }
    editor.onSelectionChange = { [weak self] location in
      self?.sidebar.selectionMoved(toUTF16: location)
    }
  }

  // MARK: - Toolbar

  private static let sourceItem = NSToolbarItem.Identifier("app.vien.source")

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.sourceItem]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch id {
    case Self.sourceItem:
      let item = NSToolbarItem(itemIdentifier: id)
      item.label = "Source"
      item.toolTip = "Show Markdown source without styling (⌥⌘S)"
      item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: "Source")
      item.target = editor
      item.action = #selector(EditorViewController.toggleSourceMode(_:))
      return item
    default:
      return nil
    }
  }

  // MARK: - Sidebar

  @IBAction func toggleSidebar(_ sender: Any?) {
    split.splitViewItems.first?.animator().isCollapsed.toggle()
  }

  func showSidebar(_ pane: SidebarViewController.Pane, animated: Bool = true) {
    if let side = split.splitViewItems.first, side.isCollapsed {
      if animated && window?.isVisible == true { side.animator().isCollapsed = false } else { side.isCollapsed = false }
    }
    sidebar.show(pane)
  }

  @IBAction func toggleOutline(_ sender: Any?) {
    if let side = split.splitViewItems.first, !side.isCollapsed, sidebar.pane == .outline {
      side.animator().isCollapsed = true
    } else {
      showSidebar(.outline)
    }
  }

  @IBAction func findInFolder(_ sender: Any?) { showSidebar(.search) }

  // MARK: - Window delegate

  func windowDidBecomeMain(_ notification: Notification) {
    (NSApp.delegate as? AppDelegate)?.activeWindow = self
  }

  /// In full screen keep the toolbar visible (the menu bar still auto-hides), so the sidebar toggle,
  /// pane switcher and source button stay reachable without hunting for them at the screen edge.
  func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
    var options = proposedOptions
    options.remove(.autoHideToolbar)
    return options
  }
}
