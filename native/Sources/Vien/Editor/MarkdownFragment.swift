import AppKit
import CoreText
import VienMarkdown

extension NSAttributedString.Key {
  /// Marks an inline code span; its fragment draws a rounded box beneath it.
  nonisolated static let inlineCode = NSAttributedString.Key("vien.inlineCode")
}

/// What a paragraph's fragment draws besides its text, decided by the styler line by line.
nonisolated struct Decor {
  enum Kind {
    case none
    case rule
    /// `label` is the language tag shown in the header strip of a folded fence.
    case codeBlock(first: Bool, last: Bool, label: String?)
    /// The first line of a folded table; the grid hangs beneath it.
    case table(Block, indent: CGFloat)
    /// A folded line that shows nothing (the other rows of a table, a setext underline).
    case hiddenLine
  }

  struct Bullet {
    /// UTF-16 index of the source marker, kept transparent so the glyph can sit on it.
    var index: Int
    var glyph: String
  }

  var kind: Kind = .none
  /// Left edges of the block-quote bars this line sits inside.
  var quoteBars: [CGFloat] = []
  var bullet: Bullet?
  /// Height of a line whose text is folded away (fence lines, `---`), spacing excluded.
  var fixedHeight: CGFloat?
  /// Where the enclosing containers end and the block's own box begins.
  var indent: CGFloat = 0

  static func bulletGlyph(depth: Int) -> String { ["•", "◦", "▪"][max(0, min(2, depth - 1))] }
}

