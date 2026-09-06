import AppKit
import VienMarkdown

/// A GFM table as a grid of cell sources. Every Table menu command edits this model and writes the
/// table back formatted, so the source stays tidy and the caret stays in the same logical cell.
struct TableModel {
  var rows: [[String]]  // rows[0] is the header
  var alignments: [TableAlignment]
  var columns: Int { alignments.count }

  init?(block: Block, in doc: MarkdownDocument) {
    guard case .table(let info) = block.kind, !info.alignments.isEmpty else { return nil }
    alignments = info.alignments
    rows = block.children.map { row in row.children.map { doc.text(of: $0).trimmingCharacters(in: .whitespaces) } }
    for i in rows.indices {
      while rows[i].count < columns { rows[i].append("") }
      if rows[i].count > columns { rows[i].removeLast(rows[i].count - columns) }
    }
    if rows.isEmpty { rows = [[String](repeating: "", count: columns)] }
  }

  init(rows: Int, columns: Int) {
    alignments = [TableAlignment](repeating: .none, count: columns)
    self.rows = [(1...columns).map { "Column \($0)" }] + [[String]](repeating: [String](repeating: "", count: columns), count: max(0, rows - 1))
  }

  // MARK: Edits

  mutating func insertRow(at index: Int) { rows.insert([String](repeating: "", count: columns), at: max(0, min(rows.count, index))) }
  mutating func removeRow(at index: Int) { if rows.count > 1, rows.indices.contains(index) { rows.remove(at: index) } }
  mutating func moveRow(_ index: Int, by delta: Int) {
    let target = index + delta
    guard rows.indices.contains(index), rows.indices.contains(target) else { return }
    rows.swapAt(index, target)
  }
  mutating func insertColumn(at index: Int) {
    let at = max(0, min(columns, index))
    alignments.insert(.none, at: at)
    for i in rows.indices { rows[i].insert("", at: at) }
  }
  mutating func removeColumn(at index: Int) {
    guard columns > 1, alignments.indices.contains(index) else { return }
    alignments.remove(at: index)
    for i in rows.indices { rows[i].remove(at: index) }
  }
  mutating func moveColumn(_ index: Int, by delta: Int) {
    let target = index + delta
    guard alignments.indices.contains(index), alignments.indices.contains(target) else { return }
    alignments.swapAt(index, target)
    for i in rows.indices { rows[i].swapAt(index, target) }
  }
  mutating func setAlignment(_ a: TableAlignment, column: Int) { if alignments.indices.contains(column) { alignments[column] = a } }

  // MARK: Source

  /// The formatted table and, for each row, the UTF-16 offset of each cell's content within it.
  func render(indent: String = "") -> (text: String, cellOffsets: [[Int]]) {
    var widths = [Int](repeating: 3, count: columns)
    for r in rows { for (i, c) in r.enumerated() { widths[i] = max(widths[i], Self.displayWidth(c)) } }
    var lines: [String] = []
    var offsets: [[Int]] = []
    var position = 0
    func pad(_ s: String, _ w: Int, _ a: TableAlignment) -> (String, Int) {
      let extra = max(0, w - Self.displayWidth(s))
      switch a {
      case .right: return (String(repeating: " ", count: extra) + s, extra)
      case .center: return (String(repeating: " ", count: extra / 2) + s + String(repeating: " ", count: extra - extra / 2), extra / 2)
      default: return (s + String(repeating: " ", count: extra), 0)
      }
    }
    for (r, row) in rows.enumerated() {
      var line = indent + "|"
      var starts: [Int] = []
      for (i, cell) in row.enumerated() {
        let (padded, lead) = pad(cell, widths[i], alignments[i])
        line += " "
        starts.append(position + line.utf16.count + lead)
        line += padded + " |"
      }
      lines.append(line)
      offsets.append(starts)
      position += line.utf16.count + 1
      if r == 0 {
        let delimiter = indent + "|" + (0..<columns).map { i -> String in
          let w = widths[i]
          switch alignments[i] {
          case .left: return " :" + String(repeating: "-", count: w - 1) + " |"
          case .right: return " " + String(repeating: "-", count: w - 1) + ": |"
          case .center: return " :" + String(repeating: "-", count: max(1, w - 2)) + ": |"
          case .none: return " " + String(repeating: "-", count: w) + " |"
          }
        }.joined()
        lines.append(delimiter)
        position += delimiter.utf16.count + 1
      }
    }
    return (lines.joined(separator: "\n"), offsets)
  }

