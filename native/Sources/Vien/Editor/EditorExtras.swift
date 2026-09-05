import AppKit
import UniformTypeIdentifiers
import VienMarkdown

/// Table formatting, image paste/drop and task toggling: small conveniences that keep the source
/// text tidy without ever rewriting anything the user did not ask for.
extension EditorViewController {
  /// Aligns the pipes of the table at the caret (⌥⇧⌘T).
  @IBAction func formatTable(_ sender: Any?) {
    let sel = textView.selectedRange()
    let doc = document.markdown
    let b = doc.byteOffset(forUTF16: sel.location)
    guard let table = doc.path(at: b).first(where: { if case .table = $0.kind { return true }; return false }), case .table(let info) = table.kind else {
      NSSound.beep()
      return
    }
    var rows: [[String]] = []
    for row in table.children {
      rows.append(row.children.map { doc.text(of: $0).trimmingCharacters(in: .whitespaces) })
    }
    let cols = info.alignments.count
    var widths = [Int](repeating: 3, count: cols)
    for r in rows { for (i, c) in r.enumerated() where i < cols { widths[i] = max(widths[i], displayWidth(c)) } }
    func pad(_ s: String, _ w: Int, _ a: TableAlignment) -> String {
      let extra = max(0, w - displayWidth(s))
      switch a {
      case .right: return String(repeating: " ", count: extra) + s
      case .center: return String(repeating: " ", count: extra / 2) + s + String(repeating: " ", count: extra - extra / 2)
      default: return s + String(repeating: " ", count: extra)
      }
    }
    var lines: [String] = []
    for (r, row) in rows.enumerated() {
      var cells = row
      while cells.count < cols { cells.append("") }
      lines.append("| " + cells.prefix(cols).enumerated().map { pad($1, widths[$0], info.alignments[$0]) }.joined(separator: " | ") + " |")
      if r == 0 {
        lines.append("| " + (0..<cols).map { i -> String in
          let w = widths[i]
          switch info.alignments[i] {
          case .left: return ":" + String(repeating: "-", count: w - 1)
          case .right: return String(repeating: "-", count: w - 1) + ":"
          case .center: return ":" + String(repeating: "-", count: max(1, w - 2)) + ":"
          case .none: return String(repeating: "-", count: w)
          }
        }.joined(separator: " | ") + " |")
      }
    }
    let lo = doc.utf16Offset(forByte: table.range.lowerBound), hi = doc.utf16Offset(forByte: table.range.upperBound)
    // Keep the table's own indentation on the first line.
    let lineStart = textView.lineRange(at: lo).location
    let indent = (textView.string as NSString).substring(with: NSRange(location: lineStart, length: lo - lineStart))
    let text = lines.map { indent + $0 }.joined(separator: "\n")
    textView.insertText(text, replacementRange: NSRange(location: lineStart, length: hi - lineStart))
    textView.setSelectedRange(NSRange(location: min(sel.location, lineStart + text.utf16.count), length: 0))
  }

  private func displayWidth(_ s: String) -> Int {
    s.unicodeScalars.reduce(0) { $0 + (($1.value >= 0x1100 && $1.properties.isIdeographic) || ($1.value >= 0x3000 && $1.value <= 0x9FFF) || ($1.value >= 0xAC00 && $1.value <= 0xD7AF) ? 2 : 1) }
  }
}

extension EditorTextView {
  // MARK: Images from the pasteboard or dropped files

  override func paste(_ sender: Any?) {
    let pb = NSPasteboard.general
    if pb.string(forType: .string) == nil, let image = NSImage(pasteboard: pb) {
      insertPastedImage(image)
      return
    }
    // Multiple files (from Finder): insert links/images for each.
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty, pb.string(forType: .string) == nil {
      insertFileReferences(urls)
      return
    }
    pasteAsPlainText(sender)
  }

  override func pasteAsPlainText(_ sender: Any?) {
    guard let s = NSPasteboard.general.string(forType: .string) else { return }
    insertText(s, replacementRange: selectedRange())
  }

  private func insertPastedImage(_ image: NSImage) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    let name = "image-\(stamp).png"
    guard let dir = document.fileURL?.deletingLastPathComponent() else {
      // Untitled documents have no folder yet: keep the image next to the autosave location later.
      let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
      try? png.write(to: tmp)
      insertText("![](\(tmp.path))", replacementRange: selectedRange())
      return
    }
    let folder = dir.appendingPathComponent(Preferences.shared.imageFolderName)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    do {
      try png.write(to: url)
      let rel = (Preferences.shared.imageFolderName + "/" + name).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
      insertText("![](\(rel))", replacementRange: selectedRange())
    } catch {
      NSSound.beep()
    }
  }

  private func insertFileReferences(_ urls: [URL]) {
    var pieces: [String] = []
    for url in urls {
      let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
      let path = document.relativeImagePath(for: url)
      pieces.append(isImage ? "![\(url.deletingPathExtension().lastPathComponent)](\(path))" : "[\(url.lastPathComponent)](\(path))")
    }
    insertText(pieces.joined(separator: "\n"), replacementRange: selectedRange())
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard
    if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
      let point = convert(sender.draggingLocation, from: nil)
      let index = characterIndexForInsertion(at: point)
      setSelectedRange(NSRange(location: index, length: 0))
      insertFileReferences(urls)
      return true
    }
    return super.performDragOperation(sender)
  }

  // MARK: Task checkboxes

  /// A click on `[ ]` / `[x]` toggles the task.
  func toggleTask(at index: Int) -> Bool {
    let b = byte(index)
    for block in doc.path(at: b) {
      if case .listItem(let info) = block.kind, let task = info.task, task.range.lowerBound <= b, b <= task.range.upperBound {
        let lo = utf16(task.range.lowerBound + 1)
        insertText(task.checked ? " " : "x", replacementRange: NSRange(location: lo, length: 1))
        return true
      }
    }
    return false
  }
}
