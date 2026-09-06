import AppKit
import UniformTypeIdentifiers
import VienMarkdown

/// Menu commands. Every command is a plain text edit on the source, so undo, autosave and the parser
/// all see one ordinary change.
extension EditorViewController {
  // MARK: Inline formats

  @IBAction func toggleBold(_ sender: Any?) { wrapSelection("**") }
  @IBAction func toggleItalic(_ sender: Any?) { wrapSelection("*") }
  @IBAction func toggleStrikethrough(_ sender: Any?) { wrapSelection("~~") }
  @IBAction func toggleInlineCode(_ sender: Any?) { wrapSelection("`") }
  @IBAction func toggleInlineMath(_ sender: Any?) { wrapSelection("$") }
  @IBAction func toggleUnderline(_ sender: Any?) { wrapSelection("<u>", "</u>") }
  @IBAction func toggleHighlight(_ sender: Any?) { wrapSelection("<mark>", "</mark>") }
  @IBAction func toggleSuperscript(_ sender: Any?) { wrapSelection(Preferences.shared.superSubScript ? "^" : "<sup>", Preferences.shared.superSubScript ? "^" : "</sup>") }
  @IBAction func toggleSubscript(_ sender: Any?) { wrapSelection(Preferences.shared.superSubScript ? "~" : "<sub>", Preferences.shared.superSubScript ? "~" : "</sub>") }

  @IBAction func insertLink(_ sender: Any?) {
    let sel = textView.selectedRange()
    let ns = textView.string as NSString
    let text = ns.substring(with: sel)
    let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
    let url = clipboard.hasPrefix("http") || clipboard.hasPrefix("www.") ? clipboard : ""
    if text.isEmpty {
      textView.insertText("[](\(url))", replacementRange: sel)
      textView.setSelectedRange(NSRange(location: sel.location + 1, length: 0))
    } else {
      textView.insertText("[\(text)](\(url))", replacementRange: sel)
      let start = sel.location + text.utf16.count + 3
      textView.setSelectedRange(NSRange(location: start, length: url.utf16.count))
    }
  }

  @IBAction func insertImage(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.canChooseDirectories = false
    guard let window = view.window else { return }
    panel.beginSheetModal(for: window) { [self] response in
      guard response == .OK, let url = panel.url else { return }
      let path = document.relativeImagePath(for: url)
      let sel = textView.selectedRange()
      let alt = url.deletingPathExtension().lastPathComponent
      textView.insertText("![\(alt)](\(path))", replacementRange: sel)
    }
  }

  @IBAction func clearFormatting(_ sender: Any?) {
    let sel = textView.selectedRange()
    guard sel.length > 0 else { return }
    let ns = textView.string as NSString
    var text = ns.substring(with: sel)
    for marker in ["**", "__", "~~", "*", "_", "`", "$", "<u>", "</u>", "<mark>", "</mark>", "<sup>", "</sup>", "<sub>", "</sub>", "=="] {
      text = text.replacingOccurrences(of: marker, with: "")
    }
    textView.insertText(text, replacementRange: sel)
    textView.setSelectedRange(NSRange(location: sel.location, length: text.utf16.count))
  }

  /// Wraps the selection (or the word at the caret) with `open`…`close`; unwraps when already wrapped.
  func wrapSelection(_ open: String, _ closeMarker: String? = nil) {
    let close = closeMarker ?? open
    var sel = textView.selectedRange()
    let ns = textView.string as NSString
    if sel.length == 0 {
      // Extend to the word under the caret.
      let word = wordRange(at: sel.location)
      if word.length > 0 { sel = word }
    }
    let text = ns.substring(with: sel)
    // Unwrap if the selection already carries the markers (inside or around).
    if text.hasPrefix(open), text.hasSuffix(close), text.utf16.count >= open.utf16.count + close.utf16.count {
      let inner = String(text.dropFirst(open.count).dropLast(close.count))
      textView.insertText(inner, replacementRange: sel)
      textView.setSelectedRange(NSRange(location: sel.location, length: inner.utf16.count))
      return
    }
    let before = sel.location - open.utf16.count, after = NSMaxRange(sel) + close.utf16.count
    if before >= 0, after <= ns.length, ns.substring(with: NSRange(location: before, length: open.utf16.count)) == open,
      ns.substring(with: NSRange(location: NSMaxRange(sel), length: close.utf16.count)) == close
    {
      textView.insertText(text, replacementRange: NSRange(location: before, length: after - before))
      textView.setSelectedRange(NSRange(location: before, length: text.utf16.count))
      return
    }
    textView.insertText(open + text + close, replacementRange: sel)
    textView.setSelectedRange(NSRange(location: sel.location + open.utf16.count, length: text.utf16.count))
  }

