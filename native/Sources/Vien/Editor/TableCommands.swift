import AppKit
import VienMarkdown

/// A GFM table as a grid of cell sources, read from the raw row lines (so escaped pipes, extra
/// cells and the lines' own prefixes survive). Every Table menu command edits this model and writes
/// the table back formatted, with the caret in the same logical cell.
struct TableModel: Equatable {
  var rows: [[String]]  // rows[0] is the header; body rows may carry extra cells past `columns`
  var alignments: [TableAlignment]
  /// Text before the table on its first line (list marker, quote prefix…) and on the lines after.
  var firstPrefix = ""
  var continuationPrefix = ""
  var columns: Int { alignments.count }

  /// Reads the table at `block`; `text` is the whole document (UTF-16 offsets from `doc`).
  init?(block: Block, in doc: MarkdownDocument, text: NSString) {
    guard case .table(let info) = block.kind, !info.alignments.isEmpty else { return nil }
    alignments = info.alignments
    let lines = Self.lines(of: block, in: doc, text: text)
    guard lines.count >= 2 else { return nil }
    firstPrefix = lines[0].prefix
    continuationPrefix = lines[1].prefix
    rows = lines.enumerated().compactMap { i, line in i == 1 ? nil : Self.cells(of: line.content) }
    if rows.isEmpty { rows = [[String](repeating: "", count: columns)] }
    for i in rows.indices where rows[i].count < columns { rows[i] += [String](repeating: "", count: columns - rows[i].count) }
  }

  init(rows: Int, columns: Int) {
    alignments = [TableAlignment](repeating: .none, count: columns)
    self.rows = [(1...columns).map { "Column \($0)" }] + [[String]](repeating: [String](repeating: "", count: columns), count: max(0, rows - 1))
  }

  /// The table's lines: (UTF-16 range of the line, prefix before the row, row content).
  static func lines(of block: Block, in doc: MarkdownDocument, text: NSString) -> [(range: NSRange, prefix: String, content: String)] {
    let lo = doc.utf16Offset(forByte: block.range.lowerBound), hi = doc.utf16Offset(forByte: block.range.upperBound)
    var out: [(NSRange, String, String)] = []
    var cursor = text.lineRange(for: NSRange(location: lo, length: 0)).location
    var first = true
    while cursor < hi {
      let line = text.lineRange(for: NSRange(location: cursor, length: 0))
      var body = text.substring(with: line)
      while body.hasSuffix("\n") || body.hasSuffix("\r") { body.removeLast() }
      // The row starts at the first pipe, or at the block start on the first line.
      let contentStart: Int
      if first {
        contentStart = lo - line.location
        first = false
      } else {
        contentStart = body.utf16.firstIndex(of: 0x7C).map { body.utf16.distance(from: body.utf16.startIndex, to: $0) }
          ?? body.utf16.count - body.trimmingCharacters(in: .whitespaces).utf16.count
      }
      let idx = body.utf16.index(body.utf16.startIndex, offsetBy: min(contentStart, body.utf16.count))
      out.append((line, String(body.utf16[..<idx])!, String(body.utf16[idx...])!))
      cursor = NSMaxRange(line)
      if line.length == 0 { break }
    }
    return out
  }

