import CoreGraphics
import Foundation

public struct XYChartDiagram: Sendable {
  public enum Kind: Sendable { case bar, line }
  var title: String?
  var xTitle: String?, yTitle: String?
  var categories: [String] = []
  var xRange: (Double, Double)?
  var yRange: (Double, Double)?
  var series: [(Kind, [Double])] = []
  var horizontal = false
}

enum XYChartParser {
  static func parse(_ lines: [(Int, String)]) throws -> XYChartDiagram {
    var d = XYChartDiagram()
    d.horizontal = lines.first?.1.lowercased().contains("horizontal") ?? false
    func quoted(_ s: Substring) -> (String?, Substring) {
      let t = s.trimmingCharacters(in: .whitespaces)
      guard t.hasPrefix("\"") else { return (nil, s) }
      let body = t.dropFirst()
      guard let end = body.firstIndex(of: "\"") else { return (String(body), "") }
      return (String(body[..<end]), body[body.index(after: end)...])
    }
    func numbers(_ s: Substring) throws -> [Double] {
      guard let open = s.firstIndex(of: "["), let close = s.lastIndex(of: "]") else { return [] }
      return s[s.index(after: open)..<close].split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("title") { d.title = Mermaid.cleanLabel(String(line.dropFirst(5))); continue }
      if lower.hasPrefix("x-axis") || lower.hasPrefix("y-axis") {
        let isX = lower.hasPrefix("x-axis")
        let (title, rest) = quoted(line.dropFirst(6))
        if isX { d.xTitle = title } else { d.yTitle = title }
        let r = rest.trimmingCharacters(in: .whitespaces)
        if r.hasPrefix("[") {
          let items = r.dropFirst().split(separator: "]").first.map { $0.split(separator: ",").map { Mermaid.cleanLabel(String($0)) } } ?? []
          if isX { d.categories = items }
        } else if r.contains("-->") {
          let parts = r.components(separatedBy: "-->").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
          if parts.count == 2 { if isX { d.xRange = (parts[0], parts[1]) } else { d.yRange = (parts[0], parts[1]) } }
        }
        continue
      }
      if lower.hasPrefix("bar") { d.series.append((.bar, try numbers(line.dropFirst(3)))); continue }
      if lower.hasPrefix("line") { d.series.append((.line, try numbers(line.dropFirst(4)))); continue }
      throw DiagramSyntaxError(line: n, message: "expected title, x-axis, y-axis, bar or line")
    }
    guard !d.series.isEmpty else { throw DiagramSyntaxError(line: 1, message: "the chart has no data") }
    return d
  }
}

struct XYChartRenderer {
  let diagram: XYChartDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let plotWidth: Double = 460
  private let plotHeight: Double = 240
  private var yTicks: [Double] = []
  private var range: (Double, Double) = (0, 1)
  private var yLabelWidth: Double = 0
  private var count: Int { diagram.series.map { $0.1.count }.max() ?? 0 }

  init(diagram: XYChartDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    let values = diagram.series.flatMap { $0.1 }
    var lo = diagram.yRange?.0 ?? min(0, values.min() ?? 0)
    var hi = diagram.yRange?.1 ?? (values.max() ?? 1)
    if hi <= lo { hi = lo + 1 }
    var ticks = ChartSupport.ticks(min: lo, max: hi)
    if diagram.yRange == nil {
      // Grow to nice bounds so the top tick sits above the data.
      if let last = ticks.last, last < hi, ticks.count > 1 { ticks.append(last + (ticks[1] - ticks[0])) }
      lo = ticks.first ?? lo
      hi = ticks.last ?? hi
    }
    range = (lo, hi)
    yTicks = ticks.filter { $0 >= lo - 0.0001 && $0 <= hi + 0.0001 }
    if yTicks.first.map({ $0 > lo + 0.0001 }) ?? true { yTicks.insert(lo, at: 0) }
    yLabelWidth = (yTicks.map { TextMetrics.measure(ChartSupport.format($0), style: tickStyle).width }.max() ?? 0) + 10
  }

