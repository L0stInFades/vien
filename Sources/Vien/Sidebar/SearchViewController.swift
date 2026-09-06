import AppKit

/// Find in the workspace folder: literal or regular-expression search across Markdown files, with
/// results grouped by file. Runs off the main thread and can be cancelled by typing again.
final class SearchViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  unowned let windowController: DocumentWindowController
  private let field = NSSearchField()
  private let caseButton = NSButton(checkboxWithTitle: "Match Case", target: nil, action: nil)
  private let regexButton = NSButton(checkboxWithTitle: "Regex", target: nil, action: nil)
  private let wordButton = NSButton(checkboxWithTitle: "Whole Word", target: nil, action: nil)
  private let table = NSTableView()
  private let status = NSTextField(labelWithString: "")
  private let stack = NSStackView()
  private let placeholder = NSTextField(wrappingLabelWithString: "Open a folder to search across its Markdown files.")
  private let openButton = NSButton(title: "Open Folder…", target: nil, action: #selector(AppDelegate.openFolder(_:)))
  private var rows: [FolderSearch.Row] = []
  private var task: Task<Void, Never>?

  init(window: DocumentWindowController) {
    windowController = window
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    view = NSView()
    field.placeholderString = "Find in folder"
    field.delegate = self
    field.sendsSearchStringImmediately = false
    field.sendsWholeSearchString = false
    for b in [caseButton, regexButton, wordButton] {
      b.controlSize = .mini
      b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      b.target = self
      b.action = #selector(optionsChanged)
    }
    let options = NSStackView(views: [caseButton, wordButton, regexButton])
    options.spacing = 8
    let column = NSTableColumn(identifier: .init("result"))
    table.addTableColumn(column)
    table.headerView = nil
    table.style = .sourceList
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.action = #selector(rowClicked)
    table.usesAutomaticRowHeights = true
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    status.textColor = .tertiaryLabelColor
    status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    for v in [field, options, status, scroll] { stack.addArrangedSubview(v) }
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    // Shown instead when no folder is open (a search across files needs one).
    placeholder.alignment = .center
    placeholder.textColor = .secondaryLabelColor
    placeholder.font = .systemFont(ofSize: NSFont.systemFontSize)
    openButton.bezelStyle = .rounded
    openButton.controlSize = .regular
    let empty = NSStackView(views: [placeholder, openButton])
    empty.orientation = .vertical
    empty.alignment = .centerX
    empty.spacing = 12
    empty.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(empty)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.topAnchor),
      stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      field.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
      empty.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      empty.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
      empty.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
      empty.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
      placeholder.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
    ])
    self.emptyView = empty
  }

  private weak var emptyView: NSView?

  /// A folder-wide search needs a workspace folder; without one, show the placeholder instead.
  func refreshFolderState() {
    let hasFolder = Workspace.shared.currentFolder != nil
    stack.isHidden = !hasFolder
    emptyView?.isHidden = hasFolder
  }

  func focusSearchField() {
    refreshFolderState()
    if Workspace.shared.currentFolder != nil { view.window?.makeFirstResponder(field) }
  }

  /// Programmatic search (automation / snapshots).
  func run(query: String) {
    field.stringValue = query
    run()
  }

  func controlTextDidChange(_ obj: Notification) { run() }
  @objc private func optionsChanged() { run() }

  private func run() {
    task?.cancel()
    let query = field.stringValue
    guard query.count >= 2 else { rows = []; table.reloadData(); status.stringValue = ""; return }
    let options = FolderSearch.Options(caseSensitive: caseButton.state == .on, regex: regexButton.state == .on, wholeWord: wordButton.state == .on)
    let files = Workspace.shared.markdownFiles()
    guard !files.isEmpty else { status.stringValue = "Open a folder to search it."; return }
    status.stringValue = "Searching…"
    task = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      let result = await FolderSearch.run(query: query, files: files, options: options)
      guard !Task.isCancelled, let self else { return }
      rows = result.rows
      table.reloadData()
      status.stringValue = result.error ?? "\(result.matchCount) matches in \(result.fileCount) files"
    }
  }

  @objc private func rowClicked() {
    let row = table.clickedRow
    guard row >= 0, row < rows.count else { return }
    let r = rows[row]
    guard case .match(let url, _, let line, let range) = r else { return }
    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
      guard let wc = document?.windowControllers.first as? DocumentWindowController else { return }
      let text = wc.editor.textView.string as NSString
      // Locate the line by number, then the match within it.
      var lineStart = 0
      var current = 0
      while current < line, lineStart < text.length {
        lineStart = NSMaxRange(text.lineRange(for: NSRange(location: lineStart, length: 0)))
        current += 1
      }
      let target = NSRange(location: min(text.length, lineStart + range.location), length: min(range.length, max(0, text.length - lineStart - range.location)))
      wc.editor.select(utf16Range: target)
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let id = NSUserInterfaceItemIdentifier("row")
    let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
      let c = NSTableCellView()
      c.identifier = id
      let f = NSTextField(wrappingLabelWithString: "")
      f.translatesAutoresizingMaskIntoConstraints = false
      f.maximumNumberOfLines = 2
      c.addSubview(f)
      c.textField = f
      NSLayoutConstraint.activate([
        f.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 4),
        f.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
        f.topAnchor.constraint(equalTo: c.topAnchor, constant: 3),
        f.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -3),
      ])
      return c
    }()
    switch rows[row] {
    case .file(let url):
      cell.textField?.attributedStringValue = NSAttributedString(string: url.lastPathComponent, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
    case .match(_, let snippet, _, let range):
      let s = NSMutableAttributedString(string: snippet, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
      if range.location + range.length <= s.length {
        s.addAttributes([.foregroundColor: NSColor.labelColor, .font: NSFont.systemFont(ofSize: 12, weight: .semibold)], range: range)
      }
      cell.textField?.attributedStringValue = s
    }
    return cell
  }

  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
    if case .file = rows[row] { return true }
    return false
  }
}