/// Lays out and draws one paragraph: its text plus what the Markdown structure adds around it
/// (quote bars, a code background with its language tag, a rule, a bullet, boxes under inline
/// code). A line whose markup is folded away takes the height its decoration needs instead.
nonisolated class MarkdownFragment: NSTextLayoutFragment {
  let decor: Decor
  let palette: Palette
  let text: NSAttributedString?
  /// Paragraph spacing is part of the fragment's frame; TextKit asks for the frame constantly.
  let spacingBefore: CGFloat
  let spacingAfter: CGFloat
  static let bleed: CGFloat = 6
  static let radius: CGFloat = 6

  init(textElement: NSTextElement, range: NSTextRange?, decor: Decor, palette: Palette) {
    self.decor = decor
    self.palette = palette
    text = (textElement as? NSTextParagraph)?.attributedString
    let style = text.flatMap { $0.length > 0 ? $0.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil }
    spacingBefore = style?.paragraphSpacingBefore ?? 0
    spacingAfter = style?.paragraphSpacing ?? 0
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) { fatalError() }

  var containerWidth: CGFloat { textLayoutManager?.textContainer?.size.width ?? super.layoutFragmentFrame.width }

  /// The height of the line itself (before any overlay): the text's, or the folded decoration's.
  var baseHeight: CGFloat {
    guard let fixed = decor.fixedHeight else { return super.layoutFragmentFrame.height }
    return fixed + spacingBefore + spacingAfter
  }

  override var layoutFragmentFrame: CGRect {
    var f = super.layoutFragmentFrame
    f.size.height = baseHeight
    return f
  }

  override var renderingSurfaceBounds: CGRect {
    let b = super.renderingSurfaceBounds
    let minX = min(b.minX, -Self.bleed - layoutFragmentFrame.minX), maxX = max(b.maxX, containerWidth + Self.bleed)
    return CGRect(x: minX, y: min(b.minY, 0), width: maxX - minX, height: max(b.maxY, baseHeight + Self.radius) - min(b.minY, 0))
  }

  override func draw(at point: CGPoint, in ctx: CGContext) {
    if case .hiddenLine = decor.kind { return }
    ctx.saveGState()
    defer { ctx.restoreGState() }
    let height = baseHeight
    let width = containerWidth
    // TextKit places the fragment at its first line's head indent; blocks are drawn from the container edge.
    let left = point.x - layoutFragmentFrame.minX
    // Strips of adjacent lines meet on device pixels: translucent fills would show every seam or overlap.
    let scale = abs(ctx.ctm.a)
    func snapped(_ top: CGFloat, _ bottom: CGFloat) -> (CGFloat, CGFloat) { ((top * scale).rounded() / scale, (bottom * scale).rounded() / scale) }
    switch decor.kind {
    case .codeBlock(let first, let last, let label):
      let (top, bottom) = snapped(point.y + (first ? spacingBefore : 0), point.y + height - (last ? spacingAfter : 0))
      let rect = CGRect(x: left + decor.indent - Self.bleed, y: top, width: width - decor.indent + 2 * Self.bleed, height: bottom - top)
      ctx.setFillColor(palette.codeBackground.cgColor)
      ctx.addPath(Self.roundedPath(rect, radius: Self.radius, top: first, bottom: last))
      ctx.fillPath()
      if let label, let fixed = decor.fixedHeight {
        let size = (fixed * 0.5).rounded()
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: palette.secondary]))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        Self.drawLine(line, at: CGPoint(x: rect.maxX - Self.bleed - size - w, y: rect.minY + (fixed + size * 0.7) / 2), in: ctx)
      }
    case .rule:
      ctx.setStrokeColor(palette.rule.cgColor)
      ctx.setLineWidth(1)
      var y = spacingBefore + (decor.fixedHeight ?? 0) / 2
      if decor.fixedHeight == nil, let line = textLineFragments.first, line.attributedString.length > 0,
        let font = line.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
      {
        // Through the middle of the marker's dashes: a hyphen sits about half an x-height up.
        y = line.typographicBounds.minY + line.glyphOrigin.y - font.xHeight / 2
      }
      y = (point.y + y).rounded() + 0.5
      ctx.move(to: CGPoint(x: left + decor.indent, y: y))
      ctx.addLine(to: CGPoint(x: left + width, y: y))
      ctx.strokePath()
      if decor.fixedHeight == nil { ctx.setAlpha(0.35) }  // the dashes stay editable but recede
    case .none, .table, .hiddenLine:
      break
    }
    ctx.setFillColor(palette.rule.cgColor)
    let (barTop, barBottom) = snapped(point.y, point.y + layoutFragmentFrame.height)
    for x in decor.quoteBars { ctx.fill(CGRect(x: left + x, y: barTop, width: 3, height: barBottom - barTop)) }
    drawInlineCode(at: point, in: ctx)
    super.draw(at: point, in: ctx)
    if let bullet = decor.bullet { drawBullet(bullet, at: point, in: ctx) }
  }

  /// Rounded boxes under inline code spans, sized from the span's own font.
  private func drawInlineCode(at point: CGPoint, in ctx: CGContext) {
    guard let text, text.length > 0 else { return }
    for line in textLineFragments {
      text.enumerateAttribute(.inlineCode, in: line.characterRange) { value, run, _ in
        guard value != nil, let font = text.attribute(.font, at: run.location, effectiveRange: nil) as? NSFont else { return }
        let x0 = line.locationForCharacter(at: run.location).x, x1 = line.locationForCharacter(at: NSMaxRange(run)).x
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        let rect = CGRect(x: point.x + line.typographicBounds.minX + x0 - 2, y: point.y + baseline - font.ascender - 1, width: x1 - x0 + 4, height: font.ascender - font.descender + 2)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
      }
    }
    ctx.setFillColor(palette.codeBackground.cgColor)
    ctx.fillPath()
  }

  /// The bullet glyph, centred on the transparent source marker at the marker's own baseline.
  private func drawBullet(_ bullet: Decor.Bullet, at point: CGPoint, in ctx: CGContext) {
    guard let text, bullet.index < text.length, let line = textLineFragments.first(where: { NSLocationInRange(bullet.index, $0.characterRange) }),
      let font = text.attribute(.font, at: bullet.index, effectiveRange: nil) as? NSFont
    else { return }
    let x0 = line.locationForCharacter(at: bullet.index).x, x1 = line.locationForCharacter(at: bullet.index + 1).x
    let glyph = CTLineCreateWithAttributedString(NSAttributedString(string: bullet.glyph, attributes: [.font: font, .foregroundColor: palette.text]))
    let w = CTLineGetTypographicBounds(glyph, nil, nil, nil)
    let x = point.x + line.typographicBounds.minX + (x0 + x1 - w) / 2
    Self.drawLine(glyph, at: CGPoint(x: x, y: point.y + line.typographicBounds.minY + line.glyphOrigin.y), in: ctx)
  }

  /// Draws a Core Text line with its baseline origin at `origin` in a flipped (y down) context.
  static func drawLine(_ line: CTLine, at origin: CGPoint, in ctx: CGContext) {
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = origin
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  /// A rectangle whose top and/or bottom corners are rounded (y down).
  static func roundedPath(_ r: CGRect, radius: CGFloat, top: Bool, bottom: Bool) -> CGPath {
    let p = CGMutablePath()
    let t = top ? radius : 0, b = bottom ? radius : 0
    p.move(to: CGPoint(x: r.minX + t, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + t), radius: t)
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - b, y: r.maxY), radius: b)
    p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - b), radius: b)
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + t))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + t, y: r.minY), radius: t)
    p.closeSubpath()
    return p
  }
}
