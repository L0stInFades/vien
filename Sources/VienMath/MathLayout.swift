import CoreGraphics
import CoreText
import Foundation

/// A typeset box: metrics plus a drawing closure. Origin for drawing is the left edge on the baseline
/// in a y-down context; the fill colour is whatever the context has when `draw` runs.
struct MathBox {
  var width: Double
  var ascent: Double
  var descent: Double
  var italicCorrection: Double = 0
  var atom: MathNode.Atom = .ord
  var draw: (CGContext, CGPoint) -> Void
  var height: Double { ascent + descent }

  static func empty(_ w: Double = 0) -> MathBox { MathBox(width: w, ascent: 0, descent: 0, draw: { _, _ in }) }
}

/// TeX-style box layout driven by the font's MATH constants.
struct MathLayout {
  let font: MathFont
  let baseSize: Double
  /// Font used for `\text{}` runs (the surrounding document's font).
  let textFont: CTFont
  /// Ink colour; boxes capture it so drawing needs nothing global.
  let color: CGColor

  init(font: MathFont = .shared, size: Double, color: CGColor) {
    self.font = font
    baseSize = size
    self.color = color
    textFont = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
  }

  struct Style {
    var level: MathNode.Style
    var cramped = false

    var isDisplay: Bool { level == .display }
    var sup: Style { Style(level: level == .display || level == .text ? .script : .scriptScript, cramped: cramped) }
    var sub: Style { Style(level: level == .display || level == .text ? .script : .scriptScript, cramped: true) }
    var fractionPart: Style { Style(level: level == .display ? .text : level == .text ? .script : .scriptScript, cramped: cramped) }
    var crampedStyle: Style { Style(level: level, cramped: true) }
    var isScript: Bool { level == .script || level == .scriptScript }
  }

  func size(_ s: Style) -> Double {
    switch s.level {
    case .display, .text: return baseSize
    case .script: return baseSize * font.constant(.scriptPercentScaleDown, size: 1) / 100
    case .scriptScript: return baseSize * font.constant(.scriptScriptPercentScaleDown, size: 1) / 100
    }
  }

  private func c(_ k: MathFont.C, _ s: Style) -> Double { font.constant(k, size: size(s)) }
  private func rule(_ s: Style) -> Double { max(0.6, c(.fractionRuleThickness, s)) }

  // MARK: - Entry

  func layout(_ node: MathNode, _ style: Style) -> MathBox {
    switch node {
    case .symbol(let s, let atom, let variant): return symbol(s, atom, variant, style)
    case .text(let s, let isOp):
      // Function names are set upright in the math font; `\text{}` uses the document font.
      return isOp ? symbol(s, .op, .upright, style) : text(s, isOperator: false, style)
    case .row(let items): return row(items, style)
    case .scripts(let base, let sub, let sup, let limits): return scripts(base, sub, sup, limits, style)
    case .fraction(let n, let d, let hasRule): return fraction(n, d, hasRule, style)
    case .root(let body, let index): return root(body, index, style)
    case .fenced(let l, let body, let r): return fenced(l, body, r, style)
    case .accent(let a, let body, let wide): return accent(a, body, wide, style)
    case .overline(let body): return overbar(body, style, over: true)
    case .underline(let body): return overbar(body, style, over: false)
    case .space(let em): return .empty(em * size(style))
    case .table(let rows, let env):
      if env.hasPrefix("bigdelim:"), let scale = Double(env.dropFirst(9)), let first = rows.first?.first { return bigDelimiter(first, scale: scale, style) }
      return table(rows, env, style)
    case .style(let level, let inner): return layout(inner, Style(level: level, cramped: style.cramped))
    case .boxed(let inner):
      let b = layout(inner, style)
      let pad = size(style) * 0.25
      let lw = rule(style)
      let color = self.color
      return MathBox(width: b.width + pad * 2, ascent: b.ascent + pad, descent: b.descent + pad, atom: .ord) { ctx, o in
        ctx.saveGState()
        ctx.setLineWidth(lw)
        ctx.setStrokeColor(color)
        ctx.stroke(CGRect(x: o.x + lw / 2, y: o.y - b.ascent - pad + lw / 2, width: b.width + pad * 2 - lw, height: b.height + pad * 2 - lw))
        ctx.restoreGState()
        b.draw(ctx, CGPoint(x: o.x + pad, y: o.y))
      }
    case .phantom(let inner, let keepWidth, let keepHeight):
      let b = layout(inner, style)
      return MathBox(width: keepWidth ? b.width : 0, ascent: keepHeight ? b.ascent : 0, descent: keepHeight ? b.descent : 0, atom: .ord) { _, _ in }
    case .error(let message):
      return text(message, isOperator: false, style)
    }
  }