  private func wordRange(at location: Int) -> NSRange {
    let ns = textView.string as NSString
    guard ns.length > 0 else { return NSRange(location: location, length: 0) }
    let letters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    var s = location, e = location
    func ch(_ i: Int) -> Character? { i >= 0 && i < ns.length ? Character(ns.substring(with: NSRange(location: i, length: 1))) : nil }
    while let c = ch(s - 1), c.unicodeScalars.allSatisfy({ letters.contains($0) }) { s -= 1 }
    while let c = ch(e), c.unicodeScalars.allSatisfy({ letters.contains($0) }) { e += 1 }
    return NSRange(location: s, length: e - s)
  }

  // MARK: Paragraph types

  @IBAction func setHeading1(_ sender: Any?) { setHeading(1) }
  @IBAction func setHeading2(_ sender: Any?) { setHeading(2) }
  @IBAction func setHeading3(_ sender: Any?) { setHeading(3) }
  @IBAction func setHeading4(_ sender: Any?) { setHeading(4) }
  @IBAction func setHeading5(_ sender: Any?) { setHeading(5) }
  @IBAction func setHeading6(_ sender: Any?) { setHeading(6) }
  @IBAction func setParagraph(_ sender: Any?) { setHeading(0) }

  @IBAction func promoteHeading(_ sender: Any?) {
    let level = currentHeadingLevel()
    setHeading(level == 0 ? 6 : max(1, level - 1))
  }

  @IBAction func demoteHeading(_ sender: Any?) {
    let level = currentHeadingLevel()
    setHeading(level == 0 ? 1 : (level >= 6 ? 0 : level + 1))
  }

  private func currentHeadingLevel() -> Int {
    let line = textView.lineText(textView.lineRange(at: textView.selectedRange().location))
    let hashes = line.drop(while: { $0 == " " }).prefix(while: { $0 == "#" })
    return hashes.count <= 6 && (line.drop(while: { $0 == " " }).dropFirst(hashes.count).first == " " || hashes.count == line.count) ? hashes.count : 0
  }

  func setHeading(_ level: Int) {
    textView.transformSelectedLines { line in
      var body = Substring(line)
      body = body.drop(while: { $0 == " " })
      let hashes = body.prefix(while: { $0 == "#" })
      if hashes.count >= 1, hashes.count <= 6, body.dropFirst(hashes.count).first == " " || body.count == hashes.count {
        body = body.dropFirst(hashes.count).drop(while: { $0 == " " })
      }
      // Drop a trailing closing sequence of hashes.
      var text = String(body)
      while text.hasSuffix("#") { text.removeLast() }
      text = text.trimmingCharacters(in: .whitespaces)
      return level == 0 ? text : String(repeating: "#", count: level) + " " + text
    }
  }

  @IBAction func toggleBulletList(_ sender: Any?) { toggleList(ordered: false, task: false) }
  @IBAction func toggleOrderedList(_ sender: Any?) { toggleList(ordered: true, task: false) }
  @IBAction func toggleTaskList(_ sender: Any?) { toggleList(ordered: false, task: true) }