/// Multi-file text search. Reads files concurrently; matching is done on UTF-16 lines so results map
/// straight onto text-view ranges.
enum FolderSearch {
  struct Options: Sendable {
    var caseSensitive: Bool
    var regex: Bool
    var wholeWord: Bool
  }

  enum Row: Sendable {
    case file(URL)
    /// Snippet is the line's text; `range` is the match within the snippet (UTF-16).
    case match(URL, String, Int, NSRange)
  }

  struct Result: Sendable {
    var rows: [Row]
    var matchCount: Int
    var fileCount: Int
    var error: String?
  }

  static func run(query: String, files: [URL], options: Options) async -> Result {
    let pattern: String = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
    let wrapped = options.wholeWord ? "\\b(?:\(pattern))\\b" : pattern
    let regex: NSRegularExpression
    do {
      regex = try NSRegularExpression(pattern: wrapped, options: options.caseSensitive ? [] : [.caseInsensitive])
    } catch {
      return Result(rows: [], matchCount: 0, fileCount: 0, error: "Invalid regular expression")
    }
    let limit = 2000
    let results = await withTaskGroup(of: (Int, [Row]).self) { group -> [(Int, [Row])] in
      for (i, url) in files.enumerated() {
        group.addTask {
          guard let data = try? Data(contentsOf: url), data.count < 8_000_000, let text = String(data: data, encoding: .utf8) else { return (i, []) }
          var rows: [Row] = []
          var lineNumber = 0
          text.enumerateLines { line, stop in
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            for m in matches {
              rows.append(.match(url, line, lineNumber, m.range))
              if rows.count > 200 { stop = true; break }
            }
            lineNumber += 1
          }
          return (i, rows.isEmpty ? [] : [.file(url)] + rows)
        }
      }
      var all: [(Int, [Row])] = []
      for await r in group where !r.1.isEmpty { all.append(r) }
      return all.sorted { $0.0 < $1.0 }
    }
    var rows: [Row] = []
    var matches = 0
    for (_, r) in results {
      rows.append(contentsOf: r)
      matches += r.count - 1
      if rows.count > limit { break }
    }
    return Result(rows: rows, matchCount: matches, fileCount: results.count, error: nil)
  }
}
