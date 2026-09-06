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
    let cell = outlineView.makeView(withIdentifier: OutlineCell.id, owner: nil) as? OutlineCell ?? OutlineCell()
    cell.label.stringValue = h.text.isEmpty ? "(untitled)" : h.text
    cell.label.font = .systemFont(ofSize: h.level <= 2 ? 13 : 12, weight: h.level <= 1 ? .semibold : .regular)
    cell.label.textColor = h.level <= 2 ? .labelColor : .secondaryLabelColor
    cell.indent.constant = 8 + CGFloat(max(0, h.level - 1)) * 12
    return cell
  }
}

/// One outline row: a label whose leading inset says how deep the heading is.
private final class OutlineCell: NSTableCellView {
  static let id = NSUserInterfaceItemIdentifier("heading")
  let label = NSTextField(labelWithString: "")
  private(set) lazy var indent = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)

  init() {
    super.init(frame: .zero)
    identifier = Self.id
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([indent, label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4), label.centerYAnchor.constraint(equalTo: centerYAnchor)])
  }

  required init?(coder: NSCoder) { fatalError() }
}
