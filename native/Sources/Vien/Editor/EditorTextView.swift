import AppKit
import VienMarkdown

/// The editor surface: a TextKit 2 text view with Markdown-aware keyboard behaviour. The text you
/// see is the file's text; nothing is rewritten behind your back.
final class EditorTextView: NSTextView {
  unowned var document: MarkdownFile!
  var preferences: Preferences { .shared }

  var contentWidth: CGFloat = 700 {
    didSet { needsLayoutInsets = true; needsLayout = true }
  }
  private var needsLayoutInsets = true

  override var acceptsFirstResponder: Bool { true }

  func configure() {
    isRichText = false
    importsGraphics = false
    allowsUndo = true
    usesFindBar = true
    isIncrementalSearchingEnabled = true
    isAutomaticQuoteSubstitutionEnabled = false
    isAutomaticDashSubstitutionEnabled = false
    isAutomaticTextReplacementEnabled = false
    isAutomaticSpellingCorrectionEnabled = false
    isAutomaticLinkDetectionEnabled = false
    isContinuousSpellCheckingEnabled = true
    isGrammarCheckingEnabled = false
    smartInsertDeleteEnabled = false
    usesFontPanel = false
    usesInspectorBar = false
    isVerticallyResizable = true
    isHorizontallyResizable = false
    minSize = NSSize(width: 0, height: 0)
    maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    autoresizingMask = [.width]
    textContainer?.widthTracksTextView = true
    textContainer?.lineFragmentPadding = 0
    drawsBackground = true
    backgroundColor = Theme.background
    insertionPointColor = Theme.accent
    typingAttributes = [.font: Theme().body(), .foregroundColor: Theme.text]
  }

  override func layout() {
    updateInsets()
    super.layout()
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    updateInsets()
  }

  private func updateInsets() {
    guard let scroll = enclosingScrollView else { return }
    let available = scroll.contentSize.width
    guard available > 80 else { return }
    if abs(frame.width - available) > 0.5 { frame.size.width = available }
    let width = min(contentWidth, available - 40)
    let side = max(20, ((available - width) / 2).rounded(.down))
    let vertical: CGFloat = preferences.typewriter ? max(120, scroll.contentSize.height * 0.45) : 48
    let inset = NSSize(width: side, height: vertical)
    if textContainerInset != inset || textContainer?.size.width != width {
      trace("textview: container width \(Int(width)) inset \(Int(side)) (available \(Int(available)))")
      textContainerInset = inset
      textContainer?.widthTracksTextView = false
      textContainer?.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
    }
  }

  // MARK: - Model helpers

  var doc: MarkdownDocument { document.markdown }

  /// Byte offset of a UTF-16 location.
  func byte(_ utf16: Int) -> Int { doc.byteOffset(forUTF16: utf16) }
  func utf16(_ byte: Int) -> Int { doc.utf16Offset(forByte: byte) }

  /// The line (as an NSRange of the text storage) containing `location`.
  func lineRange(at location: Int) -> NSRange {
    (string as NSString).lineRange(for: NSRange(location: location, length: 0))
  }

