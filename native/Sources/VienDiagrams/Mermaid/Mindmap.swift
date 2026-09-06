import CoreGraphics
import Foundation

public struct MindmapDiagram: Sendable {
  public enum Shape: Sendable { case plain, rounded, square, circle, cloud, bang, hexagon }
  public struct Node: Sendable {
    var text: String
    var shape: Shape
    var children: [Int] = []
    var parent: Int?
    var depth = 0
  }
  var nodes: [Node] = []
}

enum MindmapParser {
  static func parse(_ lines: [(Int, String)]) throws -> MindmapDiagram {
    var d = MindmapDiagram()
    var stack: [(indent: Int, index: Int)] = []
    for (n, raw) in lines.dropFirst() {
      let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("::icon") || line.hasPrefix(":::") || line.isEmpty { continue }
      let (text, shape) = parseNode(line)
      while let last = stack.last, last.indent >= indent { stack.removeLast() }
      var node = MindmapDiagram.Node(text: text, shape: shape)
      if let parent = stack.last {
        node.parent = parent.index
        node.depth = d.nodes[parent.index].depth + 1
      } else if !d.nodes.isEmpty {
        throw DiagramSyntaxError(line: n, message: "a mindmap has one root; indent “\(text)” under it")
      }
      d.nodes.append(node)
      if let parent = node.parent { d.nodes[parent].children.append(d.nodes.count - 1) }
      stack.append((indent, d.nodes.count - 1))
    }
    guard !d.nodes.isEmpty else { throw DiagramSyntaxError(line: 1, message: "empty mindmap") }
    return d
  }

  /// `id((text))`, `id(text)`, `id[text]`, `id{{text}}`, `id))text((`, `id)text(` or plain text.
  static func parseNode(_ s: String) -> (String, MindmapDiagram.Shape) {
    let pairs: [(String, String, MindmapDiagram.Shape)] = [("((", "))", .circle), ("))", "((", .bang), ("{{", "}}", .hexagon), ("(", ")", .rounded), ("[", "]", .square), (")", "(", .cloud)]
    for (open, close, shape) in pairs {
      if let r = s.range(of: open), s.hasSuffix(close), r.upperBound <= s.index(s.endIndex, offsetBy: -close.count) {
        let inner = String(s[r.upperBound..<s.index(s.endIndex, offsetBy: -close.count)])
        return (Mermaid.cleanLabel(inner), shape)
      }
    }
    return (Mermaid.cleanLabel(s), .plain)
  }
}

struct MindmapRenderer {
  let diagram: MindmapDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let levelGap: Double = 48
  private let siblingGap: Double = 10
  private var sizes: [CGSize] = []
  private var texts: [String] = []
  private var positions: [CGPoint] = []  // node centres
  private var branchColor: [Int] = []  // top-level branch index per node
  private var bounds = CGRect.zero

  private func style(_ depth: Int) -> TextStyle {
    depth == 0 ? theme.style(theme.fontSize + 2, weight: .semibold) : depth == 1 ? theme.style(weight: .medium) : theme.style(theme.fontSize - 1)
  }

  init(diagram: MindmapDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    for n in diagram.nodes {
      let wrapped = ChartSupport.wrap(n.text, width: 160, style: style(n.depth))
      texts.append(wrapped)
      let t = TextMetrics.measure(wrapped, style: style(n.depth))
      let pad: Double = n.shape == .plain ? 6 : n.depth == 0 ? 18 : 12
      var s = CGSize(width: t.width + pad * 2, height: t.height + pad * 1.2)
      if n.shape == .circle || n.shape == .bang { let d = max(s.width, s.height); s = CGSize(width: d, height: d) }
      sizes.append(s)
    }
    positions = Array(repeating: .zero, count: diagram.nodes.count)
    branchColor = Array(repeating: 0, count: diagram.nodes.count)
    layout()
  }

  /// Subtree height when laid out as a horizontal tree.
  private func height(_ i: Int) -> Double {
    let own = sizes[i].height
    let children = diagram.nodes[i].children
    if children.isEmpty { return own }
    let total = children.map(height).reduce(0, +) + Double(children.count - 1) * siblingGap
    return max(own, total)
  }

  private mutating func place(_ i: Int, x: Double, centerY: Double, direction: Double, color: Int) {
    positions[i] = CGPoint(x: x + direction * sizes[i].width / 2, y: centerY)
    branchColor[i] = color
    let children = diagram.nodes[i].children
    guard !children.isEmpty else { return }
    let total = children.map(height).reduce(0, +) + Double(children.count - 1) * siblingGap
    var y = centerY - total / 2
    let childX = x + direction * (sizes[i].width + levelGap)
    for c in children {
      let h = height(c)
      place(c, x: childX, centerY: y + h / 2, direction: direction, color: color)
      y += h + siblingGap
    }
  }

