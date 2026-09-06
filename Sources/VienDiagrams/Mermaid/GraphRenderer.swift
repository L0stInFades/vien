import CoreGraphics
import Foundation

/// Draws a laid-out `GraphDiagram` (flowchart / class / state) on any canvas.
struct GraphRenderer {
  let diagram: GraphDiagram
  let theme: DiagramTheme
  let padding: Double = 12
  let nodePaddingX: Double = 14
  let nodePaddingY: Double = 9

  private(set) var nodeSizes: [String: CGSize] = [:]
  private(set) var labelSizes: [Int: CGSize] = [:]
  private(set) var layout = GraphLayout.Result()

  init(diagram: GraphDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    measure()
    var gl = GraphLayout(diagram: diagram, nodeSizes: nodeSizes, labelSizes: labelSizes)
    gl.nodeSep = 40
    layout = gl.run()
  }

  var size: CGSize {
    CGSize(width: layout.size.width + padding * 2, height: layout.size.height + padding * 2 + (diagram.title == nil ? 0 : 28))
  }

  private var contentOffset: CGPoint { CGPoint(x: padding, y: padding + (diagram.title == nil ? 0 : 28)) }

  // MARK: - Measurement

  private mutating func measure() {
    for n in diagram.nodes {
      nodeSizes[n.id] = nodeSize(n)
    }
    for (i, e) in diagram.edges.enumerated() {
      if let l = e.label, !l.isEmpty { labelSizes[i] = TextMetrics.measure(l, style: theme.style(theme.fontSize - 1)) }
    }
  }

  private func nodeSize(_ n: GraphDiagram.Node) -> CGSize {
    switch n.shape {
    case .start: return CGSize(width: 16, height: 16)
    case .end: return CGSize(width: 18, height: 18)
    case .classBox:
      var w: Double = 60, h: Double = 0
      for (i, comp) in n.compartments.enumerated() {
        let style = i == 0 ? theme.style(weight: .semibold) : theme.style(theme.fontSize - 1, mono: false)
        let text = comp.joined(separator: "\n")
        let s = TextMetrics.measure(text.isEmpty ? " " : text, style: style)
        w = max(w, s.width)
        h += s.height + 8
      }
      return CGSize(width: w + nodePaddingX * 2, height: h)
    default:
      let s = TextMetrics.measure(n.label.isEmpty ? " " : n.label, style: theme.style())
      var w = s.width + nodePaddingX * 2, h = s.height + nodePaddingY * 2
      switch n.shape {
      case .circle, .doubleCircle:
        let d = max(w, h) + (n.shape == .doubleCircle ? 8 : 0)
        return CGSize(width: d, height: d)
      case .diamond: w = s.width * 1.5 + 24; h = s.height * 1.5 + 20
      case .hexagon, .asymmetric, .cylinder: w += 18
      case .parallelogram, .parallelogramAlt, .trapezoid, .trapezoidAlt: w += 28
      case .stadium: w += 10
      case .subroutine: w += 16
      case .note: w += 8; h += 4
      default: break
      }
      if n.shape == .cylinder { h += 14 }
      return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }
  }

  // MARK: - Drawing

