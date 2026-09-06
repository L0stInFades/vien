import AppKit
import CoreText
import VienMarkdown

/// A table laid out as a grid of wrapped cells: what a table looks like while the caret is elsewhere.
/// Column widths come from the cells' natural widths, shrunk proportionally to fit the content width.
/// Immutable once built; CTFramesetter and NSColor reads are thread-safe, hence @unchecked.
nonisolated struct TableGrid: @unchecked Sendable {
  struct Cell {
    var frame: CGRect  // grid coordinates, y down
    let framesetter: CTFramesetter
    let textHeight: CGFloat
  }

  let size: CGSize
  let columnEdges: [CGFloat]
  let rowEdges: [CGFloat]
  let cells: [[Cell]]
  /// Source byte range of every cell, so a click can put the caret into it.
  let sources: [[Range<Int>]]

  let palette: Palette

  static let padX: CGFloat = 12
  static let padY: CGFloat = 8
  static let minColumn: CGFloat = 64

  init?(table: Block, width: CGFloat, palette: Palette, attributed: (Block, Bool) -> NSAttributedString) {
    guard case .table(let info) = table.kind, !info.alignments.isEmpty else { return nil }
    self.palette = palette
    let columns = info.alignments.count
    var strings: [[NSAttributedString]] = []
    var sources: [[Range<Int>]] = []
    for (r, row) in table.children.enumerated() {
      var line: [NSAttributedString] = []
      var src: [Range<Int>] = []
      for c in 0..<columns {
        let cell = c < row.children.count ? row.children[c] : nil
        let text = NSMutableAttributedString(attributedString: cell.map { attributed($0, r == 0) } ?? NSAttributedString())
        let style = NSMutableParagraphStyle()
        switch info.alignments[c] {
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        default: style.alignment = .left
        }
        style.lineBreakMode = .byWordWrapping
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        line.append(text)
        src.append(cell?.range ?? (row.range.upperBound..<row.range.upperBound))
      }
      strings.append(line)
      sources.append(src)
    }
    var natural = [CGFloat](repeating: Self.minColumn, count: columns)
    for row in strings {
      for (c, s) in row.enumerated() where s.length > 0 {
        let line = CTLineCreateWithAttributedString(s)
        natural[c] = max(natural[c], ceil(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))) + 2 * Self.padX)
      }
    }
    // Columns keep their natural width while it fits an equal share of the space; only the wide
    // ones wrap, sharing what is left in proportion. Very wide tables shrink below the usual
    // minimum rather than run off the page.
    let minColumn = min(Self.minColumn, max(24, floor(width / Double(columns))))
    var widths = natural
    if natural.reduce(0, +) > width {
      var flexible = Set(natural.indices)
      var remaining = width
      while !flexible.isEmpty {
        let share = remaining / CGFloat(flexible.count)
        let settled = flexible.filter { natural[$0] <= share }
        if settled.isEmpty {
          let total = flexible.reduce(0) { $0 + natural[$1] }
          for i in flexible { widths[i] = max(minColumn, floor(natural[i] * remaining / max(1, total))) }
          break
        }
        for i in settled { widths[i] = natural[i]; remaining -= natural[i]; flexible.remove(i) }
      }
    }
    var cells: [[Cell]] = []
    var rowHeights: [CGFloat] = []
    for row in strings {
      var line: [Cell] = []
      var height: CGFloat = 0
      for (c, s) in row.enumerated() {
        let framesetter = CTFramesetterCreateWithAttributedString(s)
        var textHeight: CGFloat = 0
        if s.length > 0 {
          let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, CGSize(width: widths[c] - 2 * Self.padX, height: 10_000), nil)
          textHeight = ceil(fit.height)
        }
        height = max(height, textHeight)
        line.append(Cell(frame: .zero, framesetter: framesetter, textHeight: textHeight))
      }
      rowHeights.append(max(height, 18) + 2 * Self.padY)
      cells.append(line)
    }
    var xs: [CGFloat] = [0]
    for w in widths { xs.append(xs[xs.count - 1] + w) }
    var ys: [CGFloat] = [0]
    for h in rowHeights { ys.append(ys[ys.count - 1] + h) }
    for r in cells.indices {
      for c in cells[r].indices { cells[r][c].frame = CGRect(x: xs[c], y: ys[r], width: widths[c], height: rowHeights[r]) }
    }
    size = CGSize(width: xs[xs.count - 1], height: ys[ys.count - 1])
    columnEdges = xs
    rowEdges = ys
    self.cells = cells
    self.sources = sources
  }

  func cell(at p: CGPoint) -> (row: Int, column: Int)? {
    guard p.x >= 0, p.y >= 0, p.x <= size.width, p.y <= size.height else { return nil }
    let r = max(0, (rowEdges.firstIndex { $0 > p.y } ?? rowEdges.count) - 1)
    let c = max(0, (columnEdges.firstIndex { $0 > p.x } ?? columnEdges.count) - 1)
    guard r < cells.count, c < cells[r].count else { return nil }
    return (r, c)
  }

  /// Draws into a flipped (y down) context with the grid's top-left corner at `origin`.
  func draw(at origin: CGPoint, in ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    if rowEdges.count > 1 {
      ctx.setFillColor(palette.codeBackground.cgColor)
      ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: rowEdges[1]))
    }
    ctx.setStrokeColor(palette.rule.cgColor)
    ctx.setLineWidth(1)
    for x in columnEdges {
      ctx.move(to: CGPoint(x: x.rounded() + 0.5, y: 0))
      ctx.addLine(to: CGPoint(x: x.rounded() + 0.5, y: size.height))
    }
    for y in rowEdges {
      ctx.move(to: CGPoint(x: 0, y: y.rounded() + 0.5))
      ctx.addLine(to: CGPoint(x: size.width, y: y.rounded() + 0.5))
    }
    ctx.strokePath()
    for row in cells {
      for cell in row where cell.textHeight > 0 {
        let rect = cell.frame.insetBy(dx: Self.padX, dy: Self.padY)
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY + cell.textHeight)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: cell.textHeight), transform: nil)
        let frame = CTFramesetterCreateFrame(cell.framesetter, CFRange(), path, nil)
        drawInlineCode(in: frame, ctx: ctx)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
      }
    }
    ctx.restoreGState()
  }

  /// Rounded boxes under inline code runs of a laid-out frame (y up, as CTFrameDraw expects).
  private func drawInlineCode(in frame: CTFrame, ctx: CGContext) {
    let lines = CTFrameGetLines(frame) as! [CTLine]
    var origins = [CGPoint](repeating: .zero, count: lines.count)
    CTFrameGetLineOrigins(frame, CFRange(), &origins)
    for (line, origin) in zip(lines, origins) {
      for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        guard (CTRunGetAttributes(run) as NSDictionary)[NSAttributedString.Key.inlineCode] != nil else { continue }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        CTRunGetTypographicBounds(run, CFRange(), &ascent, &descent, nil)
        let r = CTRunGetStringRange(run)
        let x0 = CTLineGetOffsetForStringIndex(line, r.location, nil), x1 = CTLineGetOffsetForStringIndex(line, r.location + r.length, nil)
        ctx.addPath(CGPath(roundedRect: CGRect(x: origin.x + x0 - 2, y: origin.y - descent - 1, width: x1 - x0 + 4, height: ascent + descent + 2), cornerWidth: 3, cornerHeight: 3, transform: nil))
      }
    }
    ctx.setFillColor(palette.codeBackground.cgColor)
    ctx.fillPath()
  }
}

