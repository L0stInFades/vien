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
    trace("editor: loadView")
    styler = Styler(document: document)
    styler.sourceMode = Preferences.shared.sourceMode
    styler.focusMode = Preferences.shared.focus
    styler.foldMarkup = Preferences.shared.foldMarkup
    // TextKit 2 asks the delegate for a paragraph only when it lays one out, so attaching it before
    // the text is attached costs nothing for the paragraphs that are not on screen.
    contentStorage = NSTextContentStorage()
    contentStorage.delegate = styler
    contentStorage.textStorage = document.storage
    layoutManager = NSTextLayoutManager()
    layoutManager.delegate = styler
    contentStorage.addTextLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
    layoutManager.textContainer = container

    textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
    textView.document = document
    textView.configure()
    textView.delegate = self
    styler.textView = textView

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
    trace("editor: view built")
    NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: textView)
    NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    scheduleStats()
    observePreferences()
  }

  /// Settings changes reach open editors through Observation; each change re-registers.
  private func observePreferences() {
    withObservationTracking {
      let p = Preferences.shared
      _ = (p.fontSize, p.lineHeight, p.contentWidth, p.fontFamily, p.codeFontFamily, p.foldMarkup, p.theme)
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        styler.foldMarkup = Preferences.shared.foldMarkup
        applyTheme()
        observePreferences()
      }
    }
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    trace("editor: viewDidAppear")
    view.window?.appearance = styler.theme.palette.appearance
    view.window?.makeFirstResponder(textView)
  }

  // MARK: - Element recycling

  /// TextKit 2 keeps every paragraph element it has ever created and, on each keystroke, rewrites the
  /// range of all of them after the caret (about 2 µs each). Reading through a long document would
  /// therefore make typing slower and slower, so once scrolling has created this many elements they
  /// are dropped again with a whole-document attribute invalidation, which recreates only the
  /// visible ones. Cost: one viewport relayout every few thousand paragraphs scrolled.
  private static let elementBudget = 2_000
  private var recyclePending = false

  @objc private func scrolled() {
    guard styler.elementsCreated > Self.elementBudget, !recyclePending else { return }
    recyclePending = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      recyclePending = false
      if styler.elementsCreated > Self.elementBudget { recycleElements() }
    }
  }

  /// Drops every cached paragraph element; the visible ones are rebuilt in place.
  func recycleElements() {
    guard !textView.hasMarkedText(), NSEvent.pressedMouseButtons == 0 else { return }
    styler.elementsCreated = 0
    textView.keepingViewport { textView.invalidateAll() }
  }

  var elementsCreated: Int { styler.elementsCreated }

  // MARK: - Model sync

  func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
    guard editedMask.contains(.editedCharacters) else { return }
    let oldRange = editedRange.location..<(editedRange.location + editedRange.length - delta)
    let replacement = (textStorage.string as NSString).substring(with: editedRange)
    let affected = document.markdown.replace(utf16Range: oldRange, with: replacement)
    document.revision += 1
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
    updateActiveBlock()
    if Preferences.shared.focus { updateFocus() }
    if Preferences.shared.typewriter { centerCaret() }
  }

  /// The block(s) holding the selection show their markup; every other paragraph folds it.
  private func updateActiveBlock() {
    let doc = document.markdown
    func unit(atUTF16 u: Int) -> Range<Int>? {
      let b = doc.byteOffset(forUTF16: u)
      var path = doc.path(at: b)
      // A caret at the very end of a block belongs to that block, not to whatever follows.
      if path.last.map({ !$0.range.contains(b) }) ?? true, b > 0, doc.bytes[b - 1] != 0x0A {
        let before = doc.path(at: b - 1)
        if let leaf = before.last, leaf.range.upperBound >= b { path = before }
      }
      if let table = path.first(where: { if case .table = $0.kind { return true }; return false }) { return table.range }
      return path.last?.range
    }
    let sel = textView.selectedRange()
    var active = unit(atUTF16: sel.location)
    if sel.length > 0, let end = unit(atUTF16: NSMaxRange(sel)) {
      active = active.map { min($0.lowerBound, end.lowerBound)..<max($0.upperBound, end.upperBound) } ?? end
    }
    guard active != styler.activeRange else { return }
    let old = styler.activeRange
    styler.activeRange = active
    guard styler.foldMarkup, !styler.sourceMode else { return }
    restyle(from: old, to: active)
  }

  /// Rebuilds the paragraphs whose folding/focus state changed between two block ranges. While
  /// typing, the block only grows or shrinks at its end, so just that difference is rebuilt.
  private func restyle(from old: Range<Int>?, to new: Range<Int>?) {
    let doc = document.markdown
    func invalidate(_ r: Range<Int>) {
      guard !r.isEmpty else { return }
      let lo = doc.utf16Offset(forByte: r.lowerBound), hi = doc.utf16Offset(forByte: r.upperBound)
      textView.invalidateParagraphs(in: NSRange(location: lo, length: max(0, hi - lo)))
    }
    if let old, let new, old.lowerBound == new.lowerBound {
      invalidate(min(old.upperBound, new.upperBound)..<max(old.upperBound, new.upperBound))
    } else {
      for r in [old, new].compactMap({ $0 }) { invalidate(r) }
    }
  }

  @objc private func appearanceChanged() {
    restyleEverything()
  }

  // MARK: - Modes

  func applyTheme(invalidate: Bool = true) {
    styler.theme = Theme(zoom: zoom)
    Theme.current = styler.theme
    let palette = styler.theme.palette
    textView.backgroundColor = palette.background
    textView.insertionPointColor = palette.accent
    scrollView.backgroundColor = palette.background
    view.window?.appearance = palette.appearance
    // A fixed palette themes every window (Settings, Quick Open) so nothing stays light beside a dark editor.
    if palette.appearance != nil || ProcessInfo.processInfo.environment["VIEN_SNAPSHOT_DARK"] == nil { NSApp.appearance = palette.appearance }
    textView.contentWidth = CGFloat(Preferences.shared.contentWidth) * zoom
    textView.typingAttributes = [.font: styler.theme.body(), .foregroundColor: palette.text]
    OverlayStore.shared.clear()
    if invalidate { restyleEverything() }
  }

  /// Rebuilds every visible paragraph now; the rest are built as they scroll into view, so switching
  /// modes in a 10 MB document does not stall.
  func restyleEverything() {
    styler.elementsCreated = 0
    textView.keepingViewport { textView.invalidateAll() }
  }

  func setZoom(_ z: CGFloat) {
    zoom = max(0.5, min(3, z))
    applyTheme()
  }

  var zoomLevel: CGFloat { zoom }

  func setSourceMode(_ on: Bool) {
    Preferences.shared.sourceMode = on
    styler.sourceMode = on
    restyleEverything()
  }

  func setFocusMode(_ on: Bool) {
    Preferences.shared.focus = on
    styler.focusMode = on
    updateFocus()
    restyleEverything()
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
      if old == nil { restyleEverything(); return }
      restyle(from: old, to: newRange)
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
        if case .paragraph = leaf.kind, Styler.isImagesOnly(doc.inlines(of: leaf)) { return false }  // hidden when folded
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
