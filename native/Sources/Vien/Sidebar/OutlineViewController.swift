import AppKit
import VienMarkdown

/// Table of contents: headings with indentation by level; clicking jumps, the caret's section is
/// highlighted as you move.
final class OutlineViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
  unowned let windowController: DocumentWindowController
  private let outlineView = NSOutlineView()
  private let scroll = NSScrollView()
  private var headings: [MarkdownDocument.Heading] = []
  private let emptyLabel = NSTextField(labelWithString: "No headings")

  init(window: DocumentWindowController) {
    windowController = window
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    view = NSView()
    let column = NSTableColumn(identifier: .init("heading"))
    column.isEditable = false
    outlineView.addTableColumn(column)
    outlineView.outlineTableColumn = column
    outlineView.headerView = nil
    outlineView.style = .sourceList
    outlineView.rowSizeStyle = .default
    outlineView.indentationPerLevel = 0
    outlineView.dataSource = self
    outlineView.delegate = self
    outlineView.target = self
    outlineView.action = #selector(rowClicked)
    scroll.documentView = outlineView
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(scroll)
    emptyLabel.textColor = .tertiaryLabelColor
    emptyLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    emptyLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(emptyLabel)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      emptyLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
    ])
    reload()
  }

  func reload() {
    headings = windowController.markdownFile.markdown.headings()
    emptyLabel.isHidden = !headings.isEmpty
    outlineView.reloadData()
  }

  func highlight(utf16 location: Int) {
    guard !headings.isEmpty else { return }
    let b = windowController.markdownFile.markdown.byteOffset(forUTF16: location)
    var index = -1
    for (i, h) in headings.enumerated() where h.range.lowerBound <= b { index = i }
    if index >= 0, outlineView.selectedRow != index {
      outlineView.selectRowIndexes([index], byExtendingSelection: false)
      outlineView.scrollRowToVisible(index)
    }
  }

  @objc private func rowClicked() {
    let row = outlineView.clickedRow
    guard row >= 0, row < headings.count else { return }
    windowController.editor.scroll(toByteOffset: headings[row].range.lowerBound)
  }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? headings.count : 0 }
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { index }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let i = item as? Int, i < headings.count else { return nil }
    let h = headings[i]
    let id = NSUserInterfaceItemIdentifier("cell")
    let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
      let c = NSTableCellView()
      c.identifier = id
      let f = NSTextField(labelWithString: "")
      f.lineBreakMode = .byTruncatingTail
      f.translatesAutoresizingMaskIntoConstraints = false
      c.addSubview(f)
      c.textField = f
      NSLayoutConstraint.activate([
        f.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
        f.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
        f.centerYAnchor.constraint(equalTo: c.centerYAnchor),
      ])
      return c
    }()
    cell.textField?.stringValue = h.text.isEmpty ? "(untitled)" : h.text
    cell.textField?.font = h.level <= 1 ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 12)
    cell.textField?.textColor = h.level <= 2 ? .labelColor : .secondaryLabelColor
    cell.textField?.constraints.first(where: { $0.firstAttribute == .leading })?.constant = 8 + CGFloat(max(0, h.level - 1)) * 12
    return cell
  }
}
