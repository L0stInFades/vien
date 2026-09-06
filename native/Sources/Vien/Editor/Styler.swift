import AppKit
import CoreText
import VienCode
import VienMarkdown

/// A paragraph element that carries what its fragment draws around the text.
nonisolated final class MarkdownParagraph: NSTextParagraph {
  var overlay: Overlay?
  var decor = Decor()

  convenience init(attributedString: NSAttributedString, overlay: Overlay?, decor: Decor) {
    self.init(attributedString: attributedString)
    self.overlay = overlay
    self.decor = decor
  }
}

/// Produces styled paragraphs on demand for the text view (TextKit 2 asks for them lazily as it lays
/// out the viewport), so styling cost is proportional to what is visible, never to document length.
///
/// Outside the block that holds the selection, markup folds away: heading hashes, quote prefixes,
/// fences, rules and inline delimiters keep their bytes but take no space, and the fragment draws
/// what they stood for (a bar, a background, a bullet, a rule). The active block shows its source.
final class Styler: NSObject, NSTextContentStorageDelegate, NSTextLayoutManagerDelegate {
  /// Diagnostics: how many paragraphs have been styled since launch, and for how long in total.
  static var paragraphsStyled = 0
  static var stylingTime: TimeInterval = 0
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
    guard prefix.length > 0 else { return 0 }
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
    let styled = NSMutableAttributedString(string: (storage.string as NSString).substring(with: range))
    let t0 = Date()
    let result = style(styled, utf16Range: range)
    Self.stylingTime += Date().timeIntervalSince(t0)
    return MarkdownParagraph(attributedString: styled, overlay: result.overlay, decor: result.decor)
  }

  // MARK: - NSTextLayoutManagerDelegate

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
    guard let p = textElement as? MarkdownParagraph else { return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange) }
    if case .table(let block, let indent) = p.decor.kind {
      // The fragment asks for the grid at the container's current width (cached per width).
      return TableFragment(textElement: p, range: p.elementRange, table: block, width: contentWidth - indent, indent: indent, decor: p.decor, palette: theme.palette, bottomPadding: theme.paragraphSpacing) { [weak self] table, width in
        self?.grid(for: table, width: width)
      }
    }
    if let overlay = p.overlay {
      return OverlayFragment(textElement: p, range: p.elementRange, overlay: overlay, contentWidth: contentWidth, dark: isDark, decor: p.decor, palette: theme.palette)
    }
    return MarkdownFragment(textElement: p, range: p.elementRange, decor: p.decor, palette: theme.palette)
  }

  private var contentWidth: CGFloat {
    guard let tv = textView else { return 600 }
    return tv.textContainer?.size.width ?? 600
  }

  private var isDark: Bool {
    textView?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  // MARK: - Styling

  private struct Styled {
    var decor = Decor()
    var overlay: Overlay?
  }

  /// Vertical rhythm and horizontal inset a leaf block asks for.
  private struct Layout {
    var lineHeight: CGFloat? = nil
    var before: CGFloat = 0
    var after: CGFloat = 0
    var inset: CGFloat = 0
    /// The block's box starts at the container edge even when its lines begin with spaces.
    var flush = false
  }

  private func style(_ s: NSMutableAttributedString, utf16Range: NSRange) -> Styled {
    var out = Styled()
    let doc = document.markdown
    let bytes = doc.bytes
    let full = NSRange(location: 0, length: s.length)
    let bodyFont = sourceMode ? theme.code(size: theme.baseSize) : theme.body()
    s.setAttributes([.font: bodyFont, .foregroundColor: Theme.text, .paragraphStyle: theme.paragraphStyle()], range: full)
    guard s.length > 0 else { return out }

    let byteStart = doc.byteOffset(forUTF16: utf16Range.location)
    let byteEnd = doc.byteOffset(forUTF16: NSMaxRange(utf16Range))
    // Byte → UTF-16 (paragraph-relative) map for this line.
    var u16 = [Int](repeating: 0, count: byteEnd - byteStart + 1)
    do {
      var i = byteStart
      var u = 0
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
    func hide(_ r: Range<Int>) {
      let n = nsRange(r)
      if n.length > 0 { s.addAttributes(Theme.hiddenAttributes, range: n) }
    }
    func onLine(_ r: Range<Int>) -> Bool { r.lowerBound >= byteStart && r.lowerBound < byteEnd }
    func width(upTo end: Int) -> CGFloat { prefixWidth(s.attributedSubstring(from: nsRange(byteStart..<end))) }

    // Markup is folded on every line outside the block that holds the selection.
    let active = activeRange.map { $0.lowerBound == byteStart || (byteEnd > $0.lowerBound && byteStart < $0.upperBound) } ?? false
    let folded = foldMarkup && !sourceMode && !active

    // Locate the innermost block on this line: start at the first non-blank byte, then step past
    // container prefixes (`>`, list markers) until the path ends in a leaf.
    var probe = byteStart
    while probe < byteEnd, bytes[probe] == 0x20 || bytes[probe] == 0x09 { probe += 1 }
    var path = doc.path(at: probe)
    var guardCount = 0
    while let deepest = path.last, deepest.isContainer, guardCount < 8 {
      guardCount += 1
      var next = probe
      switch deepest.kind {
      case .listItem(let info):
        if info.marker.lowerBound >= byteStart, info.marker.upperBound <= byteEnd { next = max(next, info.task?.range.upperBound ?? info.marker.upperBound) }
      case .blockQuote(let prefixes):
        if let p = prefixes.last(where: { onLine($0) }) { next = max(next, p.upperBound) }
      case .footnoteDefinition(_, let marker):
        if marker.lowerBound >= byteStart, marker.upperBound <= byteEnd { next = max(next, marker.upperBound) }
      default: break
      }
      while next < byteEnd, bytes[next] == 0x20 || bytes[next] == 0x09 { next += 1 }
      guard next > probe else { break }
      probe = next
      let deeper = doc.path(at: probe)
      guard deeper.count > path.count else { break }
      path = deeper
    }
    let inFocus = focusRange.map { $0.contains(probe) || $0.upperBound == probe } ?? true

    var textColor = Theme.text
    var leaf: Block? = nil
    var listDepth = 0
    for block in path {
      switch block.kind {
      case .blockQuote(let prefixes):
        textColor = Theme.quote
        for p in prefixes where onLine(p) {
          guard folded else { mark(p); continue }
          // A bar stands in for the marker: `>` and the space after it fold away.
          let end = p.upperBound < byteEnd && bytes[p.upperBound] == 0x20 ? p.upperBound + 1 : p.upperBound
          out.decor.quoteBars.append(width(upTo: p.lowerBound) + CGFloat(out.decor.quoteBars.count) * theme.quoteIndent)
          hide(p.lowerBound..<end)
        }
      case .list:
        listDepth += 1
      case .listItem(let info):
        guard onLine(info.marker) else { break }
        if folded, "-*+".utf8.contains(bytes[info.marker.lowerBound]) {
          // The bullet is drawn over its marker, which stays in the text at full width.
          s.addAttribute(.foregroundColor, value: NSColor.clear, range: nsRange(info.marker))
          out.decor.bullet = Decor.Bullet(index: nsRange(info.marker).location, glyph: Decor.bulletGlyph(depth: listDepth))
        } else {
          mark(info.marker, folded ? Theme.text : Theme.secondary)
        }
        if let task = info.task { mark(task.range, Theme.accent) }
      case .footnoteDefinition(_, let marker):
        if onLine(marker) { mark(marker, Theme.secondary) }
      case .table:
        leaf = block  // the delimiter line has no row; rows and cells that follow replace this
      case .tableRow:
        break
      default:
        leaf = block
      }
    }
    let quoteShift = CGFloat(out.decor.quoteBars.count) * theme.quoteIndent

    if folded, let table = path.first(where: { if case .table = $0.kind { return true }; return false }) {
      // A folded table: every row's text is hidden; the first row's fragment draws the grid under
      // the same indent as the surrounding text (list marker, quote bars).
      let first = onLine(table.range)
      out.decor.kind = first ? .table(table, indent: width(upTo: table.range.lowerBound) + quoteShift) : .hiddenLine
      out.decor.fixedHeight = 0
      hide(byteStart..<byteEnd)
      s.addAttribute(.paragraphStyle, value: theme.paragraphStyle(lineHeight: 1, indent: 0), range: full)
      return out
    }
    if textColor != Theme.text { s.addAttribute(.foregroundColor, value: textColor, range: full) }

    var layout = Layout()
    if let leaf {
      layout = styleLeaf(leaf, in: path, s: s, full: full, byteStart: byteStart, byteEnd: byteEnd, folded: folded, out: &out, nsRange: nsRange, mark: mark, hide: hide)
    } else if folded, probe == byteEnd || bytes[probe] == 0x0A || bytes[probe] == 0x0D {
      layout.lineHeight = theme.blankLineHeight  // a blank line is a gap, not an empty line of text
    }

    // Wrapped lines align under the text that follows the line's prefix (markers, spaces). Folded
    // quote prefixes measure nothing, so the bars' indent is added back on every line.
    var indent: CGFloat = 0
    if !sourceMode {
      var prefixEnd = probe
      if let leaf, let first = leaf.lines.first, first.range.lowerBound >= byteStart, first.range.lowerBound <= byteEnd {
        switch leaf.kind {
        case .paragraph, .heading: prefixEnd = max(prefixEnd, first.range.lowerBound)
        default: break
        }
      }
      if prefixEnd > byteStart { indent = width(upTo: prefixEnd) }
    }
    out.decor.indent = (layout.flush ? 0 : indent) + quoteShift
    let isFirst = leaf.map { onLine($0.range) } ?? false
    let isLast = leaf.map { $0.range.upperBound >= byteStart && $0.range.upperBound <= byteEnd } ?? false
    let style = theme.paragraphStyle(lineHeight: layout.lineHeight, indent: indent + quoteShift + layout.inset, firstLineIndent: quoteShift + layout.inset,
      spacingBefore: isFirst ? layout.before : 0, spacingAfter: isLast ? layout.after : 0)
    s.addAttribute(.paragraphStyle, value: style, range: full)

    if !sourceMode, let row = path.first(where: { if case .tableRow = $0.kind { return true }; return false }) {
      // A table row being edited: links, code and markers get their colours; the font stays
      // monospaced so the pipes line up.
      for cell in row.children { styleInlines(inlines(of: cell), s: s, nsRange: nsRange, mark: mark, hide: nil, base: theme.code()) }
      s.addAttribute(.font, value: theme.code(), range: full)
    }
    if focusMode, !inFocus {
      s.addAttribute(.foregroundColor, value: Theme.marker, range: full)
    }
    return out
  }

  private func grid(for table: Block, width: CGFloat) -> TableGrid? {
    if gridCacheRevision != document.revision || gridCacheWidth != width {
      gridCache.removeAll(keepingCapacity: true)
      gridCacheRevision = document.revision
      gridCacheWidth = width
    }
    if let hit = gridCache[table.range] { return hit }
    let doc = document.markdown
    let renderer = AttributedRenderer(document: doc, theme: theme)
    let size = theme.baseSize * 0.95
    let grid = TableGrid(table: table, width: width, palette: theme.palette) { cell, header in
      renderer.inlines(doc.inlines(of: cell), font: header ? theme.body(weight: .semibold, size: size) : theme.body(size: size), color: Theme.text)
    }
    if let grid { gridCache[table.range] = grid }
    return grid
  }

  private func styleLeaf(_ leaf: Block, in path: [Block], s: NSMutableAttributedString, full: NSRange, byteStart: Int, byteEnd: Int, folded: Bool, out: inout Styled,
    nsRange: (Range<Int>) -> NSRange, mark: (Range<Int>, NSColor) -> Void, hide: @escaping (Range<Int>) -> Void) -> Layout
  {
    let doc = document.markdown
    let isFirstLine = leaf.range.lowerBound >= byteStart && leaf.range.lowerBound < byteEnd
    let isLastLine = leaf.range.upperBound >= byteStart && leaf.range.upperBound <= byteEnd
    let inlineHide: ((Range<Int>) -> Void)? = folded ? hide : nil
    func onLine(_ r: Range<Int>) -> Bool { r.lowerBound >= byteStart && r.lowerBound < byteEnd }
    func codeFont() { s.addAttribute(.font, value: theme.code(), range: full) }
    let codeLayout = Layout(lineHeight: theme.codeLineHeight, after: isLastLine ? theme.paragraphSpacing : 0)

    switch leaf.kind {
    case .heading(let level, let marker, let trailing, let underline):
      if !sourceMode { s.addAttribute(.font, value: theme.heading(level: level), range: full) }
      if let marker {
        if folded { hide(marker.lowerBound..<(leaf.lines.first?.range.lowerBound ?? marker.upperBound)) } else { mark(marker, Theme.marker) }
      }
      if let trailing { if folded { hide(trailing) } else { mark(trailing, Theme.marker) } }
      if let underline, underline.lowerBound >= byteStart {
        if folded { hide(underline); out.decor = Decor(kind: .hiddenLine, fixedHeight: 0) } else { mark(underline, Theme.marker) }
      }
      styleInlines(inlines(of: leaf), s: s, nsRange: nsRange, mark: mark, hide: inlineHide, base: theme.heading(level: level))
      return Layout(lineHeight: 1.25, before: sourceMode ? 0 : theme.headingSpacingBefore, after: theme.headingSpacingAfter)
    case .paragraph:
      let inlines = inlines(of: leaf)
      styleInlines(inlines, s: s, nsRange: nsRange, mark: mark, hide: inlineHide, base: nil)
      if !sourceMode {
        let images = Styler.imageSources(inlines)
        if !images.isEmpty {
          if isLastLine { out.overlay = .images(images.map { document.resolveImageURL($0) }) }
          // A paragraph that is only images shows the images in its place.
          if folded, Styler.isImagesOnly(inlines) { hide(byteStart..<byteEnd) }
        }
      }
      // Items of a tight list sit close together; the list's last paragraph keeps the usual gap.
      var after = theme.paragraphSpacing
      if let list = path.last(where: { if case .list = $0.kind { return true }; return false }), case .list(let info) = list.kind, info.tight, leaf.range.upperBound < list.range.upperBound {
        after = theme.listItemSpacing
      }
      return Layout(after: isLastLine ? after : 0)
    case .fencedCode(let fence):
      codeFont()
      let language = leaf.language(in: doc.bytes)
      if isFirstLine {
        if folded {
          hide(byteStart..<byteEnd)
          out.decor.fixedHeight = language == nil ? theme.codePadding : theme.codeHeader
        } else {
          mark(fence.open, Theme.marker)
          if let info = fence.info { mark(info, Theme.secondary) }
        }
      }
      if let close = fence.close, onLine(close) {
        if folded { hide(byteStart..<byteEnd); out.decor.fixedHeight = theme.codePadding } else { mark(close, Theme.marker) }
      }
      out.decor.kind = .codeBlock(first: isFirstLine, last: isLastLine, label: folded && isFirstLine ? language : nil)
      if !sourceMode {
        for token in highlight.tokens(for: leaf, in: document, intersecting: byteStart..<byteEnd) { mark(token.range, Theme.syntax(token.kind)) }
      }
      if isLastLine, !sourceMode, let lang = language?.lowercased() {
        if lang == "mermaid" { out.overlay = .mermaid(doc.text(of: leaf)) }
        else if ["math", "latex", "tex"].contains(lang) { out.overlay = .math(doc.text(of: leaf)) }
      }
      var layout = codeLayout
      layout.inset = theme.codeInset
      return layout
    case .indentedCode:
      codeFont()
      out.decor.kind = .codeBlock(first: isFirstLine, last: isLastLine, label: nil)
      var layout = codeLayout
      layout.flush = true
      return layout
    case .htmlBlock, .linkReferenceDefinition:
      codeFont()
      s.addAttribute(.foregroundColor, value: Theme.secondary, range: full)
      return codeLayout
    case .mathBlock(let open, let close):
      codeFont()
      if onLine(open) { mark(open, Theme.marker) }
      if let close, onLine(close) { mark(close, Theme.marker) }
      if isLastLine, !sourceMode { out.overlay = .math(doc.text(of: leaf)) }
      return codeLayout
    case .frontMatter(_, let open, let close):
      codeFont()
      s.addAttribute(.foregroundColor, value: Theme.secondary, range: full)
      if onLine(open) { mark(open, Theme.marker) }
      if let close, onLine(close) { mark(close, Theme.marker) }
      return codeLayout
    case .thematicBreak:
      out.decor.kind = .rule
      guard !folded else {
        hide(byteStart..<byteEnd)
        out.decor.fixedHeight = theme.ruleHeight
        return Layout()
      }
      s.addAttribute(.foregroundColor, value: Theme.marker, range: full)
      return Layout(before: theme.paragraphSpacing * 0.5, after: theme.paragraphSpacing)
    case .tableCell, .table, .tableRow:
      // The table block's rows are children; a line inside the table is styled as a whole row.
      codeFont()
      return codeLayout
    default:
      return Layout()
    }
  }

  private func styleInlines(_ inlines: [Inline], s: NSMutableAttributedString, nsRange: (Range<Int>) -> NSRange, mark: (Range<Int>, NSColor) -> Void, hide: ((Range<Int>) -> Void)?, base: NSFont?) {
    for node in inlines { styleInline(node, s: s, nsRange: nsRange, mark: mark, hide: hide, bold: false, italic: false, base: base) }
  }

  private func styleInline(_ node: Inline, s: NSMutableAttributedString, nsRange: (Range<Int>) -> NSRange, mark: (Range<Int>, NSColor) -> Void, hide: ((Range<Int>) -> Void)?, bold: Bool, italic: Bool, base: NSFont?) {
    let r = nsRange(node.range)
    var bold = bold, italic = italic
    func applyFont() {
      guard r.length > 0, bold || italic else { return }
      let size = (base ?? theme.body()).pointSize
      s.addAttribute(.font, value: theme.body(weight: bold ? .bold : .regular, size: size, italic: italic), range: r)
    }
    switch node.kind {
    case .emphasis: italic = true; applyFont()
    case .strong: bold = true; applyFont()
    case .code:
      if r.length > 0 { s.addAttributes([.font: theme.code(size: base?.pointSize), .inlineCode: true], range: r) }
    case .link, .image, .autolink, .extendedAutolink:
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
    case .hardBreak:
      if r.length > 0, !sourceMode { s.addAttribute(.hardBreak, value: true, range: r) }
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