/// The first row of a folded table: its (hidden) text line plus the whole grid beneath it.
/// The grid is fetched for the container's current width, so it follows window resizes.
nonisolated final class TableFragment: MarkdownFragment {
  private let table: Block
  private let provider: (Block, CGFloat) -> TableGrid?
  private let initialWidth: CGFloat
  /// Container indent (list marker, quote bars) the grid sits under.
  let indent: CGFloat
  let bottomPadding: CGFloat

  init(textElement: NSTextElement, range: NSTextRange?, table: Block, width: CGFloat, indent: CGFloat, decor: Decor, palette: Palette, bottomPadding: CGFloat, provider: @escaping (Block, CGFloat) -> TableGrid?) {
    self.table = table
    self.provider = provider
    self.initialWidth = width
    self.indent = indent
    self.bottomPadding = bottomPadding
    super.init(textElement: textElement, range: range, decor: decor, palette: palette)
  }

  required init?(coder: NSCoder) { fatalError() }

  var grid: TableGrid? {
    let width = (textLayoutManager?.textContainer?.size.width ?? initialWidth) - indent - 4
    nonisolated(unsafe) let me = self
    return MainActor.assumeIsolated { me.provider(me.table, width) }
  }

  /// Where the grid sits, relative to the fragment's origin.
  var gridOrigin: CGPoint { CGPoint(x: indent, y: baseHeight) }

  override var layoutFragmentFrame: CGRect {
    var f = super.layoutFragmentFrame
    f.size.height += (grid?.size.height ?? 0) + bottomPadding
    return f
  }

  override var renderingSurfaceBounds: CGRect {
    var b = super.renderingSurfaceBounds
    b.size.height += (grid?.size.height ?? 0) + bottomPadding
    b.size.width = max(b.size.width, indent + (grid?.size.width ?? 0) + 2)
    return b
  }

  override func draw(at point: CGPoint, in ctx: CGContext) {
    super.draw(at: point, in: ctx)
    grid?.draw(at: CGPoint(x: point.x + gridOrigin.x, y: point.y + gridOrigin.y), in: ctx)
  }
}