  private mutating func layout() {
    let root = 0
    // Split the root's children between the two sides, balancing subtree heights.
    var right: [Int] = [], left: [Int] = []
    var hr = 0.0, hl = 0.0
    for c in diagram.nodes[root].children {
      let h = height(c)
      if hr <= hl { right.append(c); hr += h + siblingGap } else { left.append(c); hl += h + siblingGap }
    }
    positions[root] = .zero
    for (side, dir) in [(right, 1.0), (left, -1.0)] {
      let total = side.map(height).reduce(0, +) + Double(max(0, side.count - 1)) * siblingGap
      var y = -total / 2
      for (k, c) in side.enumerated() {
        let h = height(c)
        place(c, x: dir * (sizes[root].width / 2 + levelGap), centerY: y + h / 2, direction: dir, color: k + (dir > 0 ? 0 : right.count))
        y += h + siblingGap
      }
    }
    var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
    for (i, p) in positions.enumerated() {
      minX = min(minX, p.x - sizes[i].width / 2); maxX = max(maxX, p.x + sizes[i].width / 2)
      minY = min(minY, p.y - sizes[i].height / 2); maxY = max(maxY, p.y + sizes[i].height / 2)
    }
    bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  var size: CGSize { CGSize(width: bounds.width + margin * 2, height: bounds.height + margin * 2) }

  func draw<C: Canvas>(on canvas: inout C) {
    func center(_ i: Int) -> CGPoint { CGPoint(x: positions[i].x - bounds.minX + margin, y: positions[i].y - bounds.minY + margin) }
    func color(_ i: Int) -> DiagramColor { theme.palette[branchColor[i] % theme.palette.count] }
    // Edges: smooth curves from parent edge to child edge.
    for (i, n) in diagram.nodes.enumerated() {
      guard let parent = n.parent else { continue }
      let a = center(parent), b = center(i)
      let dir: Double = b.x >= a.x ? 1 : -1
      let start = CGPoint(x: a.x + dir * sizes[parent].width / 2, y: a.y)
      let end = CGPoint(x: b.x - dir * sizes[i].width / 2, y: b.y)
      let mid = (start.x + end.x) / 2
      canvas.path(start: start, segments: [(CGPoint(x: mid, y: start.y), CGPoint(x: mid, y: end.y), end)], closed: false, fill: nil, stroke: Stroke(color: color(i).withAlpha(0.8), width: n.depth == 1 ? 2.5 : 1.5))
    }
    for (i, n) in diagram.nodes.enumerated() {
      let c = center(i), s = sizes[i]
      let rect = CGRect(x: c.x - s.width / 2, y: c.y - s.height / 2, width: s.width, height: s.height)
      let tint = n.depth == 0 ? theme.accent : color(i)
      let fill = n.depth == 0 ? tint : tint.withAlpha(n.depth == 1 ? 0.22 : 0.12)
      let stroke = Stroke(color: tint.withAlpha(n.depth == 0 ? 1 : 0.6), width: 1)
      switch n.shape {
      case .plain: break
      case .circle: canvas.ellipse(in: rect, fill: fill, stroke: stroke)
      case .square: canvas.rect(rect, radius: 2, fill: fill, stroke: stroke)
      case .hexagon:
        let k = min(12, s.height / 2)
        canvas.polygon([CGPoint(x: rect.minX + k, y: rect.minY), CGPoint(x: rect.maxX - k, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX - k, y: rect.maxY), CGPoint(x: rect.minX + k, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)], fill: fill, stroke: stroke)
      case .bang:
        var points: [CGPoint] = []
        for k in 0..<16 {
          let angle = Double(k) / 16 * 2 * .pi
          let r = (k % 2 == 0 ? 0.5 : 0.42) * s.width
          points.append(CGPoint(x: c.x + cos(angle) * r, y: c.y + sin(angle) * r))
        }
        canvas.polygon(points, fill: fill, stroke: stroke)
      case .cloud, .rounded:
        canvas.rect(rect, radius: n.shape == .cloud ? s.height / 2 : 8, fill: fill, stroke: stroke)
      }
      let textColor = n.depth == 0 && n.shape != .plain ? DiagramColor(hex: 0xFFFFFF) : theme.text
      var st = style(n.depth)
      st.color = textColor
      let t = TextMetrics.measure(texts[i], style: st)
      canvas.text(texts[i], at: CGPoint(x: c.x - t.width / 2, y: c.y - t.height / 2), width: t.width, align: .center, style: st)
    }
  }
}