  func lineText(_ range: NSRange) -> String {
    var r = range
    let ns = string as NSString
    while r.length > 0, ["\n", "\r"].contains(ns.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1))) { r.length -= 1 }
    return ns.substring(with: r)
  }

  /// Re-creates and re-lays out the paragraphs covering `range` (attributes-only edit trick).
  func invalidateParagraphs(in range: NSRange) {
    guard let storage = textStorage else { return }
    let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
    guard clamped.length > 0 || storage.length == 0 else { return }
    storage.beginEditing()
    storage.edited(.editedAttributes, range: clamped, changeInLength: 0)
    storage.endEditing()
    needsDisplay = true
  }

  func invalidateAll() {
    invalidateParagraphs(in: NSRange(location: 0, length: textStorage?.length ?? 0))
  }

  /// Runs `body` (typically a whole-document invalidation, which rebuilds TextKit's layout from
  /// estimates) and then scrolls so the paragraph at the top of the window stays where it was.
  /// Never enumerates beyond the viewport: TextKit caches every element it is asked for.
  func keepingViewport(_ body: () -> Void) {
    guard let lm = textLayoutManager, let cs = lm.textContentManager as? NSTextContentStorage,
      let viewport = lm.textViewportLayoutController.viewportRange
    else { body(); return }
    let top = visibleRect.minY - textContainerInset.height
    var anchor: Int? = nil
    var offset: CGFloat = 0
    lm.enumerateTextLayoutFragments(from: viewport.location, options: [.ensuresLayout]) { fragment in
      if fragment.layoutFragmentFrame.maxY <= top { return true }
      anchor = cs.offset(from: cs.documentRange.location, to: fragment.rangeInElement.location)
      offset = fragment.layoutFragmentFrame.minY - top
      return false
    }
    body()
    guard let anchor, let location = cs.location(cs.documentRange.location, offsetBy: anchor) else { return }
    lm.textViewportLayoutController.layoutViewport()
    lm.ensureLayout(for: NSTextRange(location: location))
    guard let fragment = lm.textLayoutFragment(for: location) else { return }
    scroll(NSPoint(x: 0, y: max(0, fragment.layoutFragmentFrame.minY - offset + textContainerInset.height)))
  }

  /// The standard menu, plus Table commands when the (moved) caret is inside a table.
  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = super.menu(for: event)
    if let editor = delegate as? EditorViewController, editor.tableAtCaret() != nil {
      let table = NSMenuItem(title: "Table", action: nil, keyEquivalent: "")
      table.submenu = NSMenu(title: "Table")
      for item in MainMenu.tableItems() { table.submenu?.addItem(item) }
      menu?.insertItem(table, at: 0)
      menu?.insertItem(.separator(), at: 1)
    }
    return menu
  }

  // MARK: - Keyboard behaviour

  override func insertNewline(_ sender: Any?) {
    let sel = selectedRange()
    guard sel.length == 0 else { super.insertNewline(sender); return }
    let line = lineRange(at: sel.location)
    let text = lineText(line)
    let caretInLine = sel.location - line.location
    let before = String(text.utf16.prefix(caretInLine))!
    // Continue lists, quotes and task items; a marker alone on the line ends the list instead.
    if let m = ListMarker.parse(before) {
      let onlyMarker = before.trimmingCharacters(in: .whitespaces).isEmpty == false && before.count == m.length && text.count == m.length
      if onlyMarker || text.trimmingCharacters(in: .whitespaces) == m.markerText.trimmingCharacters(in: .whitespaces) {
        // Remove the marker: the user pressed Enter on an empty item.
        insertText("", replacementRange: line.length > 0 ? NSRange(location: line.location, length: min(line.length, m.length)) : line)
        return
      }
      insertText("\n" + m.next(), replacementRange: sel)
      return
    }
    if let q = QuotePrefix.parse(before) {
      if text.trimmingCharacters(in: .whitespaces) == ">" {
        insertText("", replacementRange: NSRange(location: line.location, length: min(line.length, q.count)))
        return
      }
      insertText("\n" + q, replacementRange: sel)
      return
    }
    // Inside a code block or after an opening bracket, keep the indentation.
    let indent = String(text.prefix(while: { $0 == " " || $0 == "\t" }))
    let pairOpen = before.hasSuffix("{") || before.hasSuffix("[") || before.hasSuffix("(")
    let after = String(text.utf16.dropFirst(caretInLine)) ?? ""
    let pairClose = after.hasPrefix("}") || after.hasPrefix("]") || after.hasPrefix(")")
    if pairOpen && pairClose {
      let unit = String(repeating: " ", count: preferences.tabSize)
      insertText("\n" + indent + unit + "\n" + indent, replacementRange: sel)
      setSelectedRange(NSRange(location: sel.location + 1 + indent.utf16.count + unit.count, length: 0))
      return
    }
    if !indent.isEmpty {
      insertText("\n" + indent, replacementRange: sel)
      return
    }
    super.insertNewline(sender)
  }

  override func insertTab(_ sender: Any?) {
    let sel = selectedRange()
    let line = lineRange(at: sel.location)
    let text = lineText(line)
    // Table row: jump to the next cell.
    if text.contains("|"), let next = nextCellRange(in: line, after: sel.location) {
      setSelectedRange(next)
      return
    }
    // List item: indent the whole item line(s).
    if ListMarker.parse(text) != nil || sel.length > 0 {
      indentSelectedLines(by: preferences.tabSize)
      return
    }
    insertText(String(repeating: " ", count: preferences.tabSize), replacementRange: sel)
  }

  override func insertBacktab(_ sender: Any?) {
    let sel = selectedRange()
    let line = lineRange(at: sel.location)
    let text = lineText(line)
    if text.contains("|"), let prev = previousCellRange(in: line, before: sel.location) {
      setSelectedRange(prev)
      return
    }
    indentSelectedLines(by: -preferences.tabSize)
  }

  override func deleteBackward(_ sender: Any?) {
    let sel = selectedRange()
    if sel.length == 0, sel.location > 0 {
      let ns = string as NSString
      // Delete a whole auto-inserted pair.
      if sel.location < ns.length {
        let left = ns.substring(with: NSRange(location: sel.location - 1, length: 1))
        let right = ns.substring(with: NSRange(location: sel.location, length: 1))
        if AutoPair.closing(for: left) == right, AutoPair.isEnabled(left, preferences) {
          insertText("", replacementRange: NSRange(location: sel.location - 1, length: 2))
          return
        }
      }
      // Backspace right after a list marker removes the marker.
      let line = lineRange(at: sel.location)
      let before = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
      if let m = ListMarker.parse(before), before.count == m.length {
        insertText("", replacementRange: NSRange(location: line.location, length: before.utf16.count))
        return
      }
    }
    super.deleteBackward(sender)
  }

  override func insertText(_ string: Any, replacementRange: NSRange) {
    guard let typed = string as? String, typed.count == 1, replacementRange.location == NSNotFound || replacementRange.length == 0 else {
      super.insertText(string, replacementRange: replacementRange)
      return
    }
    let sel = selectedRange()
    let ns = self.string as NSString
    // Wrap a selection with a Markdown pair.
    if sel.length > 0, AutoPair.isEnabled(typed, preferences), let close = AutoPair.closing(for: typed), typed != close || AutoPair.isMarkdown(typed) {
      let inner = ns.substring(with: sel)
      super.insertText(typed + inner + close, replacementRange: sel)
      setSelectedRange(NSRange(location: sel.location + 1, length: inner.utf16.count))
      return
    }
    // Step over an existing closing character.
    if sel.length == 0, sel.location < ns.length, AutoPair.isClosing(typed), ns.substring(with: NSRange(location: sel.location, length: 1)) == typed,
      AutoPair.isEnabled(typed, preferences)
    {
      // Only step over when the matching opener precedes it on this line.
      let line = lineRange(at: sel.location)
      let before = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
      if let open = AutoPair.opening(for: typed), before.contains(open) {
        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        return
      }
    }
    // Insert a pair.
    if sel.length == 0, AutoPair.isEnabled(typed, preferences), let close = AutoPair.closing(for: typed) {
      let next: String = sel.location < ns.length ? ns.substring(with: NSRange(location: sel.location, length: 1)) : ""
      let prev: String = sel.location > 0 ? ns.substring(with: NSRange(location: sel.location - 1, length: 1)) : ""
      let nextOK = next.isEmpty || next == " " || next == "\n" || AutoPair.isClosing(next) || next == "\r"
      let prevOK = !AutoPair.isMarkdown(typed) || prev.isEmpty || !(prev.first?.isLetter ?? false) && !(prev.first?.isNumber ?? false)
      if nextOK, prevOK {
        super.insertText(typed + close, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        return
      }
    }
    super.insertText(string, replacementRange: replacementRange)
  }

  // MARK: - Line operations

  /// Applies `transform` to every line touched by the selection in one undoable edit.
  func transformSelectedLines(_ transform: (String) -> String) {
    let sel = selectedRange()
    let ns = string as NSString
    let lines = ns.lineRange(for: sel)
    let block = ns.substring(with: lines)
    var pieces = block.components(separatedBy: "\n")
    let trailingNewline = block.hasSuffix("\n")
    if trailingNewline { pieces.removeLast() }
    let out = pieces.map(transform).joined(separator: "\n") + (trailingNewline ? "\n" : "")
    guard out != block else { return }
    insertText(out, replacementRange: lines)
    let delta = out.utf16.count - block.utf16.count
    if sel.length == 0 {
      // A caret stays a caret, moved by the change on its own line (or clamped to that line).
      let firstNew = pieces.first.map(transform) ?? ""
      let firstOld = pieces.first ?? ""
      let shift = firstNew.utf16.count - firstOld.utf16.count
      let caret = pieces.count == 1 ? sel.location + shift : sel.location + shift
      setSelectedRange(NSRange(location: max(lines.location, min(caret, lines.location + out.utf16.count)), length: 0))
    } else {
      setSelectedRange(NSRange(location: lines.location, length: max(0, lines.length + delta - (trailingNewline ? 1 : 0))))
    }
  }

  func indentSelectedLines(by amount: Int) {
    transformSelectedLines { line in
      if amount > 0 { return String(repeating: " ", count: amount) + line }
      var l = Substring(line)
      var n = -amount
      while n > 0, l.first == " " { l = l.dropFirst(); n -= 1 }
      if l.first == "\t" { l = l.dropFirst() }
      return String(l)
    }
  }

  private func nextCellRange(in line: NSRange, after location: Int) -> NSRange? {
    let ns = string as NSString
    var i = location
    let end = NSMaxRange(lineRange(at: location)) - (lineText(line).utf16.count < line.length ? 1 : 0)
    while i < end {
      if ns.substring(with: NSRange(location: i, length: 1)) == "|" {
        var s = i + 1
        while s < end, ns.substring(with: NSRange(location: s, length: 1)) == " " { s += 1 }
        var e = s
        while e < end, ns.substring(with: NSRange(location: e, length: 1)) != "|" { e += 1 }
        while e > s, ns.substring(with: NSRange(location: e - 1, length: 1)) == " " { e -= 1 }
        if s >= end { break }
        return NSRange(location: s, length: e - s)
      }
      i += 1
    }
    // Last cell: continue on the next row if it exists.
    let nextLineStart = NSMaxRange(lineRange(at: location))
    if nextLineStart < ns.length {
      let next = lineRange(at: nextLineStart)
      if lineText(next).contains("|") { return nextCellRange(in: next, after: next.location) }
    }
    return nil
  }

  private func previousCellRange(in line: NSRange, before location: Int) -> NSRange? {
    let ns = string as NSString
    var i = location - 1
    var pipes = 0
    while i >= line.location {
      if ns.substring(with: NSRange(location: i, length: 1)) == "|" {
        pipes += 1
        if pipes == 2 || (i == line.location) {
          var s = i + 1
          let e0 = (0..<location).reversed().first(where: { ns.substring(with: NSRange(location: $0, length: 1)) == "|" }) ?? location
          while s < e0, ns.substring(with: NSRange(location: s, length: 1)) == " " { s += 1 }
          var e = e0
          while e > s, ns.substring(with: NSRange(location: e - 1, length: 1)) == " " { e -= 1 }
          return NSRange(location: s, length: max(0, e - s))
        }
      }
      i -= 1
    }
    return nil
  }

  // MARK: - Links

  override func clicked(onLink link: Any, at charIndex: Int) {
    if let url = link as? URL { NSWorkspace.shared.open(url) }
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let index = characterIndexForInsertion(at: point)
    if event.clickCount == 1, !event.modifierFlags.contains(.shift), toggleTask(at: index) { return }
    if event.modifierFlags.contains(.command) {
      if let url = linkURL(at: index) {
        if url.isFileURL, url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown" {
          NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
          NSWorkspace.shared.open(url)
        }
        return
      }
    }
    super.mouseDown(with: event)
  }

  /// URL of the link/autolink/image under a character index, if any.
  func linkURL(at index: Int) -> URL? {
    let b = byte(index)
    guard let leaf = doc.path(at: b).last else { return nil }
    switch leaf.kind {
    case .paragraph, .heading, .tableCell: break
    default: return nil
    }
    func find(_ nodes: [Inline]) -> URL? {
      for n in nodes where n.range.contains(b) {
        switch n.kind {
        case .link(let d, _), .image(let d, _): return document.resolveImageURL(d)
        case .autolink(let u, _), .extendedAutolink(let u, _): return URL(string: u)
        default: if let c = find(n.children) { return c }
        }
      }
      return nil
    }
    return find(doc.inlines(of: leaf))
  }
}