  /// East Asian wide characters take two columns in a monospaced grid.
  static func displayWidth(_ s: String) -> Int {
    s.unicodeScalars.reduce(0) { $0 + (($1.value >= 0x1100 && $1.properties.isIdeographic) || ($1.value >= 0x3000 && $1.value <= 0x9FFF) || ($1.value >= 0xAC00 && $1.value <= 0xD7AF) || ($1.value >= 0xFF00 && $1.value <= 0xFF60) ? 2 : 1) }
  }
}

extension EditorViewController {
  struct TableContext {
    let block: Block
    var model: TableModel
    var row: Int
    var column: Int
  }

  /// The table at the caret with the caret's cell, or nil when the caret is not in a table.
  func tableAtCaret() -> TableContext? {
    let doc = document.markdown
    let b = doc.byteOffset(forUTF16: textView.selectedRange().location)
    let path = doc.path(at: b)
    guard let table = path.first(where: { if case .table = $0.kind { return true }; return false }), let model = TableModel(block: table, in: doc) else { return nil }
    var row = 0, column = 0
    if let r = table.children.lastIndex(where: { $0.range.lowerBound <= b }) {
      row = r
      let cells = table.children[r].children
      if let c = cells.lastIndex(where: { $0.range.lowerBound <= b }) { column = c }
    }
    return TableContext(block: table, model: model, row: min(row, model.rows.count - 1), column: min(column, model.columns - 1))
  }

  /// Applies `change` to the table at the caret and writes it back formatted, caret in the cell it returns.
  private func editTable(_ change: (inout TableContext) -> Void) {
    guard var context = tableAtCaret() else { NSSound.beep(); return }
    change(&context)
    let doc = document.markdown
    let lo = doc.utf16Offset(forByte: context.block.range.lowerBound), hi = doc.utf16Offset(forByte: context.block.range.upperBound)
    let lineStart = textView.lineRange(at: lo).location
    let indent = (textView.string as NSString).substring(with: NSRange(location: lineStart, length: lo - lineStart))
    let (text, offsets) = context.model.render(indent: indent)
    textView.insertText(text, replacementRange: NSRange(location: lineStart, length: hi - lineStart))
    let r = max(0, min(offsets.count - 1, context.row))
    let c = max(0, min(offsets[r].count - 1, context.column))
    textView.setSelectedRange(NSRange(location: lineStart + offsets[r][c], length: 0))
  }