  private func toggleList(ordered: Bool, task: Bool) {
    var n = 0
    let marker = Preferences.shared.bulletMarker
    let delimiter = Preferences.shared.orderedDelimiter
    var allAlready = true
    textView.transformSelectedLines { line in
      if let m = ListMarker.parse(line) {
        let same = (ordered == (m.number != nil)) && (task == m.task)
        if !same { allAlready = false }
      } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
        allAlready = false
      }
      return line
    }
    textView.transformSelectedLines { line in
      var body = Substring(line)
      var indent = ""
      if let m = ListMarker.parse(line) {
        indent = m.indent
        body = body.dropFirst(m.length)
      } else {
        indent = String(line.prefix(while: { $0 == " " }))
        body = body.dropFirst(indent.count)
      }
      if allAlready { return indent + body }
      if body.trimmingCharacters(in: .whitespaces).isEmpty, line.isEmpty { return line }
      n += 1
      let prefix = ordered ? "\(n)\(delimiter) " : "\(marker) "
      return indent + prefix + (task ? "[ ] " : "") + body
    }
  }

  @IBAction func toggleLooseList(_ sender: Any?) {
    // Insert or remove blank lines between the items of the current list.
    let sel = textView.selectedRange()
    let b = document.markdown.byteOffset(forUTF16: sel.location)
    guard let list = document.markdown.path(at: b).last(where: { if case .list = $0.kind { return true }; return false }),
      case .list(let info) = list.kind
    else { return }
    let ns = textView.string as NSString
    let lo = document.markdown.utf16Offset(forByte: list.range.lowerBound)
    let hi = document.markdown.utf16Offset(forByte: list.range.upperBound)
    let range = NSRange(location: lo, length: hi - lo)
    let text = ns.substring(with: range)
    var out: String
    if info.tight {
      var lines: [String] = []
      for (i, l) in text.components(separatedBy: "\n").enumerated() {
        if i > 0, ListMarker.parse(l) != nil, ListMarker.parse(l)!.indent.isEmpty || true { lines.append("") }
        lines.append(l)
      }
      out = lines.joined(separator: "\n")
    } else {
      out = text.replacingOccurrences(of: "\n\n", with: "\n")
    }
    textView.insertText(out, replacementRange: range)
    textView.setSelectedRange(NSRange(location: lo, length: out.utf16.count))
  }

  @IBAction func toggleBlockQuote(_ sender: Any?) {
    var all = true
    textView.transformSelectedLines { line in
      if !line.trimmingCharacters(in: .whitespaces).isEmpty, QuotePrefix.parse(line) == nil { all = false }
      return line
    }
    textView.transformSelectedLines { line in
      if all {
        if let q = QuotePrefix.parse(line) { return String(line.dropFirst(q.count)) }
        return line
      }
      return line.isEmpty ? ">" : "> " + line
    }
  }

  @IBAction func insertCodeFence(_ sender: Any?) { wrapBlock("```", "```", placeholder: "") }
  @IBAction func insertMathBlock(_ sender: Any?) { wrapBlock("$$", "$$", placeholder: "") }
  @IBAction func insertHTMLBlock(_ sender: Any?) { wrapBlock("<div>", "</div>", placeholder: "") }

  private func wrapBlock(_ open: String, _ close: String, placeholder: String) {
    let sel = textView.selectedRange()
    let ns = textView.string as NSString
    let lines = ns.lineRange(for: sel)
    var body = ns.substring(with: lines)
    if body.hasSuffix("\n") { body.removeLast() }
    let needsLeadingNewline = lines.location > 0 && !body.isEmpty && false
    let text = (needsLeadingNewline ? "\n" : "") + open + "\n" + body + (body.isEmpty ? "" : "\n") + close + "\n"
    textView.insertText(text, replacementRange: lines)
    // Put the caret on the first content line.
    textView.setSelectedRange(NSRange(location: lines.location + open.utf16.count + 1, length: body.utf16.count))
  }

  @IBAction func insertHorizontalRule(_ sender: Any?) { insertBlockText("---") }


  @IBAction func insertFrontMatter(_ sender: Any?) {
    guard !textView.string.hasPrefix("---\n") else { return }
    let fence = Preferences.shared.frontMatterKind
    let body = fence == "---" ? "title: " : fence == "+++" ? "title = \"\"" : "\"title\": \"\""
    textView.insertText("\(fence)\n\(body)\n\(fence)\n\n", replacementRange: NSRange(location: 0, length: 0))
    textView.setSelectedRange(NSRange(location: fence.utf16.count + 1 + body.utf16.count, length: 0))
  }

  /// Inserts `text` as its own block at the caret, surrounded by blank lines as needed.
  func insertBlockText(_ text: String) {
    var sel = textView.selectedRange()
    let ns = textView.string as NSString
    // Inside a table the new block goes after the table, never between its rows.
    if let context = tableAtCaret(), let last = TableModel.lines(of: context.block, in: document.markdown, text: ns).last {
      sel = NSRange(location: max(last.range.location, NSMaxRange(last.range) - 1), length: 0)
    }
    let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
    let current = textView.lineText(line)
    var insertion = text + "\n"
    var at = line.location
    if !current.isEmpty {
      // Insert after the current line.
      at = NSMaxRange(line)
      if at == ns.length, !ns.hasSuffix("\n") { insertion = "\n\n" + text + "\n" } else { insertion = "\n" + text + "\n" }
    }
    textView.insertText(insertion, replacementRange: NSRange(location: at, length: 0))
    textView.setSelectedRange(NSRange(location: at + insertion.utf16.count - 1, length: 0))
  }

  // MARK: Block operations

  @IBAction func duplicateParagraph(_ sender: Any?) {
    guard let (range, text) = currentBlockText() else { return }
    let insertion = "\n\n" + text
    textView.insertText(insertion, replacementRange: NSRange(location: NSMaxRange(range), length: 0))
    textView.setSelectedRange(NSRange(location: NSMaxRange(range) + 2, length: text.utf16.count))
  }

  @IBAction func deleteParagraph(_ sender: Any?) {
    guard let (range, _) = currentBlockText() else { return }
    let ns = textView.string as NSString
    var r = range
    // Also remove the following blank line if present.
    while NSMaxRange(r) < ns.length, ns.substring(with: NSRange(location: NSMaxRange(r), length: 1)) == "\n" { r.length += 1 }
    textView.insertText("", replacementRange: r)
  }

  @IBAction func createParagraph(_ sender: Any?) {
    guard let (range, _) = currentBlockText() else {
      textView.insertText("\n\n", replacementRange: textView.selectedRange())
      return
    }
    textView.insertText("\n\n", replacementRange: NSRange(location: NSMaxRange(range), length: 0))
    textView.setSelectedRange(NSRange(location: NSMaxRange(range) + 2, length: 0))
  }

  /// UTF-16 range and text of the top-level block at the caret.
  private func currentBlockText() -> (NSRange, String)? {
    let sel = textView.selectedRange()
    let b = document.markdown.byteOffset(forUTF16: sel.location)
    guard let block = document.markdown.path(at: b).first else { return nil }
    let lo = document.markdown.utf16Offset(forByte: block.range.lowerBound)
    let hi = document.markdown.utf16Offset(forByte: block.range.upperBound)
    let range = NSRange(location: lo, length: hi - lo)
    return (range, (textView.string as NSString).substring(with: range))
  }

  // MARK: Clipboard

  @IBAction func copyAsHTML(_ sender: Any?) {
    let sel = textView.selectedRange()
    let text = sel.length > 0 ? (textView.string as NSString).substring(with: sel) : textView.string
    let html = HTMLRenderer.render(MarkdownDocument(text: text, options: MarkdownFile.parserOptions))
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(html, forType: .html)
    pb.setString(html, forType: .string)
  }

  @IBAction func copyAsMarkdown(_ sender: Any?) {
    let sel = textView.selectedRange()
    let text = sel.length > 0 ? (textView.string as NSString).substring(with: sel) : textView.string
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
  }


  // MARK: View

  @IBAction func zoomIn(_ sender: Any?) { setZoom(zoomLevel + 0.1) }
  @IBAction func zoomOut(_ sender: Any?) { setZoom(zoomLevel - 0.1) }
  @IBAction func zoomActualSize(_ sender: Any?) { setZoom(1) }
  @IBAction func toggleSourceMode(_ sender: Any?) { setSourceMode(!Preferences.shared.sourceMode) }
  @IBAction func toggleTypewriterMode(_ sender: Any?) { setTypewriter(!Preferences.shared.typewriter) }
  @IBAction func toggleFocusMode(_ sender: Any?) { setFocusMode(!Preferences.shared.focus) }
  @IBAction func reloadImages(_ sender: Any?) {
    OverlayStore.shared.clear()
    textView.invalidateAll()
  }

}