  func draw<C: Canvas>(on canvas: inout C) {
    let off = contentOffset
    if let title = diagram.title {
      canvas.text(title, at: CGPoint(x: 0, y: 6), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold))
    }
    // Clusters, outermost first.
    let ordered = diagram.clusters.sorted { depth($0) < depth($1) }
    for c in ordered {
      guard let r = layout.clusterRects[c.id]?.offsetBy(dx: off.x, dy: off.y) else { continue }
      let style = c.style
      canvas.rect(r, radius: 8, fill: style?.fill ?? theme.clusterFill, stroke: Stroke(color: style?.stroke ?? theme.clusterStroke, width: style?.strokeWidth ?? 1, dash: style?.dashed == true ? [4, 3] : []))
      if let t = c.title {
        canvas.text(t, at: CGPoint(x: r.minX, y: r.minY + 4), width: r.width, align: .center, style: theme.style(theme.fontSize - 1, weight: .semibold, color: style?.color ?? theme.secondaryText))
      }
    }
    for (i, e) in diagram.edges.enumerated() where e.line != .invisible {
      drawEdge(i, e, on: &canvas, offset: off)
    }
    for n in diagram.nodes {
      guard let r = layout.nodeRects[n.id]?.offsetBy(dx: off.x, dy: off.y) else { continue }
      drawNode(n, in: r, on: &canvas)
    }
  }

  private func depth(_ c: GraphDiagram.Cluster) -> Int {
    var d = 0
    var p = c.parent
    while let id = p { d += 1; p = diagram.clusters.first { $0.id == id }?.parent }
    return d
  }

  private func drawNode<C: Canvas>(_ n: GraphDiagram.Node, in r: CGRect, on canvas: inout C) {
    let style = diagram.effectiveStyle(n)
    let fill = style?.fill ?? theme.nodeFill
    let stroke = Stroke(color: style?.stroke ?? theme.nodeStroke, width: style?.strokeWidth ?? 1, dash: style?.dashed == true ? [4, 3] : [])
    let textStyle = theme.style(color: style?.color)
    let labelSize = TextMetrics.measure(n.label.isEmpty ? " " : n.label, style: textStyle)
    let textOrigin = CGPoint(x: r.minX, y: r.midY - labelSize.height / 2)
    switch n.shape {
    case .rect:
      canvas.rect(r, radius: 3, fill: fill, stroke: stroke)
    case .rounded, .note:
      canvas.rect(r, radius: n.shape == .note ? 4 : 8, fill: n.shape == .note ? theme.noteFill : fill, stroke: n.shape == .note ? Stroke(color: theme.noteStroke) : stroke)
    case .stadium:
      canvas.rect(r, radius: r.height / 2, fill: fill, stroke: stroke)
    case .subroutine:
      canvas.rect(r, radius: 0, fill: fill, stroke: stroke)
      canvas.line(CGPoint(x: r.minX + 6, y: r.minY), CGPoint(x: r.minX + 6, y: r.maxY), stroke: stroke)
      canvas.line(CGPoint(x: r.maxX - 6, y: r.minY), CGPoint(x: r.maxX - 6, y: r.maxY), stroke: stroke)
    case .cylinder:
      let ry: Double = 7
      let body = CGRect(x: r.minX, y: r.minY + ry, width: r.width, height: r.height - ry * 2)
      canvas.rect(body, radius: 0, fill: fill, stroke: nil)
      canvas.line(CGPoint(x: r.minX, y: r.minY + ry), CGPoint(x: r.minX, y: r.maxY - ry), stroke: stroke)
      canvas.line(CGPoint(x: r.maxX, y: r.minY + ry), CGPoint(x: r.maxX, y: r.maxY - ry), stroke: stroke)
      canvas.ellipse(in: CGRect(x: r.minX, y: r.maxY - ry * 2, width: r.width, height: ry * 2), fill: fill, stroke: stroke)
      canvas.rect(CGRect(x: r.minX + stroke.width, y: r.minY + ry, width: r.width - stroke.width * 2, height: r.height - ry * 3), radius: 0, fill: fill, stroke: nil)
      canvas.ellipse(in: CGRect(x: r.minX, y: r.minY, width: r.width, height: ry * 2), fill: fill, stroke: stroke)
    case .circle:
      canvas.ellipse(in: r, fill: fill, stroke: stroke)
    case .doubleCircle:
      canvas.ellipse(in: r, fill: fill, stroke: stroke)
      canvas.ellipse(in: r.insetBy(dx: 4, dy: 4), fill: nil, stroke: stroke)
    case .asymmetric:
      let k: Double = 12
      canvas.polygon([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX + k, y: r.midY)], fill: fill, stroke: stroke)
    case .diamond:
      canvas.polygon([CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)], fill: fill, stroke: stroke)
    case .hexagon:
      let k = min(14, r.height / 2)
      canvas.polygon([CGPoint(x: r.minX + k, y: r.minY), CGPoint(x: r.maxX - k, y: r.minY), CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX - k, y: r.maxY), CGPoint(x: r.minX + k, y: r.maxY), CGPoint(x: r.minX, y: r.midY)], fill: fill, stroke: stroke)
    case .parallelogram:
      let k: Double = 14
      canvas.polygon([CGPoint(x: r.minX + k, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX - k, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)], fill: fill, stroke: stroke)
    case .parallelogramAlt:
      let k: Double = 14
      canvas.polygon([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX - k, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX + k, y: r.maxY)], fill: fill, stroke: stroke)
    case .trapezoid:
      let k: Double = 14
      canvas.polygon([CGPoint(x: r.minX + k, y: r.minY), CGPoint(x: r.maxX - k, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)], fill: fill, stroke: stroke)
    case .trapezoidAlt:
      let k: Double = 14
      canvas.polygon([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX - k, y: r.maxY), CGPoint(x: r.minX + k, y: r.maxY)], fill: fill, stroke: stroke)
    case .start:
      canvas.ellipse(in: r, fill: theme.text, stroke: nil)
      return
    case .end:
      canvas.ellipse(in: r, fill: nil, stroke: Stroke(color: theme.text, width: 1.5))
      canvas.ellipse(in: r.insetBy(dx: 4, dy: 4), fill: theme.text, stroke: nil)
      return
    case .classBox:
      canvas.rect(r, radius: 4, fill: fill, stroke: stroke)
      var y = r.minY
      for (i, comp) in n.compartments.enumerated() {
        let st = i == 0 ? theme.style(weight: .semibold, color: style?.color) : theme.style(theme.fontSize - 1, color: style?.color)
        let text = comp.joined(separator: "\n")
        let s = TextMetrics.measure(text.isEmpty ? " " : text, style: st)
        if i > 0 { canvas.line(CGPoint(x: r.minX, y: y), CGPoint(x: r.maxX, y: y), stroke: stroke) }
        canvas.text(text, at: CGPoint(x: r.minX + nodePaddingX, y: y + 4), width: r.width - nodePaddingX * 2, align: i == 0 ? .center : .left, style: st)
        y += s.height + 8
      }
      return
    }
    canvas.text(n.label, at: textOrigin, width: r.width, align: .center, style: textStyle)
  }

  // MARK: - Edges

  private func drawEdge<C: Canvas>(_ index: Int, _ e: GraphDiagram.Edge, on canvas: inout C, offset: CGPoint) {
    guard var pts = layout.edgeRoutes[index]?.map({ CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }), pts.count >= 2 else { return }
    let fromRect = layout.nodeRects[e.from]?.offsetBy(dx: offset.x, dy: offset.y)
    let toRect = layout.nodeRects[e.to]?.offsetBy(dx: offset.x, dy: offset.y)
    let stroke = Stroke(color: theme.edge, width: e.line == .thick ? 2.5 : 1.2, dash: e.line == .dotted ? [3, 4] : [])

    if e.from == e.to, let r = fromRect {
      // Self loop on the right side.
      let a = CGPoint(x: r.maxX, y: r.midY - 8), b = CGPoint(x: r.maxX, y: r.midY + 8)
      let c1 = CGPoint(x: r.maxX + 28, y: r.midY - 26), c2 = CGPoint(x: r.maxX + 28, y: r.midY + 26)
      canvas.path(start: a, segments: [(c1, c2, b)], closed: false, fill: nil, stroke: stroke)
      drawHead(e.head, at: b, from: c2, on: &canvas, stroke: stroke)
      if let l = e.label { drawLabel(l, at: CGPoint(x: r.maxX + 24, y: r.midY), on: &canvas) }
      return
    }
    // Clip endpoints to shape boundaries.
    if let fr = fromRect, let n = diagram.node(withID: e.from) { pts[0] = boundary(of: n.shape, rect: fr, toward: pts[1]) }
    if let tr = toRect, let n = diagram.node(withID: e.to) { pts[pts.count - 1] = boundary(of: n.shape, rect: tr, toward: pts[pts.count - 2]) }
    // Pull the ends back so arrowheads sit on the boundary.
    let headLen: Double = e.head == .none ? 0 : 9
    let tailLen: Double = e.tail == .none ? 0 : 9
    let last = pts.count - 1
    if headLen > 0 { pts[last] = shorten(pts[last], from: pts[last - 1], by: headLen * 0.6) }
    if tailLen > 0 { pts[0] = shorten(pts[0], from: pts[1], by: tailLen * 0.6) }

    let segments = smooth(pts)
    canvas.path(start: pts[0], segments: segments, closed: false, fill: nil, stroke: stroke)
    drawHead(e.head, at: pts[last], from: pts[last - 1], on: &canvas, stroke: stroke)
    drawHead(e.tail, at: pts[0], from: pts[1], on: &canvas, stroke: stroke)
    if let l = e.label, !l.isEmpty { drawLabel(l, at: midpoint(pts), on: &canvas) }
  }

  private func drawLabel<C: Canvas>(_ text: String, at p: CGPoint, on canvas: inout C) {
    let style = theme.style(theme.fontSize - 1)
    let s = TextMetrics.measure(text, style: style)
    let r = CGRect(x: p.x - s.width / 2 - 5, y: p.y - s.height / 2 - 2, width: s.width + 10, height: s.height + 4)
    canvas.rect(r, radius: 4, fill: theme.background.a > 0 ? theme.background : (theme.text.r > 0.5 ? DiagramColor(hex: 0x1E1E1E) : DiagramColor(hex: 0xFFFFFF)), stroke: nil)
    canvas.text(text, at: CGPoint(x: r.minX + 5, y: r.minY + 2), width: s.width, align: .center, style: style)
  }

  private func drawHead<C: Canvas>(_ head: GraphDiagram.ArrowHead, at tip: CGPoint, from: CGPoint, on canvas: inout C, stroke: Stroke) {
    guard head != .none else { return }
    let dx = tip.x - from.x, dy = tip.y - from.y
    let len = max(0.001, (dx * dx + dy * dy).squareRoot())
    let ux = dx / len, uy = dy / len
    let solid = Stroke(color: stroke.color, width: stroke.width, dash: [])
    switch head {
    case .arrow:
      let size: Double = 9
      let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
      let left = CGPoint(x: base.x - uy * size * 0.45, y: base.y + ux * size * 0.45)
      let right = CGPoint(x: base.x + uy * size * 0.45, y: base.y - ux * size * 0.45)
      canvas.polygon([tip, left, right], fill: stroke.color, stroke: nil)
    case .triangle:
      let size: Double = 12
      let base = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
      let left = CGPoint(x: base.x - uy * size * 0.55, y: base.y + ux * size * 0.55)
      let right = CGPoint(x: base.x + uy * size * 0.55, y: base.y - ux * size * 0.55)
      canvas.polygon([tip, left, right], fill: theme.background.a > 0 ? theme.background : DiagramColor(hex: 0xFFFFFF, alpha: 0), stroke: solid)
    case .circle:
      let r: Double = 4
      canvas.ellipse(in: CGRect(x: tip.x - ux * r - r, y: tip.y - uy * r - r, width: r * 2, height: r * 2), fill: stroke.color, stroke: nil)
    case .cross:
      let s: Double = 5
      let c = CGPoint(x: tip.x - ux * s, y: tip.y - uy * s)
      canvas.line(CGPoint(x: c.x - s, y: c.y - s), CGPoint(x: c.x + s, y: c.y + s), stroke: solid)
      canvas.line(CGPoint(x: c.x - s, y: c.y + s), CGPoint(x: c.x + s, y: c.y - s), stroke: solid)
    case .diamond, .diamondFilled:
      let size: Double = 7
      let mid = CGPoint(x: tip.x - ux * size, y: tip.y - uy * size)
      let back = CGPoint(x: tip.x - ux * size * 2, y: tip.y - uy * size * 2)
      let left = CGPoint(x: mid.x - uy * size * 0.6, y: mid.y + ux * size * 0.6)
      let right = CGPoint(x: mid.x + uy * size * 0.6, y: mid.y - ux * size * 0.6)
      canvas.polygon([tip, left, back, right], fill: head == .diamondFilled ? stroke.color : (theme.text.r > 0.5 ? DiagramColor(hex: 0x1E1E1E) : DiagramColor(hex: 0xFFFFFF)), stroke: solid)
    case .erOne, .erZeroOrOne, .erZeroOrMore, .erOneOrMore:
      // Crow's foot notation, read from the entity outwards: bar = one, circle = zero, foot = many.
      let nx = -uy, ny = ux
      func bar(_ d: Double) { canvas.line(CGPoint(x: tip.x - ux * d - nx * 6, y: tip.y - uy * d - ny * 6), CGPoint(x: tip.x - ux * d + nx * 6, y: tip.y - uy * d + ny * 6), stroke: solid) }
      func foot() {
        let heel = CGPoint(x: tip.x - ux * 12, y: tip.y - uy * 12)
        canvas.line(heel, CGPoint(x: tip.x + nx * 7, y: tip.y + ny * 7), stroke: solid)
        canvas.line(heel, CGPoint(x: tip.x - nx * 7, y: tip.y - ny * 7), stroke: solid)
      }
      func circle(_ d: Double) {
        let c = CGPoint(x: tip.x - ux * d, y: tip.y - uy * d)
        canvas.ellipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8), fill: theme.background.a > 0 ? theme.background : DiagramColor(hex: 0xFFFFFF), stroke: solid)
      }
      switch head {
      case .erOne: bar(6); bar(11)
      case .erZeroOrOne: bar(6); circle(15)
      case .erZeroOrMore: foot(); circle(18)
      default: foot(); bar(14)
      }
    case .none: break
    }
  }

  // MARK: - Geometry helpers

  private func shorten(_ p: CGPoint, from q: CGPoint, by d: Double) -> CGPoint {
    let dx = p.x - q.x, dy = p.y - q.y
    let len = (dx * dx + dy * dy).squareRoot()
    guard len > d else { return p }
    return CGPoint(x: p.x - dx / len * d, y: p.y - dy / len * d)
  }

  private func midpoint(_ pts: [CGPoint]) -> CGPoint {
    var total: Double = 0
    for i in 1..<pts.count { total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
    var acc: Double = 0
    for i in 1..<pts.count {
      let l = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
      if acc + l >= total / 2 {
        let t = l == 0 ? 0 : (total / 2 - acc) / l
        return CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
      }
      acc += l
    }
    return pts[pts.count / 2]
  }

  /// Catmull-Rom → cubic Bézier segments; two points give a straight line.
  private func smooth(_ pts: [CGPoint]) -> [(CGPoint, CGPoint, CGPoint)] {
    guard pts.count > 2 else { return [(pts[1], pts[1], pts[1])] }
    var out: [(CGPoint, CGPoint, CGPoint)] = []
    for i in 0..<(pts.count - 1) {
      let p0 = i == 0 ? pts[0] : pts[i - 1], p1 = pts[i], p2 = pts[i + 1], p3 = i + 2 < pts.count ? pts[i + 2] : pts[i + 1]
      let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
      let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
      out.append((c1, c2, p2))
    }
    return out
  }

  /// Point on the shape's outline along the ray from its centre toward `target`.
  private func boundary(of shape: GraphDiagram.Shape, rect: CGRect, toward target: CGPoint) -> CGPoint {
    let c = CGPoint(x: rect.midX, y: rect.midY)
    func inside(_ p: CGPoint) -> Bool {
      switch shape {
      case .circle, .doubleCircle, .start, .end:
        let rx: Double = rect.width / 2, ry: Double = rect.height / 2
        let dx: Double = (p.x - c.x) / rx, dy: Double = (p.y - c.y) / ry
        let d2: Double = dx * dx + dy * dy
        return d2 <= 1
      case .diamond:
        let nx: Double = abs(p.x - c.x) / (rect.width / 2)
        let ny: Double = abs(p.y - c.y) / (rect.height / 2)
        return nx + ny <= 1
      case .stadium:
        let r = rect.height / 2
        if abs(p.y - c.y) > r { return false }
        if p.x >= rect.minX + r && p.x <= rect.maxX - r { return true }
        let cx = p.x < c.x ? rect.minX + r : rect.maxX - r
        return hypot(p.x - cx, p.y - c.y) <= r
      default:
        return rect.contains(p)
      }
    }
    var lo: Double = 0, hi: Double = 1
    let dx = target.x - c.x, dy = target.y - c.y
    if !inside(target) {
      for _ in 0..<24 {
        let mid = (lo + hi) / 2
        if inside(CGPoint(x: c.x + dx * mid, y: c.y + dy * mid)) { lo = mid } else { hi = mid }
      }
      return CGPoint(x: c.x + dx * lo, y: c.y + dy * lo)
    }
    return c
  }
}
