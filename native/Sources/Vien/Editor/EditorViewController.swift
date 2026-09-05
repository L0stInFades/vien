import AppKit
import VienMarkdown

/// Hosts the text view, keeps the parsed document in sync with every edit, and applies the editor
/// modes (source, typewriter, focus).
final class EditorViewController: NSViewController, NSTextStorageDelegate, NSTextViewDelegate {
  let document: MarkdownFile
  private(set) var textView: EditorTextView!
  private(set) var scrollView: NSScrollView!
  private var styler: Styler!
  private var layoutManager: NSTextLayoutManager!
  private var contentStorage: NSTextContentStorage!
  private var wordCountTask: Task<Void, Never>?
  private var zoom: CGFloat = 1
  var onSelectionChange: ((Int) -> Void)?
  var onStatsChange: ((MarkdownDocument.WordCount) -> Void)?

  init(document: MarkdownFile) {
    self.document = document
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    contentStorage = NSTextContentStorage()
    contentStorage.textStorage = document.storage
    layoutManager = NSTextLayoutManager()
    contentStorage.addTextLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
    layoutManager.textContainer = container

    textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
    textView.document = document
    textView.configure()
    textView.delegate = self

    styler = Styler(document: document)
    styler.textView = textView
    styler.sourceMode = Preferences.shared.sourceMode
    styler.focusMode = Preferences.shared.focus
    contentStorage.delegate = styler
    layoutManager.delegate = styler

    scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.documentView = textView
    scrollView.drawsBackground = true
    scrollView.backgroundColor = Theme.background
    scrollView.contentView.postsBoundsChangedNotifications = true
    view = scrollView

    document.storage.delegate = self
    applyTheme(invalidate: false)
    NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: textView)
    NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    scheduleStats()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    view.window?.makeFirstResponder(textView)
  }

  // MARK: - Model sync

  func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
    guard editedMask.contains(.editedCharacters) else { return }
    let oldRange = editedRange.location..<(editedRange.location + editedRange.length - delta)
    let replacement = (textStorage.string as NSString).substring(with: editedRange)
    let affected = document.markdown.replace(utf16Range: oldRange, with: replacement)
    document.lastReparse = affected
    // Structure may have changed beyond the edited paragraph (fences, lists, tables): re-style it.
    let lo = document.markdown.utf16Offset(forByte: affected.lowerBound)
    let hi = document.markdown.utf16Offset(forByte: affected.upperBound)
    let region = NSRange(location: lo, length: max(0, hi - lo))
    if region.location < editedRange.location || NSMaxRange(region) > NSMaxRange(editedRange) {
      Task { @MainActor [weak self] in self?.textView.invalidateParagraphs(in: region) }
    }
    scheduleStats()
  }

  private func scheduleStats() {
    wordCountTask?.cancel()
    wordCountTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled, let self else { return }
      let wc = document.markdown.wordCount()
      onStatsChange?(wc)
    }
  }

  @objc private func selectionChanged(_ note: Notification) {
    let sel = textView.selectedRange()
    onSelectionChange?(sel.location)
    if Preferences.shared.focus { updateFocus() }
    if Preferences.shared.typewriter { centerCaret() }
  }

  @objc private func appearanceChanged() {
    textView.invalidateAll()
  }

  // MARK: - Modes

  func applyTheme(invalidate: Bool = true) {
    styler.theme = Theme(zoom: zoom)
    textView.contentWidth = CGFloat(Preferences.shared.contentWidth) * zoom
    textView.typingAttributes = [.font: styler.theme.body(), .foregroundColor: Theme.text]
    if invalidate { textView.invalidateAll() }
  }

  func setZoom(_ z: CGFloat) {
    zoom = max(0.5, min(3, z))
    applyTheme()
  }

  var zoomLevel: CGFloat { zoom }

  func setSourceMode(_ on: Bool) {
    Preferences.shared.sourceMode = on
    styler.sourceMode = on
    textView.invalidateAll()
  }

  func setFocusMode(_ on: Bool) {
    Preferences.shared.focus = on
    styler.focusMode = on
    updateFocus()
    textView.invalidateAll()
  }

  func setTypewriter(_ on: Bool) {
    Preferences.shared.typewriter = on
    textView.needsLayout = true
    textView.layout()
    if on { centerCaret() }
  }

  private func updateFocus() {
    let sel = textView.selectedRange()
    let b = document.markdown.byteOffset(forUTF16: sel.location)
    let path = document.markdown.path(at: b)
    let newRange = path.first?.range
    guard newRange != styler.focusRange else { return }
    let old = styler.focusRange
    styler.focusRange = newRange
    if Preferences.shared.focus {
      for r in [old, newRange].compactMap({ $0 }) {
        let lo = document.markdown.utf16Offset(forByte: r.lowerBound), hi = document.markdown.utf16Offset(forByte: r.upperBound)
        textView.invalidateParagraphs(in: NSRange(location: lo, length: hi - lo))
      }
    }
  }

  private func centerCaret() {
    let sel = textView.selectedRange()
    guard let lm = textView.textLayoutManager, let cs = lm.textContentManager as? NSTextContentStorage else { return }
    guard let loc = cs.location(cs.documentRange.location, offsetBy: sel.location) else { return }
    lm.ensureLayout(for: NSTextRange(location: loc))
    var caretY: CGFloat? = nil
    lm.enumerateTextSegments(in: NSTextRange(location: loc), type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
      caretY = frame.midY
      return false
    }
    guard let y = caretY else { return }
    let visible = scrollView.contentView.bounds
    let target = y + textView.textContainerInset.height - visible.height / 2
    let current = visible.origin.y
    if abs(target - current) > 2 {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.12
        scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, target)))
      }
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }
  }

  // MARK: - Navigation

  func scroll(toByteOffset offset: Int) {
    let u = document.markdown.utf16Offset(forByte: offset)
    textView.setSelectedRange(NSRange(location: u, length: 0))
    textView.scrollRangeToVisible(NSRange(location: u, length: 0))
    view.window?.makeFirstResponder(textView)
  }

  func select(utf16Range: NSRange) {
    textView.setSelectedRange(utf16Range)
    textView.scrollRangeToVisible(utf16Range)
    view.window?.makeFirstResponder(textView)
  }

  // MARK: - NSTextViewDelegate

  func undoManager(for view: NSTextView) -> UndoManager? { document.undoManager }

  /// Spelling results inside code, math, HTML and front matter are noise: drop them.
  func textView(_ view: NSTextView, didCheckTextIn range: NSRange, types checkingTypes: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey: Any], results: [NSTextCheckingResult], orthography: NSOrthography, wordCount: Int) -> [NSTextCheckingResult] {
    let doc = document.markdown
    return results.filter { result in
      let b = doc.byteOffset(forUTF16: result.range.location)
      guard let leaf = doc.path(at: b).last else { return true }
      switch leaf.kind {
      case .fencedCode, .indentedCode, .htmlBlock, .mathBlock, .frontMatter, .linkReferenceDefinition, .table: return false
      case .paragraph, .heading, .tableCell:
        // Inline code and math spans.
        func inSpan(_ nodes: [Inline]) -> Bool {
          for n in nodes where n.range.contains(b) {
            switch n.kind {
            case .code, .math, .html, .autolink, .extendedAutolink: return true
            case .link(let dest, _), .image(let dest, _):
              // The destination part of a link is not prose.
              let contentEnd = n.children.last?.range.upperBound ?? n.range.lowerBound
              if b >= contentEnd { return true }
              _ = dest
              return inSpan(n.children)
            default: if inSpan(n.children) { return true }
            }
          }
          return false
        }
        return !inSpan(doc.inlines(of: leaf))
      default: return true
      }
    }
  }
}
