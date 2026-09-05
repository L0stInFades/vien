import CoreGraphics
import Foundation

public struct PieDiagram: Sendable {
  var title: String?
  var showData = false
  var slices: [(String, Double)] = []
}

enum PieParser {
  static func parse(_ lines: [(Int, String)]) throws -> PieDiagram {
    var d = PieDiagram()
    for (i, (n, raw)) in lines.enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if i == 0 {
        var rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if rest.lowercased().hasPrefix("showdata") { d.showData = true; rest = rest.dropFirst(8).trimmingCharacters(in: .whitespaces) }
        if rest.lowercased().hasPrefix("title") { d.title = rest.dropFirst(5).trimmingCharacters(in: .whitespaces) }
        continue
      }
      if line.lowercased().hasPrefix("title ") { d.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
      if line.lowercased() == "showdata" { d.showData = true; continue }
      guard let colon = line.lastIndex(of: ":") else { throw DiagramSyntaxError(line: n, message: "expected “\"label\" : value”") }
      let label = Mermaid.cleanLabel(String(line[..<colon]))
      guard let value = Double(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)) else {
        throw DiagramSyntaxError(line: n, message: "value must be a number")
      }
      d.slices.append((label, value))
    }
    return d
  }
}

struct PieRenderer {
  let diagram: PieDiagram
  let theme: DiagramTheme
  private let radius: Double = 90
  private let margin: Double = 16

  var size: CGSize {
    let legendW = (diagram.slices.map { TextMetrics.measure(legendText($0), style: theme.style(theme.fontSize - 1)).width }.max() ?? 0) + 30
    let h = max(radius * 2, Double(diagram.slices.count) * 22) + margin * 2 + (diagram.title == nil ? 0 : 30)
    return CGSize(width: margin * 2 + radius * 2 + 24 + legendW, height: h)
  }

  private func legendText(_ s: (String, Double)) -> String {
    diagram.showData ? "\(s.0) (\(format(s.1)))" : s.0
  }

  private func format(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

  func draw<C: Canvas>(on canvas: inout C) {
    let top = margin + (diagram.title == nil ? 0 : 30)
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    let total = diagram.slices.map(\.1).reduce(0, +)
    let center = CGPoint(x: margin + radius, y: top + radius)
    var angle = -Double.pi / 2
    for (i, s) in diagram.slices.enumerated() where total > 0 {
      let sweep = s.1 / total * 2 * .pi
      let color = theme.palette[i % theme.palette.count]
      canvas.pieSlice(center: center, radius: radius, start: angle, end: angle + sweep, fill: color, stroke: Stroke(color: theme.background.a > 0 ? theme.background : DiagramColor(hex: 0xFFFFFF), width: 1.5))
      if sweep > 0.25 {
        let mid = angle + sweep / 2
        let p = CGPoint(x: center.x + cos(mid) * radius * 0.62, y: center.y + sin(mid) * radius * 0.62)
        let pct = String(format: "%.0f%%", s.1 / total * 100)
        canvas.text(pct, at: CGPoint(x: p.x - 30, y: p.y - 8), width: 60, align: .center, style: TextStyle(size: theme.fontSize - 1, weight: .semibold, color: DiagramColor(hex: 0xFFFFFF)))
      }
      angle += sweep
    }
    let lx = margin + radius * 2 + 24
    var ly = top + radius - Double(diagram.slices.count) * 11
    for (i, s) in diagram.slices.enumerated() {
      canvas.rect(CGRect(x: lx, y: ly + 4, width: 12, height: 12), radius: 3, fill: theme.palette[i % theme.palette.count], stroke: nil)
      canvas.text(legendText(s), at: CGPoint(x: lx + 18, y: ly + 1), width: 400, align: .left, style: theme.style(theme.fontSize - 1))
      ly += 22
    }
  }
}
