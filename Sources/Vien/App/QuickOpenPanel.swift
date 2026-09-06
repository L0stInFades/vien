import AppKit

/// ⌘P: fuzzy-find a Markdown file in the workspace (and open documents), Spotlight-style.
final class QuickOpenPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  private let panel: NSPanel
  private let field = NSSearchField()
  private let table = NSTableView()
  private var candidates: [URL] = []
  private var results: [(URL, Int)] = []

  override init() {
    panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
    super.init()
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.hidesOnDeactivate = true
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = false
    let effect = NSVisualEffectView()
    effect.material = .popover
    effect.blendingMode = .behindWindow
    effect.state = .active
    panel.contentView = effect
    field.placeholderString = "Open file…"
    field.font = .systemFont(ofSize: 18)
    field.delegate = self
    field.focusRingType = .none
    field.translatesAutoresizingMaskIntoConstraints = false
    let column = NSTableColumn(identifier: .init("file"))
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 36
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(openSelected)
    table.style = .plain
    table.backgroundColor = .clear
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(field)
    effect.addSubview(scroll)
    NSLayoutConstraint.activate([
      field.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
      field.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
      field.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
      scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
      scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
    ])
  }

  func show() {
    var urls = NSDocumentController.shared.documents.compactMap(\.fileURL)
    for u in Workspace.shared.markdownFiles() where !urls.contains(u) { urls.append(u) }
    candidates = urls
    field.stringValue = ""
    filter()
    if let screen = NSScreen.main {
      let f = screen.visibleFrame
      panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY + 60))
    }
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(field)
  }

  func controlTextDidChange(_ obj: Notification) { filter() }

  func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
    switch selector {
    case #selector(NSResponder.moveDown(_:)):
      table.selectRowIndexes([min(results.count - 1, table.selectedRow + 1)], byExtendingSelection: false)
      table.scrollRowToVisible(table.selectedRow)
      return true
    case #selector(NSResponder.moveUp(_:)):
      table.selectRowIndexes([max(0, table.selectedRow - 1)], byExtendingSelection: false)
      table.scrollRowToVisible(table.selectedRow)
      return true
    case #selector(NSResponder.insertNewline(_:)):
      openSelected()
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      panel.orderOut(nil)
      return true
    default: return false
    }
  }

  private func filter() {
    let q = field.stringValue.lowercased()
    if q.isEmpty {
      results = candidates.prefix(50).map { ($0, 0) }
    } else {
      results = candidates.compactMap { url in
        QuickOpenPanel.score(query: q, candidate: url.lastPathComponent.lowercased(), path: url.path.lowercased()).map { (url, $0) }
      }.sorted { $0.1 > $1.1 }.prefix(50).map { $0 }
    }
    table.reloadData()
    if !results.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
  }

  /// Subsequence match with bonuses for name matches and word starts.
  static func score(query: String, candidate: String, path: String) -> Int? {
    var score = 0
    var qi = query.startIndex
    var last: String.Index? = nil
    var target = candidate
    var inName = true
    if !candidate.contains(query.first!) { target = path; inName = false }
    for (i, c) in target.enumerated() {
      guard qi < query.endIndex else { break }
      if c == query[qi] {
        score += inName ? 10 : 3
        let idx = target.index(target.startIndex, offsetBy: i)
        if let l = last, target.index(after: l) == idx { score += 5 }
        if i == 0 || target[target.index(before: idx)] == " " || target[target.index(before: idx)] == "-" || target[target.index(before: idx)] == "/" { score += 4 }
        last = idx
        qi = query.index(after: qi)
      }
    }
    return qi == query.endIndex ? score : nil
  }

  @objc private func openSelected() {
    let row = table.selectedRow
    guard row >= 0, row < results.count else { return }
    let url = results[row].0
    panel.orderOut(nil)
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { results.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let id = NSUserInterfaceItemIdentifier("qo")
    let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
      let c = NSTableCellView()
      c.identifier = id
      let name = NSTextField(labelWithString: "")
      name.font = .systemFont(ofSize: 14)
      let path = NSTextField(labelWithString: "")
      path.font = .systemFont(ofSize: 11)
      path.textColor = .secondaryLabelColor
      path.lineBreakMode = .byTruncatingMiddle
      let stack = NSStackView(views: [name, path])
      stack.orientation = .vertical
      stack.alignment = .leading
      stack.spacing = 1
      stack.translatesAutoresizingMaskIntoConstraints = false
      c.addSubview(stack)
      c.textField = name
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14),
        stack.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
        stack.centerYAnchor.constraint(equalTo: c.centerYAnchor),
      ])
      return c
    }()
    let url = results[row].0
    cell.textField?.stringValue = url.lastPathComponent
    (cell.subviews.first as? NSStackView)?.views.last.flatMap { $0 as? NSTextField }?.stringValue = url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    return cell
  }
}