  @IBAction func formatTable(_ sender: Any?) { editTable { _ in } }
  @IBAction func addRowAbove(_ sender: Any?) { editTable { $0.model.insertRow(at: $0.row) } }
  @IBAction func addRowBelow(_ sender: Any?) { editTable { $0.model.insertRow(at: $0.row + 1); $0.row += 1 } }
  @IBAction func addColumnBefore(_ sender: Any?) { editTable { $0.model.insertColumn(at: $0.column) } }
  @IBAction func addColumnAfter(_ sender: Any?) { editTable { $0.model.insertColumn(at: $0.column + 1); $0.column += 1 } }
  @IBAction func deleteRow(_ sender: Any?) { editTable { $0.model.removeRow(at: $0.row); $0.row = min($0.row, $0.model.rows.count - 1) } }
  @IBAction func deleteColumn(_ sender: Any?) { editTable { $0.model.removeColumn(at: $0.column); $0.column = min($0.column, $0.model.columns - 1) } }
  @IBAction func moveRowUp(_ sender: Any?) { editTable { if $0.row > 0 { $0.model.moveRow($0.row, by: -1); $0.row -= 1 } } }
  @IBAction func moveRowDown(_ sender: Any?) { editTable { if $0.row + 1 < $0.model.rows.count { $0.model.moveRow($0.row, by: 1); $0.row += 1 } } }
  @IBAction func moveColumnLeft(_ sender: Any?) { editTable { if $0.column > 0 { $0.model.moveColumn($0.column, by: -1); $0.column -= 1 } } }
  @IBAction func moveColumnRight(_ sender: Any?) { editTable { if $0.column + 1 < $0.model.columns { $0.model.moveColumn($0.column, by: 1); $0.column += 1 } } }
  @IBAction func alignColumnLeft(_ sender: Any?) { editTable { $0.model.setAlignment(.left, column: $0.column) } }
  @IBAction func alignColumnCenter(_ sender: Any?) { editTable { $0.model.setAlignment(.center, column: $0.column) } }
  @IBAction func alignColumnRight(_ sender: Any?) { editTable { $0.model.setAlignment(.right, column: $0.column) } }
  @IBAction func alignColumnNone(_ sender: Any?) { editTable { $0.model.setAlignment(.none, column: $0.column) } }

  static let tableActions: [Selector] = [
    #selector(formatTable(_:)), #selector(addRowAbove(_:)), #selector(addRowBelow(_:)), #selector(addColumnBefore(_:)),
    #selector(addColumnAfter(_:)), #selector(deleteRow(_:)), #selector(deleteColumn(_:)), #selector(moveRowUp(_:)),
    #selector(moveRowDown(_:)), #selector(moveColumnLeft(_:)), #selector(moveColumnRight(_:)), #selector(alignColumnLeft(_:)),
    #selector(alignColumnCenter(_:)), #selector(alignColumnRight(_:)), #selector(alignColumnNone(_:)),
  ]

  /// Asks for a size, then inserts an empty table after the current line with the caret in its first cell.
  @IBAction func insertTable(_ sender: Any?) {
    guard let window = view.window else { return }
    let alert = NSAlert()
    alert.messageText = "Insert Table"
    alert.informativeText = "The header row counts as a row."
    alert.addButton(withTitle: "Insert")
    alert.addButton(withTitle: "Cancel")
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 100
    formatter.allowsFloats = false
    let rows = NSTextField(frame: NSRect(x: 84, y: 30, width: 56, height: 22))
    let columns = NSTextField(frame: NSRect(x: 84, y: 2, width: 56, height: 22))
    for (field, value) in [(rows, 3), (columns, 3)] {
      field.formatter = formatter
      field.integerValue = value
      field.alignment = .right
    }
    let rowsLabel = NSTextField(labelWithString: "Rows:")
    let columnsLabel = NSTextField(labelWithString: "Columns:")
    rowsLabel.frame = NSRect(x: 0, y: 32, width: 78, height: 18)
    columnsLabel.frame = NSRect(x: 0, y: 4, width: 78, height: 18)
    rowsLabel.alignment = .right
    columnsLabel.alignment = .right
    let box = NSView(frame: NSRect(x: 0, y: 0, width: 144, height: 54))
    for v in [rowsLabel, rows, columnsLabel, columns] { box.addSubview(v) }
    rows.nextKeyView = columns
    columns.nextKeyView = rows
    alert.accessoryView = box
    alert.window.initialFirstResponder = rows
    alert.beginSheetModal(for: window) { [weak self] response in
      guard response == .alertFirstButtonReturn, let self else { return }
      let model = TableModel(rows: max(1, min(100, rows.integerValue)), columns: max(1, min(50, columns.integerValue)))
      let (text, offsets) = model.render()
      insertBlockText(text)
      let start = textView.selectedRange().location + 1 - text.utf16.count
      textView.setSelectedRange(NSRange(location: start + (offsets.first?.first ?? 0), length: 0))
      textView.window?.makeFirstResponder(textView)
    }
  }
}