  // MARK: - Glyphs

  private struct Glyph {
    var id: CGGlyph
    var metrics: MathFont.Metrics
  }

  private func glyph(for scalar: Unicode.Scalar, style: Style) -> Glyph? {
    guard let id = font.glyph(for: scalar) else { return nil }
    return Glyph(id: id, metrics: font.metrics(id, size: size(style)))
  }

  private func drawGlyph(_ id: CGGlyph, at origin: CGPoint, size: Double, transform extra: CGAffineTransform = .identity, in ctx: CGContext) {
    let scale = size / font.unit
    var t = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: origin.x, ty: origin.y)
    t = extra.concatenating(t)
    guard let path = CTFontCreatePathForGlyph(font.font, id, &t) else { return }
    ctx.addPath(path)
    ctx.fillPath()
  }

  private func symbol(_ s: String, _ atom: MathNode.Atom, _ variant: MathNode.Variant, _ style: Style) -> MathBox {
    // Map letters/digits/Greek to the Mathematical Alphanumeric block for the requested variant.
    var scalars: [Unicode.Scalar] = []
    for u in s.unicodeScalars { scalars.append(MathAlphabet.map(u, variant)) }
    var boxes: [(Glyph, Double)] = []
    var width: Double = 0, ascent: Double = 0, descent: Double = 0
    var ic: Double = 0
    let sz = size(style)
    for (i, u) in scalars.enumerated() {
      var g = glyph(for: u, style: style) ?? glyph(for: s.unicodeScalars[s.unicodeScalars.index(s.unicodeScalars.startIndex, offsetBy: min(i, s.unicodeScalars.count - 1))], style: style)
      guard var gl = g else { continue }
      // Large operators use their display variant in display style.
      if atom == .op, style.isDisplay, let v = font.variants(gl.id, vertical: true), let big = v.variants.dropFirst().first ?? v.variants.first, big.glyph != gl.id {
        gl = Glyph(id: big.glyph, metrics: font.metrics(big.glyph, size: sz))
      }
      g = gl
      // Combining marks (e.g. from `\not`) overprint the previous glyph.
      let combining = u.properties.generalCategory == .nonspacingMark || u.properties.generalCategory == .enclosingMark
      let advance = combining ? 0 : gl.metrics.advance
      let x = combining ? width - gl.metrics.advance : width
      boxes.append((gl, x))
      width += advance
      ascent = max(ascent, gl.metrics.bounds.maxY)
      descent = max(descent, -gl.metrics.bounds.minY)
      ic = font.italicCorrection(gl.id, size: sz)
    }
    // Large operator symbols sit centred on the math axis.
    var shift: Double = 0
    if atom == .op, style.isDisplay || style.level == .text, boxes.count == 1, scalars.count == 1, !(scalars[0].properties.isAlphabetic) {
      let axis = c(.axisHeight, style)
      let centre = (ascent - descent) / 2
      shift = axis - centre
      ascent += shift
      descent -= shift
    }
    let placed = boxes
    return MathBox(width: width, ascent: max(0, ascent), descent: max(0, descent), italicCorrection: ic, atom: atom) { ctx, o in
      for (g, x) in placed { drawGlyph(g.id, at: CGPoint(x: o.x + x, y: o.y - shift), size: sz, in: ctx) }
    }
  }

  private func text(_ s: String, isOperator: Bool, _ style: Style) -> MathBox {
    let f = CTFontCreateCopyWithAttributes(textFont, size(style), nil, nil)
    let attributed = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: f])
    let line = CTLineCreateWithAttributedString(attributed)
    var ascent: CGFloat = 0, descent: CGFloat = 0
    let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
    let colored = NSMutableAttributedString(attributedString: attributed)
    colored.addAttribute(kCTForegroundColorAttributeName as NSAttributedString.Key, value: color, range: NSRange(location: 0, length: colored.length))
    let coloredLine = CTLineCreateWithAttributedString(colored)
    return MathBox(width: width, ascent: ascent, descent: descent, atom: isOperator ? .op : .ord) { ctx, o in
      ctx.saveGState()
      ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
      ctx.textPosition = o
      CTLineDraw(coloredLine, ctx)
      ctx.restoreGState()
    }
  }

  // MARK: - Rows and spacing

  private func row(_ items: [MathNode], _ style: Style) -> MathBox {
    var boxes = items.map { layout($0, style) }
    guard !boxes.isEmpty else { return .empty() }
    // Binary operators without operands on both sides become ordinary (TeX rule 5).
    for i in boxes.indices where boxes[i].atom == .bin {
      let prev = i > 0 ? boxes[i - 1].atom : nil
      let next = i + 1 < boxes.count ? boxes[i + 1].atom : nil
      let prevOK = prev.map { ![.bin, .op, .rel, .open, .punct].contains($0) } ?? false
      let nextOK = next.map { ![.rel, .close, .punct].contains($0) } ?? false
      if !prevOK || !nextOK { boxes[i].atom = .ord }
    }
    var positions: [Double] = []
    var x: Double = 0
    let em = size(style)
    for i in boxes.indices {
      if i > 0 { x += spacing(boxes[i - 1].atom, boxes[i].atom, style) * em / 18 }
      positions.append(x)
      x += boxes[i].width
    }
    let ascent = boxes.map(\.ascent).max() ?? 0
    let descent = boxes.map(\.descent).max() ?? 0
    let first = boxes.first!.atom, last = boxes.last!
    let atom: MathNode.Atom = boxes.count == 1 ? first : .ord
    return MathBox(width: x, ascent: ascent, descent: descent, italicCorrection: last.italicCorrection, atom: atom) { ctx, o in
      for (b, px) in zip(boxes, positions) { b.draw(ctx, CGPoint(x: o.x + px, y: o.y)) }
    }
  }

  /// Inter-atom spacing in mu (18 mu = 1 em), following TeX's table.
  private func spacing(_ a: MathNode.Atom, _ b: MathNode.Atom, _ style: Style) -> Double {
    let script = style.isScript
    func cond(_ v: Double) -> Double { script ? 0 : v }
    switch (a, b) {
    case (.ord, .op), (.op, .ord), (.op, .op), (.close, .op), (.inner, .op): return 3
    case (.ord, .bin), (.bin, .ord), (.bin, .open), (.bin, .inner), (.close, .bin), (.inner, .bin): return cond(4)
    case (.ord, .rel), (.rel, .ord), (.rel, .open), (.rel, .inner), (.op, .rel), (.close, .rel), (.inner, .rel): return cond(5)
    case (.ord, .inner), (.op, .inner), (.close, .inner), (.inner, .ord), (.inner, .open), (.inner, .inner), (.inner, .punct): return cond(3)
    case (.punct, _): return cond(3)
    default: return 0
    }
  }

  // MARK: - Scripts

  private func scripts(_ baseNode: MathNode, _ subNode: MathNode?, _ supNode: MathNode?, _ limits: Bool, _ style: Style) -> MathBox {
    let base = layout(baseNode, style)
    let sub = subNode.map { layout($0, style.sub) }
    let sup = supNode.map { layout($0, style.sup) }
    let em = size(style)
    if limits && style.isDisplay {
      // Limits above and below, centred on the base.
      let gapUp = c(.upperLimitGapMin, style), riseUp = c(.upperLimitBaselineRiseMin, style)
      let gapDown = c(.lowerLimitGapMin, style), dropDown = c(.lowerLimitBaselineDropMin, style)
      let width = max(base.width, sup?.width ?? 0, sub?.width ?? 0)
      var ascent = base.ascent, descent = base.descent
      var supBaseline: Double = 0, subBaseline: Double = 0
      if let sup {
        supBaseline = -(max(base.ascent + gapUp + sup.descent, riseUp + sup.descent))
        ascent = -supBaseline + sup.ascent
      }
      if let sub {
        subBaseline = max(base.descent + gapDown + sub.ascent, dropDown + sub.ascent)
        descent = subBaseline + sub.descent
      }
      return MathBox(width: width, ascent: ascent, descent: descent, atom: base.atom) { ctx, o in
        base.draw(ctx, CGPoint(x: o.x + (width - base.width) / 2, y: o.y))
        if let sup { sup.draw(ctx, CGPoint(x: o.x + (width - sup.width) / 2, y: o.y + supBaseline)) }
        if let sub { sub.draw(ctx, CGPoint(x: o.x + (width - sub.width) / 2, y: o.y + subBaseline)) }
      }
    }
    // TeX Appendix G rules 18a–f, using MATH constants.
    var supShift = 0.0, subShift = 0.0
    // A tall large operator (∫, ∮…) positions its scripts by its own height, so they sit near the
    // top and bottom of the sign rather than cramped at the baseline like a plain symbol's do.
    let isLargeOp = base.atom == .op && (base.ascent + base.descent) > 1.5 * em
    let isSimple: Bool = { if case .symbol = baseNode { return true }; return false }() && !isLargeOp
    if !isSimple {
      supShift = base.ascent - c(.superscriptBaselineDropMax, style)
      subShift = base.descent + c(.subscriptBaselineDropMin, style)
    }
    if let sup {
      let minUp = style.cramped ? c(.superscriptShiftUpCramped, style) : c(.superscriptShiftUp, style)
      supShift = max(supShift, minUp, sup.descent + c(.superscriptBottomMin, style))
    }
    if let sub {
      subShift = max(subShift, c(.subscriptShiftDown, style), sub.ascent - c(.subscriptTopMax, style))
    }
    if let sup, let sub {
      let gap = (supShift - sup.descent) - (sub.ascent - subShift)
      let minGap = c(.subSuperscriptGapMin, style)
      if gap < minGap {
        subShift += minGap - gap
        let maxSupBottom = c(.superscriptBottomMaxWithSubscript, style)
        let excess = maxSupBottom - (supShift - sup.descent)
        if excess > 0 { supShift += excess; subShift -= excess }
      }
    }
    let supX = base.width
    let subX = base.width - base.italicCorrection
    let scriptSpace = c(.spaceAfterScript, style)
    let width = max(supX + (sup?.width ?? 0), subX + (sub?.width ?? 0)) + (sup != nil || sub != nil ? scriptSpace : 0)
    let ascent = max(base.ascent, sup.map { supShift + $0.ascent } ?? 0)
    let descent = max(base.descent, sub.map { subShift + $0.descent } ?? 0)
    _ = em
    return MathBox(width: width, ascent: ascent, descent: descent, atom: base.atom) { ctx, o in
      base.draw(ctx, o)
      if let sup { sup.draw(ctx, CGPoint(x: o.x + supX, y: o.y - supShift)) }
      if let sub { sub.draw(ctx, CGPoint(x: o.x + subX, y: o.y + subShift)) }
    }
  }

  // MARK: - Fractions

  private func fraction(_ n: MathNode, _ d: MathNode, _ hasRule: Bool, _ style: Style) -> MathBox {
    let num = layout(n, style.fractionPart)
    let den = layout(d, Style(level: style.fractionPart.level, cramped: true))
    let axis = c(.axisHeight, style)
    let thickness = hasRule ? rule(style) : 0
    let display = style.isDisplay
    var numShift = display ? c(.fractionNumeratorDisplayStyleShiftUp, style) : c(.fractionNumeratorShiftUp, style)
    var denShift = display ? c(.fractionDenominatorDisplayStyleShiftDown, style) : c(.fractionDenominatorShiftDown, style)
    let numGap = display ? c(.fractionNumDisplayStyleGapMin, style) : c(.fractionNumeratorGapMin, style)
    let denGap = display ? c(.fractionDenomDisplayStyleGapMin, style) : c(.fractionDenominatorGapMin, style)
    if hasRule {
      numShift = max(numShift, axis + thickness / 2 + numGap + num.descent)
      denShift = max(denShift, -axis + thickness / 2 + denGap + den.ascent)
    } else {
      let gap = display ? c(.stackDisplayStyleGapMin, style) : c(.stackGapMin, style)
      numShift = max(display ? c(.stackTopDisplayStyleShiftUp, style) : c(.stackTopShiftUp, style), numShift)
      denShift = max(display ? c(.stackBottomDisplayStyleShiftDown, style) : c(.stackBottomShiftDown, style), denShift)
      let actual = (numShift - num.descent) - (den.ascent - denShift)
      if actual < gap { let extra = (gap - actual) / 2; numShift += extra; denShift += extra }
    }
    let pad = size(style) * 0.1
    let width = max(num.width, den.width) + pad * 2
    return MathBox(width: width, ascent: numShift + num.ascent, descent: denShift + den.descent, atom: .inner) { ctx, o in
      num.draw(ctx, CGPoint(x: o.x + (width - num.width) / 2, y: o.y - numShift))
      den.draw(ctx, CGPoint(x: o.x + (width - den.width) / 2, y: o.y + denShift))
      if hasRule { ctx.fill(CGRect(x: o.x + pad / 2, y: o.y - axis - thickness / 2, width: width - pad, height: thickness)) }
    }
  }

  // MARK: - Radicals

  private func root(_ bodyNode: MathNode, _ indexNode: MathNode?, _ style: Style) -> MathBox {
    let body = layout(bodyNode, style.crampedStyle)
    let thickness = max(0.6, c(.radicalRuleThickness, style))
    let gap = style.isDisplay ? c(.radicalDisplayStyleVerticalGap, style) : c(.radicalVerticalGap, style)
    let extra = c(.radicalExtraAscender, style)
    let needed = body.height + gap + thickness
    let surd = stretched("√", height: needed, style: style, centreOnAxis: false)
    // Align the surd so its top meets the rule and its bottom reaches below the body.
    let ruleY = -(body.ascent + gap)  // relative to baseline (y down: negative = above)
    let surdTop = ruleY - thickness
    let surdShift = surdTop + surd.ascent  // move surd's baseline so that its top lands at surdTop
    let index = indexNode.map { layout($0, Style(level: .scriptScript, cramped: false)) }
    let kernBefore = c(.radicalKernBeforeDegree, style), kernAfter = c(.radicalKernAfterDegree, style)
    let indexWidth = index.map { max(0, kernBefore + $0.width + kernAfter) } ?? 0
    let width = indexWidth + surd.width + body.width + size(style) * 0.08
    let ascent = max(body.ascent + gap + thickness + extra, surd.ascent - surdShift)
    let descent = max(body.descent, surd.descent + surdShift)
    let raise = c(.radicalDegreeBottomRaisePercent, style) / 100
    return MathBox(width: width, ascent: ascent, descent: descent, atom: .ord) { ctx, o in
      if let index {
        let y = o.y - (surd.height * raise - surd.descent) + surdShift
        index.draw(ctx, CGPoint(x: o.x + kernBefore, y: y))
      }
      surd.draw(ctx, CGPoint(x: o.x + indexWidth, y: o.y + surdShift))
      let startX = o.x + indexWidth + surd.width
      ctx.fill(CGRect(x: startX - 0.5, y: o.y + surdTop, width: body.width + size(style) * 0.08 + 0.5, height: thickness))
      body.draw(ctx, CGPoint(x: startX, y: o.y))
    }
  }

  // MARK: - Delimiters

  private func fenced(_ left: String?, _ bodyNode: MathNode, _ right: String?, _ style: Style) -> MathBox {
    let body = layout(bodyNode, style)
    let axis = c(.axisHeight, style)
    let half = max(body.ascent - axis, body.descent + axis)
    let needed = max(half * 2, c(.delimitedSubFormulaMinHeight, style))
    let l = left.map { stretched($0, height: needed, style: style, centreOnAxis: true) }
    let r = right.map { stretched($0, height: needed, style: style, centreOnAxis: true) }
    let gap = size(style) * 0.05
    let width = (l?.width ?? 0) + body.width + (r?.width ?? 0) + gap * 2
    let ascent = max(body.ascent, l?.ascent ?? 0, r?.ascent ?? 0)
    let descent = max(body.descent, l?.descent ?? 0, r?.descent ?? 0)
    return MathBox(width: width, ascent: ascent, descent: descent, atom: .inner) { ctx, o in
      var x = o.x
      if let l { l.draw(ctx, CGPoint(x: x, y: o.y)); x += l.width }
      x += gap
      body.draw(ctx, CGPoint(x: x, y: o.y))
      x += body.width + gap
      if let r { r.draw(ctx, CGPoint(x: x, y: o.y)) }
    }
  }

  private func bigDelimiter(_ node: MathNode, scale: Double, _ style: Style) -> MathBox {
    guard case .symbol(let s, _, _) = node else { return layout(node, style) }
    let base = size(style)
    return stretched(s, height: base * 1.2 * scale, style: style, centreOnAxis: true)
  }

  /// A delimiter or radical glyph at least `height` tall, from the font's variants or an assembly,
  /// or scaled when the font offers neither.
  private func stretched(_ s: String, height: Double, style: Style, centreOnAxis: Bool) -> MathBox {
    let sz = size(style)
    guard let u = s.unicodeScalars.first, let base = glyph(for: u, style: style) else { return text(s, isOperator: false, style) }
    let axis = c(.axisHeight, style)
    func box(_ id: CGGlyph, metrics: MathFont.Metrics, extra: CGAffineTransform = .identity) -> MathBox {
      let b = metrics.bounds
      var shift: Double = 0
      if centreOnAxis { shift = axis - (b.maxY + b.minY) / 2 }
      return MathBox(width: metrics.advance, ascent: b.maxY + shift, descent: -b.minY - shift, atom: .open) { ctx, o in
        drawGlyph(id, at: CGPoint(x: o.x, y: o.y - shift), size: sz, transform: extra, in: ctx)
      }
    }
    let baseHeight = base.metrics.bounds.height
    // Slightly too-small delimiters are left alone rather than replaced by a visibly bigger variant.
    if baseHeight * 1.12 >= height { return box(base.id, metrics: base.metrics) }
    var largest: (CGGlyph, MathFont.Metrics) = (base.id, base.metrics)
    if let construction = font.variants(base.id, vertical: true) {
      for v in construction.variants {
        let m = font.metrics(v.glyph, size: sz)
        if m.bounds.height >= height { return box(v.glyph, metrics: m) }
        if m.bounds.height > largest.1.bounds.height { largest = (v.glyph, m) }
      }
      // Real top/middle/bottom assemblies extend cleanly; two-part "assemblies" are just a repeated bar.
      if construction.assembly.count >= 3 {
        return assembly(construction, height: height, style: style, centreOnAxis: centreOnAxis, advance: base.metrics.advance)
      }
    }
    // Scale the largest available shape vertically (bars, and fonts without variants).
    let (id, m) = largest
    let factor = height / max(1, m.bounds.height)
    var scaled = m
    scaled.bounds = CGRect(x: m.bounds.minX, y: m.bounds.minY * factor, width: m.bounds.width, height: m.bounds.height * factor)
    return box(id, metrics: scaled, extra: CGAffineTransform(scaleX: 1, y: factor))
  }

  private func assembly(_ construction: MathFont.Construction, height: Double, style: Style, centreOnAxis: Bool, advance: Double) -> MathBox {
    let sz = size(style)
    let unit = sz / font.unitsPerEm
    let minOverlap = font.minConnectorOverlap * unit
    // Expand extenders `repeats` times; parts are listed bottom to top.
    func expanded(_ repeats: Int) -> [MathFont.Part] {
      var out: [MathFont.Part] = []
      for p in construction.assembly { for _ in 0..<(p.isExtender ? repeats : 1) { out.append(p) } }
      return out
    }
    // Overlap between consecutive parts: as large as both connectors allow (closes any gaps).
    func overlaps(_ parts: [MathFont.Part]) -> [Double] {
      guard parts.count > 1 else { return [] }
      return (1..<parts.count).map { i in max(minOverlap, min(parts[i - 1].endConnector, parts[i].startConnector) * unit) }
    }
    func totalHeight(_ parts: [MathFont.Part]) -> Double {
      parts.map { $0.fullAdvance * unit }.reduce(0, +) - overlaps(parts).reduce(0, +)
    }
    var repeats = 1
    var parts = expanded(repeats)
    while totalHeight(parts) < height, repeats < 40 { repeats += 1; parts = expanded(repeats) }
    // Stretch the overlaps a little less than the maximum so the assembly meets the height exactly.
    let ov = overlaps(parts)
    let total = totalHeight(parts)
    let axis = c(.axisHeight, style)
    let shift = centreOnAxis ? axis - total / 2 : 0
    var width: Double = advance
    for p in parts { width = max(width, font.metrics(p.glyph, size: sz).advance) }
    return MathBox(width: width, ascent: total / 2 + shift, descent: total / 2 - shift, atom: .open) { ctx, o in
      var y = o.y + total / 2 - shift  // bottom edge (y down)
      for (i, p) in parts.enumerated() {
        let m = font.metrics(p.glyph, size: sz)
        // The glyph's advance box spans fullAdvance; place its bottom (baseline + descent) at y.
        drawGlyph(p.glyph, at: CGPoint(x: o.x, y: y + m.bounds.minY), size: sz, in: ctx)
        y -= p.fullAdvance * unit
        if i + 1 < parts.count { y += ov[i] }
      }
    }
  }

  // MARK: - Accents and bars

  private func accent(_ mark: String, _ bodyNode: MathNode, _ wide: Bool, _ style: Style) -> MathBox {
    let body = layout(bodyNode, style.crampedStyle)
    let sz = size(style)
    guard let u = mark.unicodeScalars.first, var g = glyph(for: u, style: style) else { return body }
    if wide, let construction = font.variants(g.id, vertical: false) {
      for v in construction.variants {
        let m = font.metrics(v.glyph, size: sz)
        g = Glyph(id: v.glyph, metrics: m)
        if m.bounds.width >= body.width * 0.9 { break }
      }
    }
    let baseHeight = c(.accentBaseHeight, style)
    let accentBottom = -g.metrics.bounds.minY  // combining marks sit above the x-height already
    let skew = font.topAccentAttachment(g.id, size: sz) ?? (g.metrics.bounds.midX)
    let bodyCentre = body.width / 2 + body.italicCorrection / 2
    let dy = max(0, body.ascent - baseHeight)  // raise the accent for tall bases
    let ascent = max(body.ascent, dy + g.metrics.bounds.maxY)
    let x = bodyCentre - skew
    _ = accentBottom
    return MathBox(width: body.width, ascent: ascent, descent: body.descent, italicCorrection: body.italicCorrection, atom: body.atom) { ctx, o in
      body.draw(ctx, o)
      drawGlyph(g.id, at: CGPoint(x: o.x + x, y: o.y - dy), size: sz, in: ctx)
    }
  }

  private func overbar(_ bodyNode: MathNode, _ style: Style, over: Bool) -> MathBox {
    let body = layout(bodyNode, over ? style.crampedStyle : style)
    let thickness = max(0.6, c(over ? .overbarRuleThickness : .underbarRuleThickness, style))
    let gap = c(over ? .overbarVerticalGap : .underbarVerticalGap, style)
    let extra = c(over ? .overbarExtraAscender : .underbarExtraDescender, style)
    let ascent = over ? body.ascent + gap + thickness + extra : body.ascent
    let descent = over ? body.descent : body.descent + gap + thickness + extra
    return MathBox(width: body.width, ascent: ascent, descent: descent, atom: .ord) { ctx, o in
      body.draw(ctx, o)
      let y = over ? o.y - body.ascent - gap - thickness : o.y + body.descent + gap
      ctx.fill(CGRect(x: o.x, y: y, width: body.width, height: thickness))
    }
  }

  // MARK: - Tables

  private func table(_ rows: [[MathNode]], _ env: String, _ style: Style) -> MathBox {
    let cellStyle = env == "aligned" || env == "align" || env == "split" || env == "gather" || env == "cases" ? style : Style(level: style.level == .display ? .text : style.level, cramped: style.cramped)
    let cells = rows.map { $0.map { layout($0, cellStyle) } }
    let cols = cells.map(\.count).max() ?? 0
    guard cols > 0 else { return .empty() }
    var colWidths = [Double](repeating: 0, count: cols)
    for r in cells { for (i, c) in r.enumerated() { colWidths[i] = max(colWidths[i], c.width) } }
    let em = size(style)
    let aligned = ["aligned", "align", "split", "alignat"].contains(env)
    let colGap = aligned ? 0.0 : env == "cases" ? em * 0.8 : em * 0.9
    let rowGap = em * (env == "cases" ? 0.35 : 0.3)
    let ascents = cells.map { $0.map(\.ascent).max() ?? 0 }
    let descents = cells.map { $0.map(\.descent).max() ?? 0 }
    var rowBaselines: [Double] = []
    var y: Double = 0
    for i in cells.indices {
      y += ascents[i]
      rowBaselines.append(y)
      y += descents[i] + (i + 1 < cells.count ? rowGap : 0)
    }
    let totalHeight = y
    var colX: [Double] = []
    var x: Double = 0
    for i in 0..<cols {
      colX.append(x)
      x += colWidths[i]
      if i + 1 < cols { x += aligned ? (i % 2 == 0 ? em * 0.15 : em * 1.5) : colGap }
    }
    let width = x
    let axis = c(.axisHeight, style)
    let ascent = totalHeight / 2 + axis
    let descent = totalHeight / 2 - axis
    return MathBox(width: width, ascent: ascent, descent: descent, atom: .inner) { ctx, o in
      let top = o.y - ascent
      for (ri, r) in cells.enumerated() {
        for (ci, cell) in r.enumerated() {
          var cx = o.x + colX[ci]
          if aligned { cx += ci % 2 == 0 ? colWidths[ci] - cell.width : 0 }
          else if env == "cases" { }
          else { cx += (colWidths[ci] - cell.width) / 2 }
          cell.draw(ctx, CGPoint(x: cx, y: top + rowBaselines[ri]))
        }
      }
    }
  }
}