extension EditorViewController: NSMenuItemValidation {
  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(toggleSourceMode): item.state = Preferences.shared.sourceMode ? .on : .off
    case #selector(toggleTypewriterMode): item.state = Preferences.shared.typewriter ? .on : .off
    case #selector(toggleFocusMode): item.state = Preferences.shared.focus ? .on : .off
    case let action? where Self.tableActions.contains(action):
      guard let context = tableAtCaret() else { return false }
      let current = context.model.alignments[context.column]
      switch action {
      case #selector(alignColumnLeft(_:)): item.state = current == .left ? .on : .off
      case #selector(alignColumnCenter(_:)): item.state = current == .center ? .on : .off
      case #selector(alignColumnRight(_:)): item.state = current == .right ? .on : .off
      case #selector(alignColumnNone(_:)): item.state = current == .none ? .on : .off
      default: break
      }
    default: break
    }
    return true
  }
}

extension MarkdownFile {
  /// Path to write into `![]()` for a picked image, honouring the image-insertion preference.
  func relativeImagePath(for url: URL) -> String {
    let p = Preferences.shared
    guard let dir = fileURL?.deletingLastPathComponent() else { return url.path }
    var target = url
    if p.imageInsertAction == "copy" {
      let folder = dir.appendingPathComponent(p.imageFolderName)
      try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      var dest = folder.appendingPathComponent(url.lastPathComponent)
      var n = 1
      while FileManager.default.fileExists(atPath: dest.path), dest != url {
        dest = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "-\(n)." + url.pathExtension)
        n += 1
      }
      if dest != url { try? FileManager.default.copyItem(at: url, to: dest) }
      target = dest
    }
    let base = dir.standardizedFileURL.path + "/"
    let full = target.standardizedFileURL.path
    if full.hasPrefix(base) { return String(full.dropFirst(base.count)).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? full }
    return full
  }
}