  private var tickStyle: TextStyle { theme.style(theme.fontSize - 3, color: theme.secondaryText) }
  private var left: Double { margin + (diagram.yTitle == nil ? 0 : 18) + yLabelWidth }
  private var top: Double { margin + (diagram.title == nil ? 0 : 30) }
  private var bottom: Double { top + plotHeight }

  var size: CGSize { CGSize(width: left + plotWidth + margin, height: bottom + 22 + (diagram.xTitle == nil ? 0 : 18) + margin) }

  private func y(_ v: Double) -> Double {
    bottom - (max(range.0, min(range.1, v)) - range.0) / max(0.0001, range.1 - range.0) * plotHeight
  }

  func draw<C: Canvas>(on canvas: inout C) {
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    let grid = Stroke(color: theme.nodeStroke.withAlpha(0.25), width: 1)
    for v in yTicks {
      let ty = y(v)
      canvas.line(CGPoint(x: left, y: ty), CGPoint(x: left + plotWidth, y: ty), stroke: grid)
      canvas.text(ChartSupport.format(v), at: CGPoint(x: left - yLabelWidth - 2, y: ty - 7), width: yLabelWidth - 4, align: .right, style: tickStyle)
    }
    canvas.line(CGPoint(x: left, y: top), CGPoint(x: left, y: bottom), stroke: Stroke(color: theme.edge, width: 1))
    canvas.line(CGPoint(x: left, y: bottom), CGPoint(x: left + plotWidth, y: bottom), stroke: Stroke(color: theme.edge, width: 1))
    let n = max(1, count)
    let slot = plotWidth / Double(n)
    // Category labels (or numeric range labels), thinned so neighbours never touch.
    func label(_ i: Int) -> String {
      if i < diagram.categories.count { return diagram.categories[i] }
      if let r = diagram.xRange { return ChartSupport.format(r.0 + (r.1 - r.0) * Double(i) / Double(max(1, n - 1))) }
      return String(i + 1)
    }
    let widest = ((0..<n).prefix(12).map { TextMetrics.measure(label($0), style: tickStyle).width }.max() ?? 20) + 8
    let every = max(1, Int((widest / max(1, slot)).rounded(.up)))
    for i in stride(from: 0, to: n, by: every) {
      let w = max(slot, widest)
      canvas.text(label(i), at: CGPoint(x: left + Double(i) * slot + slot / 2 - w / 2, y: bottom + 5), width: w, align: .center, style: tickStyle)
    }
    if let xt = diagram.xTitle { canvas.text(xt, at: CGPoint(x: left, y: bottom + 22), width: plotWidth, align: .center, style: theme.style(theme.fontSize - 2, color: theme.secondaryText)) }
    if let yt = diagram.yTitle { canvas.text(yt, at: CGPoint(x: margin - 4, y: top - 16), width: yLabelWidth + 30, align: .left, style: theme.style(theme.fontSize - 2, color: theme.secondaryText)) }
    let bars = diagram.series.filter { $0.0 == .bar }
    let barWidth = slot * 0.6 / Double(max(1, bars.count))
    var barIndex = 0
    for (k, s) in diagram.series.enumerated() {
      let color = theme.palette[k % theme.palette.count]
      switch s.0 {
      case .bar:
        for (i, v) in s.1.enumerated() {
          let x = left + Double(i) * slot + slot * 0.2 + Double(barIndex) * barWidth
          let y0 = y(v), y1 = y(range.0)
          canvas.rect(CGRect(x: x, y: min(y0, y1), width: barWidth - 2, height: abs(y1 - y0)), radius: 2, fill: color.withAlpha(0.85), stroke: nil)
        }
        barIndex += 1
      case .line:
        var previous: CGPoint? = nil
        for (i, v) in s.1.enumerated() {
          let p = CGPoint(x: left + Double(i) * slot + slot / 2, y: y(v))
          if let previous { canvas.line(previous, p, stroke: Stroke(color: color, width: 2)) }
          previous = p
        }
        for (i, v) in s.1.enumerated() {
          let p = CGPoint(x: left + Double(i) * slot + slot / 2, y: y(v))
          canvas.ellipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7), fill: color, stroke: nil)
        }
      }
    }
  }
}