/// Unicode Mathematical Alphanumeric Symbols mapping for font variants.
enum MathAlphabet {
  static func map(_ u: Unicode.Scalar, _ v: MathNode.Variant) -> Unicode.Scalar {
    let value = u.value
    func range(_ upper: UInt32, _ lower: UInt32) -> Unicode.Scalar? {
      if value >= 0x41 && value <= 0x5A { return Unicode.Scalar(upper + value - 0x41) }
      if value >= 0x61 && value <= 0x7A { return Unicode.Scalar(lower + value - 0x61) }
      return nil
    }
    func digits(_ base: UInt32) -> Unicode.Scalar? {
      if value >= 0x30 && value <= 0x39 { return Unicode.Scalar(base + value - 0x30) }
      return nil
    }
    switch v {
    case .upright: return u
    case .italic:
      if value == 0x68 { return "\u{210E}" }  // ℎ
      if let s = range(0x1D434, 0x1D44E) { return s }
      if value >= 0x3B1 && value <= 0x3C9 { return Unicode.Scalar(0x1D6FC + value - 0x3B1)! }  // greek lowercase italic
      if value == 0x3D5 { return "\u{1D719}" }  // ϕ
      if value == 0x3F5 { return "\u{1D716}" }  // ϵ
      if value == 0x3D1 { return "\u{1D717}" }  // ϑ
      if value == 0x3C6 { return "\u{1D711}" }  // φ
      if value == 0x3F1 { return "\u{1D71A}" }
      if value == 0x3D6 { return "\u{1D71B}" }
      if value == 0x2202 { return "\u{1D715}" }  // ∂
      return u
    case .bold:
      if let s = range(0x1D400, 0x1D41A) ?? digits(0x1D7CE) { return s }
      if value >= 0x3B1 && value <= 0x3C9 { return Unicode.Scalar(0x1D6C2 + value - 0x3B1)! }
      if value >= 0x391 && value <= 0x3A9 { return Unicode.Scalar(0x1D6A8 + value - 0x391)! }
      return u
    case .boldItalic:
      if let s = range(0x1D468, 0x1D482) { return s }
      if value >= 0x3B1 && value <= 0x3C9 { return Unicode.Scalar(0x1D736 + value - 0x3B1)! }
      if value >= 0x391 && value <= 0x3A9 { return Unicode.Scalar(0x1D71C + value - 0x391)! }
      return u
    case .doubleStruck:
      let exceptions: [UInt32: UInt32] = [0x43: 0x2102, 0x48: 0x210D, 0x4E: 0x2115, 0x50: 0x2119, 0x51: 0x211A, 0x52: 0x211D, 0x5A: 0x2124]
      if let e = exceptions[value] { return Unicode.Scalar(e)! }
      return range(0x1D538, 0x1D552) ?? digits(0x1D7D8) ?? u
    case .script:
      let exceptions: [UInt32: UInt32] = [0x42: 0x212C, 0x45: 0x2130, 0x46: 0x2131, 0x48: 0x210B, 0x49: 0x2110, 0x4C: 0x2112, 0x4D: 0x2133, 0x52: 0x211B, 0x65: 0x212F, 0x67: 0x210A, 0x6F: 0x2134]
      if let e = exceptions[value] { return Unicode.Scalar(e)! }
      return range(0x1D49C, 0x1D4B6) ?? u
    case .fraktur:
      let exceptions: [UInt32: UInt32] = [0x43: 0x212D, 0x48: 0x210C, 0x49: 0x2111, 0x52: 0x211C, 0x5A: 0x2128]
      if let e = exceptions[value] { return Unicode.Scalar(e)! }
      return range(0x1D504, 0x1D51E) ?? u
    case .sans: return range(0x1D5A0, 0x1D5BA) ?? digits(0x1D7E2) ?? u
    case .mono: return range(0x1D670, 0x1D68A) ?? digits(0x1D7F6) ?? u
    }
  }
}
