import AppKit
import UniformTypeIdentifiers
import VienMarkdown

/// Image paste/drop and task toggling: small conveniences that keep the source text tidy without
/// ever rewriting anything the user did not ask for.
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