  /// Splits a row on unescaped pipes (GFM: `\|` is a literal pipe, even inside code spans).
  static func cells(of row: String) -> [String] {
    var cells: [String] = []
    var current = ""
    var escaped = false
    var chars = Array(row)
    if chars.first == "|" { chars.removeFirst() }
    if chars.last == "|", !(chars.count >= 2 && chars[chars.count - 2] == "\\") { chars.removeLast() }
    for ch in chars {
      if escaped { current.append(ch); escaped = false; continue }
      if ch == "\\" { current.append(ch); escaped = true; continue }
      if ch == "|" { cells.append(current.trimmingCharacters(in: .whitespaces)); current = "" } else { current.append(ch) }
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
  }

  /// Column index of `offset` (UTF-16, within `row`), counting unescaped pipes before it.
  static func column(at offset: Int, in row: String) -> Int {
    var column = 0
    var escaped = false
    var leading = true
    var i = 0
    for ch in row.utf16 {
      if i >= offset { break }
      i += 1
      if escaped { escaped = false; continue }
      if ch == 0x5C { escaped = true; continue }
      if ch == 0x7C { if leading { leading = false } else { column += 1 } } else if ch != 0x20, ch != 0x09 { leading = false }
    }
    return column
  }

  // MARK: Edits (the header row is fixed: it cannot move, be deleted, or get a row above it)

  mutating func insertRow(at index: Int) { rows.insert([String](repeating: "", count: columns), at: max(1, min(rows.count, index))) }
  mutating func removeRow(at index: Int) { if index >= 1, rows.indices.contains(index) { rows.remove(at: index) } }
  mutating func moveRow(_ index: Int, by delta: Int) {
    let target = index + delta
    guard index >= 1, target >= 1, rows.indices.contains(index), rows.indices.contains(target) else { return }
    rows.swapAt(index, target)
  }
  mutating func insertColumn(at index: Int) {
    let at = max(0, min(columns, index))
    alignments.insert(.none, at: at)
    for i in rows.indices { rows[i].insert("", at: min(at, rows[i].count)) }
  }
  mutating func removeColumn(at index: Int) {
    guard columns > 1, alignments.indices.contains(index) else { return }
    alignments.remove(at: index)
    for i in rows.indices where rows[i].indices.contains(index) { rows[i].remove(at: index) }
  }
  mutating func moveColumn(_ index: Int, by delta: Int) {
    let target = index + delta
    guard alignments.indices.contains(index), alignments.indices.contains(target) else { return }
    alignments.swapAt(index, target)
    for i in rows.indices where rows[i].indices.contains(index) && rows[i].indices.contains(target) { rows[i].swapAt(index, target) }
  }
  mutating func setAlignment(_ a: TableAlignment, column: Int) { if alignments.indices.contains(column) { alignments[column] = a } }

  // MARK: Source

  /// The formatted table and, for each row, the UTF-16 offset of each cell's content within it.
  func render() -> (text: String, cellOffsets: [[Int]]) {
    var widths = [Int](repeating: 3, count: columns)
    for r in rows { for (i, c) in r.prefix(columns).enumerated() { widths[i] = max(widths[i], Self.displayWidth(c)) } }
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
      var line = (r == 0 ? firstPrefix : continuationPrefix) + "|"
      var starts: [Int] = []
      for (i, cell) in row.enumerated() {
        let (padded, lead) = i < columns ? pad(cell, widths[i], alignments[i]) : (cell, 0)
        line += " "
        starts.append(position + line.utf16.count + lead)
        line += padded + " |"
      }
      lines.append(line)
      offsets.append(starts)
      position += line.utf16.count + 1
      if r == 0 {
        let delimiter = continuationPrefix + "|" + (0..<columns).map { i -> String in
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

  /// Columns a cell takes in a monospaced grid: East Asian wide characters and emoji count two,
  /// joiners and variation selectors none.
  static func displayWidth(_ s: String) -> Int {
    var w = 0
    for u in s.unicodeScalars {
      let v = u.value
      if v == 0x200D || v == 0xFE0E || v == 0xFE0F || (v >= 0x1F3FB && v <= 0x1F3FF) || u.properties.generalCategory == .nonspacingMark { continue }
      if u.properties.isEmojiPresentation || (v >= 0x1F300 && v <= 0x1FAFF) || (v >= 0x1100 && u.properties.isIdeographic) || (v >= 0x3000 && v <= 0x9FFF) || (v >= 0xAC00 && v <= 0xD7AF) || (v >= 0xFF00 && v <= 0xFF60) {
        w += 2
      } else {
        w += 1
      }
    }
    return w
  }
}

extension EditorViewController {
  struct TableContext {
    let block: Block
    var model: TableModel
    var row: Int
    var column: Int
    /// Caret offset inside its cell, kept by commands that leave the cell where it is.
    let caretInCell: Int
  }

  /// The table at the caret with the caret's cell, or nil when the caret is not in a table.
  func tableAtCaret() -> TableContext? {
    let doc = document.markdown
    let ns = textView.string as NSString
    let sel = textView.selectedRange().location
    let b = doc.byteOffset(forUTF16: sel)
    guard let table = doc.path(at: b).first(where: { if case .table = $0.kind { return true }; return false }),
      let model = TableModel(block: table, in: doc, text: ns)
    else { return nil }
    let lines = TableModel.lines(of: table, in: doc, text: ns)
    guard let index = lines.firstIndex(where: { sel >= $0.range.location && sel < NSMaxRange($0.range) || (sel == NSMaxRange($0.range) && NSMaxRange($0.range) == ns.length) })
    else { return nil }
    let row = index <= 1 ? 0 : index - 1
    let line = lines[index]
    let inContent = max(0, sel - line.range.location - line.prefix.utf16.count)
    let column = min(TableModel.column(at: inContent, in: line.content), max(0, model.columns - 1))
    var caretInCell = 0
    if index != 1, row < model.rows.count, column < model.rows[row].count {
      // Distance from the cell's first non-space character.
      let cells = model.rows[row]
      var pipes = 0, i = 0, escaped = false
      let content = Array(line.content.utf16)
      if content.first == 0x7C { i = 1 }
      while i < content.count, pipes < column {
        if escaped { escaped = false } else if content[i] == 0x5C { escaped = true } else if content[i] == 0x7C { pipes += 1 }
        i += 1
      }
      while i < content.count, content[i] == 0x20 { i += 1 }
      caretInCell = max(0, min(cells[column].utf16.count, inContent - i))
    }
    return TableContext(block: table, model: model, row: min(row, model.rows.count - 1), column: column, caretInCell: caretInCell)
  }

  /// Applies `change` to the table at the caret and writes it back formatted, caret in the same
  /// logical cell. Nothing is written when the table would not change (`force` formats regardless).
  private func editTable(force: Bool = false, _ change: (inout TableContext) -> Void) {
    guard var context = tableAtCaret() else { NSSound.beep(); return }
    let before = context
    change(&context)
    if !force, context.model == before.model { NSSound.beep(); return }
    let ns = textView.string as NSString
    let lines = TableModel.lines(of: context.block, in: document.markdown, text: ns)
    guard let first = lines.first, let last = lines.last else { return }
    let start = first.range.location
    var end = NSMaxRange(last.range)
    if end > start, ns.character(at: end - 1) == 0x0A { end -= 1 }
    let (text, offsets) = context.model.render()
    if text == ns.substring(with: NSRange(location: start, length: end - start)) { return }
    textView.breakUndoCoalescing()
    textView.insertText(text, replacementRange: NSRange(location: start, length: end - start))
    textView.breakUndoCoalescing()
    let r = max(0, min(offsets.count - 1, context.row))
    let c = max(0, min(offsets[r].count - 1, context.column))
    let sameCell = r == before.row && c == before.column && context.model.rows[r][c] == before.model.rows[before.row][before.column]
    let inCell = sameCell ? min(before.caretInCell, context.model.rows[r][c].utf16.count) : 0
    textView.setSelectedRange(NSRange(location: start + offsets[r][c] + inCell, length: 0))
  }

  @IBAction func formatTable(_ sender: Any?) { editTable(force: true) { _ in } }
  @IBAction func addRowAbove(_ sender: Any?) { editTable { $0.model.insertRow(at: max(1, $0.row)); $0.row = max(1, $0.row) } }
  @IBAction func addRowBelow(_ sender: Any?) { editTable { $0.model.insertRow(at: $0.row + 1); $0.row += 1 } }
  @IBAction func addColumnBefore(_ sender: Any?) { editTable { $0.model.insertColumn(at: $0.column) } }
  @IBAction func addColumnAfter(_ sender: Any?) { editTable { $0.model.insertColumn(at: $0.column + 1); $0.column += 1 } }
  @IBAction func deleteRow(_ sender: Any?) { editTable { $0.model.removeRow(at: $0.row); $0.row = min($0.row, $0.model.rows.count - 1) } }
  @IBAction func deleteColumn(_ sender: Any?) { editTable { $0.model.removeColumn(at: $0.column); $0.column = min($0.column, $0.model.columns - 1) } }
  @IBAction func moveRowUp(_ sender: Any?) { editTable { if $0.row > 1 { $0.model.moveRow($0.row, by: -1); $0.row -= 1 } } }
  @IBAction func moveRowDown(_ sender: Any?) { editTable { if $0.row >= 1, $0.row + 1 < $0.model.rows.count { $0.model.moveRow($0.row, by: 1); $0.row += 1 } } }
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

  /// Tab from the last cell of the last row: a new row below, caret in its first cell.
  func appendTableRow() -> Bool {
    guard let context = tableAtCaret() else { return false }
    var changed = context
    changed.model.insertRow(at: changed.model.rows.count)
    changed.row = changed.model.rows.count - 1
    changed.column = 0
    editTable { $0 = changed }
    return true
  }

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
      insertTable(rows: max(1, min(100, rows.integerValue)), columns: max(1, min(50, columns.integerValue)))
      textView.window?.makeFirstResponder(textView)
    }
  }

  func insertTable(rows: Int, columns: Int) {
    let model = TableModel(rows: rows, columns: columns)
    let (text, offsets) = model.render()
    insertBlockText(text)
    let start = textView.selectedRange().location - text.utf16.count
    textView.setSelectedRange(NSRange(location: start + (offsets.first?.first ?? 0), length: 0))
  }
}
