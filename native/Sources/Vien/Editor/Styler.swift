import AppKit
import CoreText
import VienCode
import VienMarkdown

/// A paragraph element that knows whether something is drawn beneath it (diagram, math, images).
nonisolated final class MarkdownParagraph: NSTextParagraph {
  var overlay: Overlay?
  var decoration: Decoration = .none

  enum Decoration { case none, rule, codeBlock(first: Bool, last: Bool), quote, table(Block), hiddenLine }
}

/// Produces styled paragraphs on demand for the text view (TextKit 2 asks for them lazily as it lays
/// out the viewport), so styling cost is proportional to what is visible, never to document length.
final class Styler: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
  /// Diagnostics: how many paragraphs have been styled since launch (reported by VIEN_QUIT_WHEN_READY).
  static var paragraphsStyled = 0
  /// Paragraph elements handed to TextKit since the last recycling (see `EditorViewController`).
  var elementsCreated = 0
  unowned let document: MarkdownFile
  var theme = Theme() { didSet { gridCache.removeAll() } }
  var sourceMode = false
  var focusMode = false
  /// Hide markup outside `activeRange` (the block holding the selection); see Preferences.foldMarkup.
  var foldMarkup = true
  var activeRange: Range<Int>?
  private var gridCache: [Range<Int>: TableGrid] = [:]
  private var gridCacheRevision = -1
  private var gridCacheWidth: CGFloat = 0
  /// Byte range of the block that holds the selection (focus mode dims the rest).
  var focusRange: Range<Int>?
  weak var textView: EditorTextView?
  /// Inline parses are reused for the lines of one block (and across relayouts) until the next edit.
  private var inlineCache: [Range<Int>: [Inline]] = [:]
  private var inlineCacheRevision = -1
  private var prefixWidths: [String: CGFloat] = [:]
  private let highlight = CodeHighlight()

  init(document: MarkdownFile) {
    self.document = document
  }

  private func inlines(of block: Block) -> [Inline] {
    if inlineCacheRevision != document.revision {
      inlineCache.removeAll(keepingCapacity: true)
      inlineCacheRevision = document.revision
    }
    if let hit = inlineCache[block.range] { return hit }
    let parsed = document.markdown.inlines(of: block)
    if inlineCache.count > 4096 { inlineCache.removeAll(keepingCapacity: true) }
    inlineCache[block.range] = parsed
    return parsed
  }

  private func prefixWidth(_ prefix: NSAttributedString) -> CGFloat {
    let key = prefix.string + "|" + String(describing: (prefix.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 0)
    if let w = prefixWidths[key] { return w }
    let line = CTLineCreateWithAttributedString(prefix)
    let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    if prefixWidths.count > 512 { prefixWidths.removeAll(keepingCapacity: true) }
    prefixWidths[key] = w
    return w
  }

  // MARK: - NSTextContentStorageDelegate

  func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
    Self.paragraphsStyled += 1
    elementsCreated += 1
    guard let storage = textContentStorage.textStorage else { return nil }
    let text = (storage.string as NSString).substring(with: range)
    let styled = NSMutableAttributedString(string: text)
    let paragraph = MarkdownParagraph(attributedString: styled)
    style(styled, paragraph: paragraph, utf16Range: range)
    return MarkdownParagraph(attributedString: styled, overlay: paragraph.overlay, decoration: paragraph.decoration)
  }

  // MARK: - NSTextLayoutManagerDelegate

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
    if let p = textElement as? MarkdownParagraph {
      switch p.decoration {
      case .table(let block):
        // Laid out here, at fragment time, so the grid always fits the current container width.
        if let grid = grid(for: block) { return TableFragment(textElement: p, range: p.elementRange, grid: grid, bottomPadding: theme.paragraphSpacing) }
      case .hiddenLine: return HiddenLineFragment(textElement: p, range: p.elementRange)
      default: break
      }
      if let overlay = p.overlay {
        return OverlayFragment(textElement: p, range: p.elementRange, overlay: overlay, contentWidth: contentWidth, dark: isDark)
      }
      if case .none = p.decoration {} else {
        return DecoratedFragment(textElement: p, range: p.elementRange, decoration: p.decoration, theme: theme)
      }
    }
    return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
  }

  private var contentWidth: CGFloat {
    guard let tv = textView else { return 600 }
    return tv.textContainer?.size.width ?? 600
  }

  private var isDark: Bool {
    textView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  // MARK: - Styling

  private func style(_ s: NSMutableAttributedString, paragraph: MarkdownParagraph, utf16Range: NSRange) {
    let doc = document.markdown
    let full = NSRange(location: 0, length: s.length)
    let bodyFont = sourceMode ? theme.code(size: theme.baseSize) : theme.body()
    s.setAttributes([.font: bodyFont, .foregroundColor: Theme.text, .paragraphStyle: theme.paragraphStyle()], range: full)
    guard s.length > 0 else { return }

    let byteStart = doc.byteOffset(forUTF16: utf16Range.location)
    let byteEnd = doc.byteOffset(forUTF16: NSMaxRange(utf16Range))
    // Byte → UTF-16 (paragraph-relative) map for this line.
    var u16 = [Int](repeating: 0, count: byteEnd - byteStart + 1)
    do {
      var i = byteStart
      var u = 0
      let bytes = doc.bytes
      while i < byteEnd {
        u16[i - byteStart] = u
        let b = bytes[i]
        let len = b < 0x80 ? 1 : b & 0xE0 == 0xC0 ? 2 : b & 0xF0 == 0xE0 ? 3 : b & 0xF8 == 0xF0 ? 4 : 1
        for k in 1..<len where i + k - byteStart < u16.count { u16[i + k - byteStart] = u }
        u += len == 4 ? 2 : 1
        i += len
      }
      u16[byteEnd - byteStart] = u
    }
    func nsRange(_ r: Range<Int>) -> NSRange {
      let lo = max(byteStart, min(byteEnd, r.lowerBound)), hi = max(byteStart, min(byteEnd, r.upperBound))
      return NSRange(location: u16[lo - byteStart], length: u16[hi - byteStart] - u16[lo - byteStart])
    }
    func mark(_ r: Range<Int>, _ color: NSColor = Theme.marker) {
      let n = nsRange(r)
      if n.length > 0 { s.addAttribute(.foregroundColor, value: color, range: n) }
    }
    func hideText(_ r: Range<Int>) {
      let n = nsRange(r)
      if n.length > 0 { s.addAttributes(Theme.hiddenAttributes, range: n) }
    }
    // Markup is folded on every line outside the block that holds the selection.
    var active = false
    if let r = activeRange { active = r.lowerBound == byteStart || (byteEnd > r.lowerBound && byteStart < r.upperBound) }
    var hide: ((Range<Int>) -> Void)? = nil
    if foldMarkup, !sourceMode, !active { hide = hideText }

    // Locate the innermost block on this line: start at the first non-blank byte, then step past
    // container prefixes (`>`, list markers) until the path ends in a leaf.
    var probe = byteStart
    while probe < byteEnd, doc.bytes[probe] == 0x20 || doc.bytes[probe] == 0x09 { probe += 1 }
    var path = doc.path(at: probe)
    var guardCount = 0
    while let deepest = path.last, deepest.isContainer, guardCount < 8 {
      guardCount += 1
      var next = probe
      switch deepest.kind {
      case .listItem(let info):
        if info.marker.lowerBound >= byteStart, info.marker.upperBound <= byteEnd { next = max(next, info.task?.range.upperBound ?? info.marker.upperBound) }
      case .blockQuote(let prefixes):
        if let p = prefixes.last(where: { $0.lowerBound >= byteStart && $0.lowerBound < byteEnd }) { next = max(next, p.upperBound) }
      case .footnoteDefinition(_, let marker):
        if marker.lowerBound >= byteStart, marker.upperBound <= byteEnd { next = max(next, marker.upperBound) }
      default: break
      }
      while next < byteEnd, doc.bytes[next] == 0x20 || doc.bytes[next] == 0x09 { next += 1 }
      guard next > probe else { break }
      probe = next
      let deeper = doc.path(at: probe)
      guard deeper.count > path.count else { break }
      path = deeper
    }
    let inFocus = focusRange.map { $0.contains(probe) || $0.upperBound == probe } ?? true

    var indent: CGFloat = 0
    var textColor = Theme.text
    var leaf: Block? = nil
    for block in path {
      switch block.kind {
      case .blockQuote(let prefixes):
        textColor = Theme.quote
        for p in prefixes where p.lowerBound >= byteStart && p.lowerBound < byteEnd { mark(p) }
        paragraph.decoration = .quote
      case .listItem(let info):
        if info.marker.lowerBound >= byteStart, info.marker.lowerBound < byteEnd {
          mark(info.marker, Theme.secondary)
          if let task = info.task { mark(task.range, Theme.accent) }
        }
      case .list, .table, .tableRow, .footnoteDefinition:
        if case .footnoteDefinition(_, let marker) = block.kind, marker.lowerBound >= byteStart, marker.lowerBound < byteEnd {
          mark(marker, Theme.secondary)
        }
      default:
        leaf = block
      }
    }
    if hide != nil, let table = path.first(where: { if case .table = $0.kind { return true }; return false }) {
      // A folded table: every row's text is hidden; the first row's fragment draws the grid.
      hideText(byteStart..<byteEnd)
      let first = table.range.lowerBound >= byteStart && table.range.lowerBound < byteEnd
      paragraph.decoration = first ? .table(table) : .hiddenLine
      s.addAttribute(.paragraphStyle, value: theme.paragraphStyle(lineHeight: 1, indent: 0), range: full)
      return
    }
    if !sourceMode {
      // Wrapped lines align under the text that follows the line's prefix (markers, spaces).
      var prefixEnd = probe
      if let leaf, case .paragraph = leaf.kind, let first = leaf.lines.first, first.range.lowerBound >= byteStart, first.range.lowerBound <= byteEnd {
        prefixEnd = max(prefixEnd, first.range.lowerBound)
      } else if let leaf, case .heading = leaf.kind, let first = leaf.lines.first, first.range.lowerBound >= byteStart, first.range.lowerBound <= byteEnd {
        prefixEnd = max(prefixEnd, first.range.lowerBound)
      }
      if prefixEnd > byteStart {
        let prefix = s.attributedSubstring(from: nsRange(byteStart..<prefixEnd))
        indent = prefixWidth(prefix)
      }
    }
    if textColor != Theme.text { s.addAttribute(.foregroundColor, value: textColor, range: full) }

    var style = theme.paragraphStyle(indent: indent, firstLineIndent: 0)
    if let leaf { style = leafStyle(leaf, s: s, full: full, byteStart: byteStart, byteEnd: byteEnd, indent: indent, paragraph: paragraph, nsRange: nsRange, mark: mark, hide: hide) }
    s.addAttribute(.paragraphStyle, value: style, range: full)

    if focusMode, !inFocus {
      s.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: full)
    }
  }

  private func grid(for table: Block) -> TableGrid? {
    let width = contentWidth - 4
    if gridCacheRevision != document.revision || gridCacheWidth != width {
      gridCache.removeAll(keepingCapacity: true)
      gridCacheRevision = document.revision
      gridCacheWidth = width
    }
    if let hit = gridCache[table.range] { return hit }
    let doc = document.markdown
    let renderer = AttributedRenderer(document: doc, theme: theme)
    let size = theme.baseSize * 0.95
    let grid = TableGrid(table: table, width: width) { cell, header in
      renderer.inlines(doc.inlines(of: cell), font: header ? theme.body(weight: .semibold, size: size) : theme.body(size: size), color: Theme.text)
    }
    if let grid { gridCache[table.range] = grid }
    return grid
  }

  private func leafStyle(_ leaf: Block, s: NSMutableAttributedString, full: NSRange, byteStart: Int, byteEnd: Int, indent: CGFloat,
    paragraph: MarkdownParagraph, nsRange: (Range<Int>) -> NSRange, mark: (Range<Int>, NSColor) -> Void, hide: ((Range<Int>) -> Void)?) -> NSParagraphStyle
  {
    let doc = document.markdown
    let isLastLine = leaf.range.upperBound >= byteStart && leaf.range.upperBound <= byteEnd
    let isFirstLine = leaf.range.lowerBound >= byteStart && leaf.range.lowerBound < byteEnd
    switch leaf.kind {
    case .heading(let level, let marker, let trailing, let underline):
      if !sourceMode { s.addAttribute(.font, value: theme.heading(level: level), range: full) }
      if let marker { mark(marker, Theme.marker) }
      if let trailing { mark(trailing, Theme.marker) }
      if let underline, underline.lowerBound >= byteStart { mark(underline, Theme.marker) }
      styleInlines(inlines(of: leaf), s: s, nsRange: nsRange, mark: mark, hide: hide, base: theme.heading(level: level))
      return theme.paragraphStyle(lineHeight: 1.25, indent: indent, firstLineIndent: 0, spacingBefore: sourceMode ? 0 : theme.headingSpacingBefore, spacingAfter: theme.paragraphSpacing * 0.5)
    case .paragraph:
      let inlines = inlines(of: leaf)
      styleInlines(inlines, s: s, nsRange: nsRange, mark: mark, hide: hide, base: nil)
      if !sourceMode {
        let images = Styler.imageSources(inlines)
        if !images.isEmpty {
          if isLastLine { paragraph.overlay = .images(images.map { document.resolveImageURL($0) }) }
          // A paragraph that is only images shows the images in its place.
          if let hide, Styler.isImagesOnly(inlines) { hide(byteStart..<byteEnd) }
        }
      }
      return theme.paragraphStyle(indent: indent, firstLineIndent: 0, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    case .fencedCode(let fence):
      s.addAttribute(.font, value: theme.code(), range: full)
      if isFirstLine { mark(fence.open, Theme.marker); if let info = fence.info { mark(info, Theme.secondary) } }
      if let close = fence.close, close.lowerBound >= byteStart, close.lowerBound < byteEnd { mark(close, Theme.marker) }
      paragraph.decoration = .codeBlock(first: isFirstLine, last: isLastLine)
      if !sourceMode {
        for token in highlight.tokens(for: leaf, in: document, intersecting: byteStart..<byteEnd) { mark(token.range, Theme.syntax(token.kind)) }
      }
      if isLastLine, !sourceMode, let lang = leaf.language(in: doc.bytes)?.lowercased() {
        if lang == "mermaid" { paragraph.overlay = .mermaid(doc.text(of: leaf)) }
        else if lang == "math" || lang == "latex" || lang == "tex" { paragraph.overlay = .math(doc.text(of: leaf)) }
      }
      return theme.paragraphStyle(lineHeight: 1.35, indent: 0, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    case .indentedCode:
      s.addAttribute(.font, value: theme.code(), range: full)
      paragraph.decoration = .codeBlock(first: isFirstLine, last: isLastLine)
      return theme.paragraphStyle(lineHeight: 1.35, indent: 0, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    case .htmlBlock, .linkReferenceDefinition:
      s.addAttribute(.font, value: theme.code(), range: full)
      s.addAttribute(.foregroundColor, value: Theme.secondary, range: full)
      return theme.paragraphStyle(lineHeight: 1.35, indent: indent, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    case .mathBlock(let open, let close):
      s.addAttribute(.font, value: theme.code(), range: full)
      if open.lowerBound >= byteStart, open.lowerBound < byteEnd { mark(open, Theme.marker) }
      if let close, close.lowerBound >= byteStart, close.lowerBound < byteEnd { mark(close, Theme.marker) }
      if isLastLine, !sourceMode { paragraph.overlay = .math(doc.text(of: leaf)) }
      return theme.paragraphStyle(lineHeight: 1.35, indent: indent, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    case .frontMatter(_, let open, let close):
      s.addAttribute(.font, value: theme.code(), range: full)
      s.addAttribute(.foregroundColor, value: Theme.secondary, range: full)
      if open.lowerBound >= byteStart, open.lowerBound < byteEnd { mark(open, Theme.marker) }
      if let close, close.lowerBound >= byteStart, close.lowerBound < byteEnd { mark(close, Theme.marker) }
      return theme.paragraphStyle(lineHeight: 1.35, indent: 0, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    case .thematicBreak:
      s.addAttribute(.foregroundColor, value: Theme.marker, range: full)
      paragraph.decoration = .rule
      return theme.paragraphStyle(indent: indent, spacingBefore: theme.paragraphSpacing * 0.5, spacingAfter: theme.paragraphSpacing)
    case .tableCell, .table, .tableRow:
      // The table block's rows are children; a line inside the table is styled as a whole row.
      s.addAttribute(.font, value: theme.code(), range: full)
      return theme.paragraphStyle(lineHeight: 1.35, indent: 0, spacingAfter: isLastLine ? theme.paragraphSpacing : 0)
    default:
      return theme.paragraphStyle(indent: indent, firstLineIndent: 0)
    }
  }

  private func styleInlines(_ inlines: [Inline], s: NSMutableAttributedString, nsRange: (Range<Int>) -> NSRange, mark: (Range<Int>, NSColor) -> Void, hide: ((Range<Int>) -> Void)?, base: NSFont?) {
    for node in inlines { styleInline(node, s: s, nsRange: nsRange, mark: mark, hide: hide, bold: false, italic: false, base: base) }
  }

  private func styleInline(_ node: Inline, s: NSMutableAttributedString, nsRange: (Range<Int>) -> NSRange, mark: (Range<Int>, NSColor) -> Void, hide: ((Range<Int>) -> Void)?, bold: Bool, italic: Bool, base: NSFont?) {
    let r = nsRange(node.range)
    var bold = bold, italic = italic
    func applyFont() {
      guard r.length > 0, (bold || italic) else { return }
      let size = (base ?? theme.body()).pointSize
      s.addAttribute(.font, value: theme.body(weight: bold ? .bold : .regular, size: size, italic: italic), range: r)
    }
    switch node.kind {
    case .emphasis: italic = true; applyFont()
    case .strong: bold = true; applyFont()
    case .code:
      if r.length > 0 {
        s.addAttribute(.font, value: theme.code(size: base?.pointSize), range: r)
        s.addAttribute(.backgroundColor, value: Theme.codeBackground, range: r)
      }
    case .link, .image:
      if r.length > 0 { s.addAttribute(.foregroundColor, value: Theme.link, range: r) }
    case .autolink, .extendedAutolink:
      if r.length > 0 { s.addAttribute(.foregroundColor, value: Theme.link, range: r) }
    case .html:
      if r.length > 0 { s.addAttribute(.foregroundColor, value: Theme.secondary, range: r) }
    case .math:
      if r.length > 0 { s.addAttribute(.font, value: theme.code(size: base?.pointSize), range: r) }
    case .strikethrough:
      if r.length > 0 { s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r) }
    case .footnoteReference:
      if r.length > 0 { s.addAttribute(.foregroundColor, value: Theme.accent, range: r) }
      if let hide, node.range.count > 3 {
        // `[^label]` becomes a superscript label.
        hide(node.range.lowerBound..<(node.range.lowerBound + 2))
        hide((node.range.upperBound - 1)..<node.range.upperBound)
        let label = nsRange((node.range.lowerBound + 2)..<(node.range.upperBound - 1))
        let size = (base ?? theme.body()).pointSize
        s.addAttributes([.font: theme.body(size: size * 0.7), .baselineOffset: size * 0.33], range: label)
      }
    case .superscript, .subscript:
      if r.length > 0 { s.addAttribute(.foregroundColor, value: Theme.secondary, range: r) }
    default: break
    }
    if !sourceMode {
      for m in node.markers {
        if let hide, Styler.folds(node.kind) { hide(m) } else { mark(m, Theme.marker) }
      }
    }
    for child in node.children { styleInline(child, s: s, nsRange: nsRange, mark: mark, hide: hide, bold: bold, italic: italic, base: base) }
  }

  /// Markers that disappear when the paragraph is not being edited. Math and emoji stay: their
  /// source is what the reader sees.
  private static func folds(_ kind: InlineKind) -> Bool {
    switch kind {
    case .emphasis, .strong, .strikethrough, .code, .superscript, .subscript, .autolink, .link, .image: return true
    default: return false
    }
  }

  static func isImagesOnly(_ inlines: [Inline]) -> Bool {
    var sawImage = false
    for n in inlines {
      switch n.kind {
      case .image: sawImage = true
      case .text(let t): if !t.allSatisfy({ $0 == " " || $0 == "\t" }) { return false }
      case .softBreak, .hardBreak: break
      default: return false
      }
    }
    return sawImage
  }

  static func imageSources(_ inlines: [Inline]) -> [String] {
    var out: [String] = []
    for n in inlines {
      if case .image(let dest, _) = n.kind { out.append(dest) }
      out.append(contentsOf: imageSources(n.children))
    }
    return out
  }
}

extension MarkdownParagraph {
  convenience init(attributedString: NSAttributedString, overlay: Overlay?, decoration: Decoration) {
    self.init(attributedString: attributedString)
    self.overlay = overlay
    self.decoration = decoration
  }
}

extension MarkdownFile {
  /// Resolves an image destination relative to the document's folder.
  func resolveImageURL(_ dest: String) -> URL {
    if let url = URL(string: dest), url.scheme != nil { return url }
    let path = dest.removingPercentEncoding ?? dest
    if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
    let base = fileURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
    return base.appendingPathComponent(path)
  }
}
