import CoreGraphics
import Foundation

public struct TimelineDiagram: Sendable {
  public struct Period: Sendable { var label: String; var events: [String]; var section: Int }
  var title: String?
  var sections: [String] = []
  var periods: [Period] = []
}

enum TimelineParser {
  static func parse(_ lines: [(Int, String)]) throws -> TimelineDiagram {
    var d = TimelineDiagram()
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("title ") { d.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
      if lower.hasPrefix("section ") { d.sections.append(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)); continue }
      let parts = line.split(separator: ":", omittingEmptySubsequences: false).map { Mermaid.cleanLabel(String($0)) }
      if line.hasPrefix(":") {
        guard !d.periods.isEmpty else { throw DiagramSyntaxError(line: n, message: "an event needs a period before it") }
        d.periods[d.periods.count - 1].events += parts.dropFirst().filter { !$0.isEmpty }
        continue
      }
      d.periods.append(.init(label: parts[0], events: parts.dropFirst().filter { !$0.isEmpty }, section: max(0, d.sections.count - 1)))
    }
    if d.sections.isEmpty { d.sections = [""] }
    return d
  }
}

struct TimelineRenderer {
  let diagram: TimelineDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let columnGap: Double = 14
  private var columnWidths: [Double] = []
  private var wrapped: [[String]] = []
  private var eventHeights: [[Double]] = []
  private var periodHeight: Double = 0
  private var eventStyle: TextStyle { theme.style(theme.fontSize - 1) }
  private var periodStyle: TextStyle { theme.style(weight: .semibold, color: DiagramColor(hex: 0xFFFFFF)) }

  init(diagram: TimelineDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    for p in diagram.periods {
      let w = max(110, min(180, max(TextMetrics.measure(p.label, style: periodStyle).width + 24, (p.events.map { TextMetrics.measure($0, style: eventStyle).width }.max() ?? 0) + 20)))
      columnWidths.append(w)
      let lines = p.events.map { ChartSupport.wrap($0, width: w - 20, style: eventStyle) }
      wrapped.append(lines)
      eventHeights.append(lines.map { TextMetrics.measure($0, style: eventStyle).height + 16 })
    }
    periodHeight = TextMetrics.measure("X", style: periodStyle).height + 16
  }

  private var hasSections: Bool { diagram.sections.contains { !$0.isEmpty } }
  private var top: Double { margin + (diagram.title == nil ? 0 : 30) + (hasSections ? 30 : 0) }

  var size: CGSize {
    let width = margin * 2 + columnWidths.reduce(0, +) + Double(max(0, columnWidths.count - 1)) * columnGap
    let events = eventHeights.map { $0.reduce(0) { $0 + $1 + 8 } }.max() ?? 0
    return CGSize(width: max(width, 120), height: top + periodHeight + 20 + events + margin)
  }

  func draw<C: Canvas>(on canvas: inout C) {
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    var xs: [Double] = []
    var x = margin
    for w in columnWidths { xs.append(x); x += w + columnGap }
    // Section bands.
    if hasSections {
      for (s, name) in diagram.sections.enumerated() {
        let idx = diagram.periods.indices.filter { diagram.periods[$0].section == s }
        guard let a = idx.first, let b = idx.last else { continue }
        let color = theme.palette[s % theme.palette.count]
        let rect = CGRect(x: xs[a], y: top - 30, width: xs[b] + columnWidths[b] - xs[a], height: 22)
        canvas.rect(rect, radius: 6, fill: color.withAlpha(0.18), stroke: nil)
        canvas.text(name, at: CGPoint(x: rect.minX + 6, y: rect.minY + 3), width: rect.width - 12, align: .center, style: theme.style(theme.fontSize - 1, weight: .semibold))
      }
    }
    // The line through the periods.
    let lineY = top + periodHeight / 2
    if xs.count > 1 { canvas.line(CGPoint(x: xs[0] + columnWidths[0] / 2, y: lineY), CGPoint(x: xs[xs.count - 1] + columnWidths[columnWidths.count - 1] / 2, y: lineY), stroke: Stroke(color: theme.edge, width: 2)) }
    for (i, p) in diagram.periods.enumerated() {
      let color = theme.palette[p.section % theme.palette.count]
      _ = ChartSupport.labelBox(p.label, at: CGPoint(x: xs[i], y: top), width: columnWidths[i], style: periodStyle, fill: color, stroke: nil, on: &canvas)
      var y = top + periodHeight + 20
      canvas.line(CGPoint(x: xs[i] + columnWidths[i] / 2, y: top + periodHeight), CGPoint(x: xs[i] + columnWidths[i] / 2, y: y), stroke: Stroke(color: theme.edge, width: 1))
      for (j, text) in wrapped[i].enumerated() {
        let h = eventHeights[i][j]
        canvas.rect(CGRect(x: xs[i], y: y, width: columnWidths[i], height: h), radius: 8, fill: color.withAlpha(0.12), stroke: Stroke(color: color.withAlpha(0.5), width: 1))
        canvas.text(text, at: CGPoint(x: xs[i] + 10, y: y + 8), width: columnWidths[i] - 20, align: .center, style: eventStyle)
        y += h + 8
      }
    }
  }
}
