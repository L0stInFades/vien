import CoreGraphics
import Foundation

public struct QuadrantDiagram: Sendable {
  var title: String?
  var xLeft: String?, xRight: String?
  var yBottom: String?, yTop: String?
  var quadrants: [String?] = [nil, nil, nil, nil]
  var points: [(String, Double, Double)] = []
}

enum QuadrantParser {
  static func parse(_ lines: [(Int, String)]) throws -> QuadrantDiagram {
    var d = QuadrantDiagram()
    func axis(_ s: String) -> (String?, String?) {
      let parts = s.components(separatedBy: "-->").map { Mermaid.cleanLabel($0) }
      return (parts.first.flatMap { $0.isEmpty ? nil : $0 }, parts.count > 1 ? parts[1] : nil)
    }
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("title ") { d.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
      if lower.hasPrefix("x-axis ") { (d.xLeft, d.xRight) = axis(String(line.dropFirst(7))); continue }
      if lower.hasPrefix("y-axis ") { (d.yBottom, d.yTop) = axis(String(line.dropFirst(7))); continue }
      if lower.hasPrefix("quadrant-"), let k = Int(String(lower.dropFirst(9).prefix(1))), (1...4).contains(k) {
        d.quadrants[k - 1] = Mermaid.cleanLabel(String(line.dropFirst(10)))
        continue
      }
      if lower.hasPrefix("classdef") || lower.hasPrefix("%%") { continue }
      // Name[:::class]: [x, y] [radius: N color: … …] — brackets hold the point; styles are ignored.
      guard let open = line.firstIndex(of: "["), let close = line[open...].firstIndex(of: "]"), let colon = line[..<open].lastIndex(of: ":") else {
        throw DiagramSyntaxError(line: n, message: "expected “Name: [x, y]”")
      }
      let nums = line[line.index(after: open)..<close].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
      guard nums.count == 2 else { throw DiagramSyntaxError(line: n, message: "a point needs two numbers between 0 and 1") }
      var name = String(line[..<colon])
      if let styleMark = name.range(of: ":::") { name = String(name[..<styleMark.lowerBound]) }
      d.points.append((Mermaid.cleanLabel(name), max(0, min(1, nums[0])), max(0, min(1, nums[1]))))
    }
    return d
  }
}

struct QuadrantRenderer {
  let diagram: QuadrantDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let side: Double = 320
  private var axisStyle: TextStyle { theme.style(theme.fontSize - 2, color: theme.secondaryText) }
  private var axisLeft: Double {
    let w = [diagram.yBottom, diagram.yTop].compactMap { $0 }.map { TextMetrics.measure($0, style: axisStyle).width }.max() ?? 0
    return w == 0 ? 0 : min(w, 140) + 10
  }
  private var axisBottom: Double { diagram.xLeft == nil && diagram.xRight == nil ? 0 : 22 }
  private var top: Double { margin + (diagram.title == nil ? 0 : 30) }

  var size: CGSize { CGSize(width: margin * 2 + axisLeft + side, height: top + side + axisBottom + margin) }

  func draw<C: Canvas>(on canvas: inout C) {
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    let x0 = margin + axisLeft, y0 = top
    let half = side / 2
    // Quadrants: 1 top-right, 2 top-left, 3 bottom-left, 4 bottom-right.
    let rects = [CGRect(x: x0 + half, y: y0, width: half, height: half), CGRect(x: x0, y: y0, width: half, height: half),
      CGRect(x: x0, y: y0 + half, width: half, height: half), CGRect(x: x0 + half, y: y0 + half, width: half, height: half)]
    for (i, r) in rects.enumerated() {
      canvas.rect(r, radius: 0, fill: theme.palette[i % theme.palette.count].withAlpha(0.12), stroke: Stroke(color: theme.nodeStroke.withAlpha(0.5), width: 1))
      if let label = diagram.quadrants[i] {
        // At the top of the quadrant, out of the way of the points.
        let style = theme.style(theme.fontSize - 1, color: theme.secondaryText)
        canvas.text(label, at: CGPoint(x: r.minX + 6, y: r.minY + 8), width: r.width - 12, align: .center, style: style)
      }
    }
    if let l = diagram.xLeft { canvas.text(l, at: CGPoint(x: x0, y: y0 + side + 6), width: half, align: .center, style: axisStyle) }
    if let r = diagram.xRight { canvas.text(r, at: CGPoint(x: x0 + half, y: y0 + side + 6), width: half, align: .center, style: axisStyle) }
    if let b = diagram.yBottom {
      let wrapped = ChartSupport.wrap(b, width: axisLeft - 10, style: axisStyle)
      canvas.text(wrapped, at: CGPoint(x: margin, y: y0 + side * 0.75 - TextMetrics.measure(wrapped, style: axisStyle).height / 2), width: axisLeft - 10, align: .right, style: axisStyle)
    }
    if let t = diagram.yTop {
      let wrapped = ChartSupport.wrap(t, width: axisLeft - 10, style: axisStyle)
      canvas.text(wrapped, at: CGPoint(x: margin, y: y0 + side * 0.25 - TextMetrics.measure(wrapped, style: axisStyle).height / 2), width: axisLeft - 10, align: .right, style: axisStyle)
    }
    for (i, p) in diagram.points.enumerated() {
      let c = CGPoint(x: x0 + p.1 * side, y: y0 + (1 - p.2) * side)
      let color = theme.palette[(i + 4) % theme.palette.count]
      canvas.ellipse(in: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10), fill: color, stroke: Stroke(color: theme.background.a > 0 ? theme.background : DiagramColor(hex: 0xFFFFFF), width: 1))
      canvas.text(p.0, at: CGPoint(x: c.x - 80, y: c.y + 7), width: 160, align: .center, style: theme.style(theme.fontSize - 2))
    }
  }
}
