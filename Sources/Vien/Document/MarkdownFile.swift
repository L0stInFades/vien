import AppKit
import UniformTypeIdentifiers
import VienMarkdown

/// One Markdown file. NSDocument gives us autosave, versions, crash recovery, rename/move from the
/// title bar, external-change detection and atomic saves; this class only keeps the text and its
/// parsed structure.
final class MarkdownFile: NSDocument {
  /// The text view's backing store. Created here so it survives window re-creation.
  let storage = NSTextStorage()
  /// Parsed structure, kept in sync incrementally by `EditorViewController`.
  var markdown: MarkdownDocument
  var codec = TextCodec()
  var lineEnding: TextCodec.LineEnding = .lf
  /// Incremented on every text change; caches keyed on it are dropped automatically.
  var revision = 0

  override init() {
    markdown = MarkdownDocument(text: "", options: Self.parserOptions)
    super.init()
    lineEnding = TextCodec.LineEnding(rawValue: Preferences.shared.newDocumentLineEnding) ?? .lf
    codec.hasBOM = Preferences.shared.defaultEncodingUTF8BOM
  }

  static var parserOptions: ParserOptions {
    var o = ParserOptions()
    let p = Preferences.shared
    o.math = p.mathEnabled
    o.footnotes = p.footnotesEnabled
    o.superSubScript = p.superSubScript
    o.emoji = p.emojiEnabled
    return o
  }

  nonisolated static let markdownType = "net.daringfireball.markdown"
  nonisolated override class var readableTypes: [String] { [markdownType, "public.plain-text", "public.text"] }
  nonisolated override class var writableTypes: [String] { [markdownType, "public.plain-text"] }
  nonisolated override class func isNativeType(_ type: String) -> Bool { true }
  nonisolated override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] { [Self.markdownType] }
  nonisolated override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
    // A .txt or .markdown file keeps its extension through Save As, Duplicate and Rename.
    if let ext = fileURL?.pathExtension, !ext.isEmpty { return ext }
    return "md"
  }

  nonisolated override class var autosavesInPlace: Bool { true }
  nonisolated override class var usesUbiquitousStorage: Bool { false }
  nonisolated override var isEntireFileLoaded: Bool { true }

  nonisolated override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

  // MARK: - Reading and writing

  nonisolated override func read(from data: Data, ofType typeName: String) throws {
    guard let (text, codec) = TextCodec.decode(data) else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError)
    }
    // Reads happen on the main thread (concurrent reading is off).
    MainActor.assumeIsolated {
      trace("read: decoded \(text.utf8.count) bytes")
      self.codec = codec
      lineEnding = TextCodec.detectLineEnding(text) ?? (TextCodec.LineEnding(rawValue: Preferences.shared.newDocumentLineEnding) ?? .lf)
      setText(text)
      trace("read: parsed \(markdown.blocks.count) blocks")
    }
  }

  override func data(ofType typeName: String) throws -> Data {
    var text = storage.string
    let p = Preferences.shared
    if p.trimTrailingWhitespaceOnSave { text = Self.trimTrailingWhitespace(text) }
    if p.ensureFinalNewline, !text.isEmpty, !text.hasSuffix("\n"), !text.hasSuffix("\r") { text += lineEnding.rawValue }
    // The text view keeps what the user typed: the newline and trimming exist only in the file.
    guard let data = codec.encode(text) else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
        NSLocalizedDescriptionKey: "The document contains characters that cannot be saved in \(codecName)."
      ])
    }
    return data
  }

  var codecName: String {
    let name = String.localizedName(of: codec.encoding)
    return codec.hasBOM ? "\(name) with BOM" : name
  }

  /// Replaces the whole text (open, revert, line-ending conversion) and reparses from scratch.
  func setText(_ text: String, keepingSelection: Bool = false) {
    storage.beginEditing()
    storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
    storage.setAttributes([.font: Theme().body(), .foregroundColor: Theme.text], range: NSRange(location: 0, length: storage.length))
    storage.endEditing()
    markdown = MarkdownDocument(text: text, options: Self.parserOptions)
    revision += 1
  }

  override func makeWindowControllers() {
    addWindowController(DocumentWindowController())
  }

  override var displayName: String! {
    get { super.displayName }
    set { super.displayName = newValue }
  }

  // MARK: - File actions

  @IBAction func showInFinder(_ sender: Any?) {
    guard let url = fileURL else { NSSound.beep(); return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  @IBAction func copyPath(_ sender: Any?) {
    guard let url = fileURL else { NSSound.beep(); return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.path, forType: .string)
  }

  @IBAction func changeEncoding(_ sender: NSMenuItem) {
    switch sender.representedObject as? String {
    case "UTF-8": codec = TextCodec(encoding: .utf8, hasBOM: false)
    case "UTF-8 with BOM": codec = TextCodec(encoding: .utf8, hasBOM: true)
    case "UTF-16": codec = TextCodec(encoding: .utf16LittleEndian, hasBOM: true)
    default: return
    }
    updateChangeCount(.changeDone)
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if let menu = item as? NSMenuItem {
      if menu.action == #selector(changeEncoding(_:)) {
        let names: [String] = codec.encoding == .utf16LittleEndian ? ["UTF-16"] : codec.hasBOM ? ["UTF-8 with BOM"] : ["UTF-8"]
        menu.state = names.contains(menu.representedObject as? String ?? "") ? .on : .off
        return true
      }
      if menu.action == #selector(convertLineEndings(_:)) {
        menu.state = (menu.representedObject as? String) == lineEnding.rawValue ? .on : .off
        return true
      }
    }
    return super.validateUserInterfaceItem(item)
  }

  // MARK: - Line endings

  @objc func convertLineEndings(_ sender: NSMenuItem) {
    guard let ending = TextCodec.LineEnding.allCases.first(where: { $0.rawValue == (sender.representedObject as? String) }) else { return }
    lineEnding = ending
    let converted = TextCodec.convert(storage.string, to: ending)
    if converted != storage.string {
      undoManager?.registerUndo(withTarget: self) { doc in
        let previous = doc.storage.string
        doc.setText(previous)
      }
      setText(converted)
    }
    updateChangeCount(.changeDone)
  }

  private static func trimTrailingWhitespace(_ text: String) -> String {
    var out = ""
    out.reserveCapacity(text.utf8.count)
    for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" }) {
      // `\r\n` is a single Character; keep it intact.
      var l = Substring(line)
      var trailingCR = false
      if l.last == "\r" { trailingCR = true; l = l.dropLast() }
      while let last = l.last, last == " " || last == "\t" { l = l.dropLast() }
      out += l
      if trailingCR { out += "\r" }
      out += "\n"
    }
    out.removeLast()
    return out
  }

  // MARK: - Printing

  override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
    let info = NSPrintInfo(dictionary: printSettings)
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    info.isVerticallyCentered = false
    let view = PrintView.make(document: self, printInfo: info)
    return NSPrintOperation(view: view, printInfo: info)
  }
}
