import AppKit
import UniformTypeIdentifiers

/// A folder opened as a workspace. Files are listed as Finder does, watched for changes.
final class FileTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
  unowned let windowController: DocumentWindowController
  private let outlineView = NSOutlineView()
  private let scroll = NSScrollView()
  private let placeholder = NSButton(title: "Open Folder…", target: nil, action: #selector(AppDelegate.openFolder(_:)))
  private(set) var root: FileNode?
  private var watcher: DispatchSourceFileSystemObject?

  init(window: DocumentWindowController) {
    windowController = window
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    view = NSView()
    let column = NSTableColumn(identifier: .init("name"))
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    outlineView.headerView = nil
    outlineView.style = .sourceList
    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.target = self
    outlineView.doubleAction = #selector(openClicked)
    outlineView.action = #selector(openClicked)
    outlineView.autoresizesOutlineColumn = true
    outlineView.registerForDraggedTypes([.fileURL])
    let menu = NSMenu()
    menu.delegate = self
    outlineView.menu = menu
    scroll.documentView = outlineView
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    placeholder.bezelStyle = .rounded
    placeholder.controlSize = .small
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(placeholder)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      placeholder.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
    ])
    if let url = Workspace.shared.currentFolder { open(folder: url) }
  }

  func open(folder url: URL) {
    root = FileNode(url: url, isDirectory: true)
    root?.reload()
    placeholder.isHidden = true
    outlineView.reloadData()
    if let root { outlineView.expandItem(root) }
    watch(url)
  }

  private func watch(_ url: URL) {
    watcher?.cancel()
    let fd = Darwin.open(url.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
    source.setEventHandler { [weak self] in self?.refresh() }
    source.setCancelHandler { Darwin.close(fd) }
    source.resume()
    watcher = source
  }

  func refresh() {
    guard let root else { return }
    let expanded = Set(allNodes(root).filter { outlineView.isItemExpanded($0) }.map(\.url))
    root.reload(deep: true)
    outlineView.reloadData()
    for node in allNodes(root) where expanded.contains(node.url) { outlineView.expandItem(node) }
    outlineView.expandItem(root)
  }

  private func allNodes(_ node: FileNode) -> [FileNode] {
    [node] + (node.children ?? []).flatMap(allNodes)
  }

  @objc private func openClicked() {
    let row = outlineView.clickedRow
    guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
    if node.isDirectory {
      if outlineView.isItemExpanded(node) { outlineView.collapseItem(node) } else { outlineView.expandItem(node) }
    } else if node.isMarkdown || node.isText {
      NSDocumentController.shared.openDocument(withContentsOf: node.url, display: true) { _, _, _ in }
    } else {
      NSWorkspace.shared.open(node.url)
    }
  }

  // MARK: - Data source

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    if item == nil { return root == nil ? 0 : 1 }
    return (item as? FileNode)?.children?.count ?? 0
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    if item == nil { return root! }
    return (item as! FileNode).children![index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? FileNode)?.isDirectory ?? false
  }

  func outlineViewItemWillExpand(_ notification: Notification) {
    if let node = notification.userInfo?["NSObject"] as? FileNode, node.children == nil { node.reload() }
  }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? FileNode else { return nil }
    let id = NSUserInterfaceItemIdentifier("file")
    let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
      let c = NSTableCellView()
      c.identifier = id
      let icon = NSImageView()
      icon.translatesAutoresizingMaskIntoConstraints = false
      let f = NSTextField(labelWithString: "")
      f.lineBreakMode = .byTruncatingMiddle
      f.translatesAutoresizingMaskIntoConstraints = false
      c.addSubview(icon)
      c.addSubview(f)
      c.imageView = icon
      c.textField = f
      NSLayoutConstraint.activate([
        icon.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
        icon.centerYAnchor.constraint(equalTo: c.centerYAnchor),
        icon.widthAnchor.constraint(equalToConstant: 16),
        icon.heightAnchor.constraint(equalToConstant: 16),
        f.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
        f.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
        f.centerYAnchor.constraint(equalTo: c.centerYAnchor),
      ])
      return c
    }()
    cell.textField?.stringValue = node.url.lastPathComponent
    cell.textField?.textColor = node.isDirectory || node.isMarkdown ? .labelColor : .tertiaryLabelColor
    cell.textField?.font = .systemFont(ofSize: 13)
    let symbol = node.isDirectory ? "folder" : node.isMarkdown ? "doc.text" : "doc"
    cell.imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    cell.imageView?.contentTintColor = node.isDirectory ? .controlAccentColor : .secondaryLabelColor
    return cell
  }

  // MARK: - Context menu

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let row = outlineView.clickedRow
    guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
    menu.addItem(withTitle: "New File", action: #selector(newFile), keyEquivalent: "").representedObject = node
    menu.addItem(withTitle: "New Folder", action: #selector(newFolder), keyEquivalent: "").representedObject = node
    menu.addItem(.separator())
    menu.addItem(withTitle: "Rename…", action: #selector(rename), keyEquivalent: "").representedObject = node
    menu.addItem(withTitle: "Move to Trash", action: #selector(trash), keyEquivalent: "").representedObject = node
    menu.addItem(.separator())
    menu.addItem(withTitle: "Show in Finder", action: #selector(reveal), keyEquivalent: "").representedObject = node
    menu.addItem(withTitle: "Copy Path", action: #selector(copyPath), keyEquivalent: "").representedObject = node
    for item in menu.items { item.target = self }
  }

  private func node(from sender: Any?) -> FileNode? { (sender as? NSMenuItem)?.representedObject as? FileNode }

  @objc private func newFile(_ sender: Any?) {
    guard let node = node(from: sender) else { return }
    let dir = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    var url = dir.appendingPathComponent("Untitled.md")
    var n = 1
    while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("Untitled \(n).md"); n += 1 }
    FileManager.default.createFile(atPath: url.path, contents: Data())
    refresh()
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
  }

  @objc private func newFolder(_ sender: Any?) {
    guard let node = node(from: sender) else { return }
    let dir = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
    var url = dir.appendingPathComponent("New Folder")
    var n = 1
    while FileManager.default.fileExists(atPath: url.path) { url = dir.appendingPathComponent("New Folder \(n)"); n += 1 }
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    refresh()
  }

  @objc private func rename(_ sender: Any?) {
    guard let node = node(from: sender), let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "Rename “\(node.url.lastPathComponent)”"
    let field = NSTextField(string: node.url.lastPathComponent)
    field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
    alert.accessoryView = field
    alert.addButton(withTitle: "Rename")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { [self] response in
      guard response == .alertFirstButtonReturn else { return }
      let name = field.stringValue.trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, name != node.url.lastPathComponent else { return }
      let dest = node.url.deletingLastPathComponent().appendingPathComponent(name)
      do {
        try FileManager.default.moveItem(at: node.url, to: dest)
        if let doc = NSDocumentController.shared.document(for: node.url) { doc.fileURL = dest }
        refresh()
      } catch { NSAlert(error: error).beginSheetModal(for: window) }
    }
  }

  @objc private func trash(_ sender: Any?) {
    guard let node = node(from: sender) else { return }
    try? FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
    refresh()
  }

  @objc private func reveal(_ sender: Any?) {
    guard let node = node(from: sender) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([node.url])
  }

  @objc private func copyPath(_ sender: Any?) {
    guard let node = node(from: sender) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(node.url.path, forType: .string)
  }
}

/// A file or folder in the workspace tree. Children load lazily.
final class FileNode: NSObject {
  let url: URL
  let isDirectory: Bool
  var children: [FileNode]?

  static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "text", "txt", "rmd"]

  init(url: URL, isDirectory: Bool) {
    self.url = url
    self.isDirectory = isDirectory
  }

  var isMarkdown: Bool { Self.markdownExtensions.contains(url.pathExtension.lowercased()) && url.pathExtension.lowercased() != "txt" }
  var isText: Bool { ["txt", "text"].contains(url.pathExtension.lowercased()) }

  func reload(deep: Bool = false) {
    guard isDirectory else { return }
    let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .nameKey]
    let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
    let previous = Dictionary(uniqueKeysWithValues: (children ?? []).map { ($0.url, $0) })
    children = urls
      .filter { !["node_modules", ".git"].contains($0.lastPathComponent) }
      .map { u -> FileNode in
        let dir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let node = previous[u] ?? FileNode(url: u, isDirectory: dir)
        if deep, dir, node.children != nil { node.reload(deep: true) }
        return node
      }
      .sorted { a, b in
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
      }
  }
}

/// The folder currently opened as a workspace (shared by all windows, remembered across launches).
final class Workspace {
  static let shared = Workspace()
  private(set) var currentFolder: URL? = UserDefaults.standard.url(forKey: "workspaceFolder")

  func open(_ url: URL) {
    currentFolder = url
    UserDefaults.standard.set(url, forKey: "workspaceFolder")
    var recent = recentFolders.filter { $0 != url }
    recent.insert(url, at: 0)
    UserDefaults.standard.set(Array(recent.prefix(10)).map(\.path), forKey: "recentFolders")
    NotificationCenter.default.post(name: .workspaceChanged, object: url)
  }

  var recentFolders: [URL] {
    (UserDefaults.standard.stringArray(forKey: "recentFolders") ?? []).map { URL(fileURLWithPath: $0) }
  }

  /// All Markdown files under the workspace (for quick open and search).
  func markdownFiles() -> [URL] {
    guard let root = currentFolder else { return [] }
    var out: [URL] = []
    let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
    for case let u as URL in e {
      if ["node_modules", ".git", ".build"].contains(u.lastPathComponent) { e.skipDescendants(); continue }
      if FileNode.markdownExtensions.contains(u.pathExtension.lowercased()) { out.append(u) }
    }
    return out
  }
}

extension Notification.Name {
  static let workspaceChanged = Notification.Name("app.vien.workspaceChanged")
}
