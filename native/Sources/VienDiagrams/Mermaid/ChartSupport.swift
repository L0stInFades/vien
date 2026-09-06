import CoreGraphics
import Foundation

/// Small helpers shared by the chart-like diagrams (gantt, timeline, journey, quadrant, xy).
enum ChartSupport {
  /// Wraps `text` into lines no wider than `width` (existing newlines are kept).
  static func wrap(_ text: String, width: Double, style: TextStyle) -> String {
    var out: [String] = []
    for paragraph in TextMetrics.lines(text) {
      var line = ""
      for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
        let candidate = line.isEmpty ? word : line + " " + word
        if TextMetrics.measure(candidate, style: style).width <= width || line.isEmpty { line = candidate } else { out.append(line); line = word }
      }
      out.append(line)
    }
    return out.joined(separator: "\n")
  }

  /// "Nice" axis ticks covering `min...max` with about `count` steps.
  static func ticks(min lo: Double, max hi: Double, count: Int = 5) -> [Double] {
    guard hi > lo else { return [lo] }
    let raw = (hi - lo) / Double(max(1, count))
    let magnitude = pow(10, floor(log10(raw)))
    let residual = raw / magnitude
    let step = (residual > 5 ? 10 : residual > 2 ? 5 : residual > 1 ? 2 : 1) * magnitude
    var out: [Double] = []
    var v = (lo / step).rounded(.down) * step
    while v <= hi + step * 0.001 { out.append(v); v += step }
    return out
  }

  static func format(_ v: Double) -> String {
    if v == v.rounded(), abs(v) < 1e15 { return String(Int(v)) }
    return String(format: abs(v) < 10 ? "%.2f" : "%.1f", v)
  }

  /// A rounded label box with centred text.
  static func labelBox<C: Canvas>(_ text: String, at origin: CGPoint, width: Double, style: TextStyle, fill: DiagramColor?, stroke: Stroke?, padding: Double = 8, radius: Double = 8, on canvas: inout C) -> Double {
    let size = TextMetrics.measure(text, style: style)
    let h = size.height + padding * 2
    canvas.rect(CGRect(x: origin.x, y: origin.y, width: width, height: h), radius: radius, fill: fill, stroke: stroke)
    canvas.text(text, at: CGPoint(x: origin.x + padding, y: origin.y + padding), width: width - padding * 2, align: .center, style: style)
    return h
  }
}