// MARK: - Small syntax helpers

struct ListMarker {
  var indent: String
  var markerText: String  // e.g. "- ", "1. ", "- [ ] "
  var number: Int?
  var delimiter: String
  var task: Bool
  var length: Int { indent.count + markerText.count }

  static func parse(_ line: String) -> ListMarker? {
    let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    var rest = Substring(line.dropFirst(indent.count))
    var number: Int? = nil
    var delimiter = ""
    var marker = ""
    if let c = rest.first, "-+*".contains(c), rest.dropFirst().first == " " {
      marker = String(c) + " "
      rest = rest.dropFirst(2)
    } else {
      let digits = rest.prefix(while: { $0.isNumber })
      if !digits.isEmpty, digits.count <= 9, let n = Int(digits) {
        let after = rest.dropFirst(digits.count)
        if let d = after.first, d == "." || d == ")", after.dropFirst().first == " " {
          number = n
          delimiter = String(d)
          marker = digits + delimiter + " "
          rest = after.dropFirst(2)
        }
      }
    }
    guard !marker.isEmpty else { return nil }
    var task = false
    if rest.hasPrefix("[ ] ") || rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") {
      task = true
      marker += "[ ] "
    }
    return ListMarker(indent: indent, markerText: marker, number: number, delimiter: delimiter, task: task)
  }

  /// Marker for the following item.
  func next() -> String {
    if let n = number { return indent + "\(n + 1)\(delimiter) " + (task ? "[ ] " : "") }
    return indent + markerText
  }
}

enum QuotePrefix {
  /// Returns the `> ` prefix (with indentation) when the text before the caret starts a quote line.
  static func parse(_ before: String) -> String? {
    let indent = before.prefix(while: { $0 == " " })
    guard indent.count <= 3 else { return nil }
    var rest = before.dropFirst(indent.count)
    var prefix = String(indent)
    var any = false
    while rest.first == ">" {
      any = true
      prefix += ">"
      rest = rest.dropFirst()
      if rest.first == " " { prefix += " "; rest = rest.dropFirst() }
    }
    return any ? prefix : nil
  }
}

enum AutoPair {
  static let brackets: [String: String] = ["(": ")", "[": "]", "{": "}"]
  static let quotes: [String: String] = ["\"": "\""]
  static let markdown: [String: String] = ["*": "*", "_": "_", "`": "`", "$": "$", "~": "~"]

  static func closing(for open: String) -> String? { brackets[open] ?? quotes[open] ?? markdown[open] }
  static func opening(for close: String) -> String? {
    for (k, v) in brackets where v == close { return k }
    if quotes[close] != nil || markdown[close] != nil { return close }
    return nil
  }
  static func isClosing(_ s: String) -> Bool { brackets.values.contains(s) || quotes[s] != nil || markdown[s] != nil }
  static func isMarkdown(_ s: String) -> Bool { markdown[s] != nil }
  static func isEnabled(_ s: String, _ p: Preferences) -> Bool {
    if brackets[s] != nil || brackets.values.contains(s) { return p.autoPairBrackets }
    if quotes[s] != nil { return p.autoPairQuotes }
    if markdown[s] != nil { return p.autoPairMarkdown }
    return false
  }
}
