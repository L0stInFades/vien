import CoreGraphics
import Foundation

public struct JourneyDiagram: Sendable {
  public struct Task: Sendable { var name: String; var score: Int; var actors: [String]; var section: Int }
  var title: String?
  var sections: [String] = []
  var tasks: [Task] = []
  var actors: [String] = []
}

enum JourneyParser {
  static func parse(_ lines: [(Int, String)]) throws -> JourneyDiagram {
    var d = JourneyDiagram()
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("title ") { d.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
      if lower.hasPrefix("section ") { d.sections.append(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)); continue }
      let parts = line.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
      guard parts.count >= 2, let score = Int(parts[1]) else { throw DiagramSyntaxError(line: n, message: "expected “task: score: actors”") }
      let actors = parts.count > 2 ? parts[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } : []
      for a in actors where !d.actors.contains(a) { d.actors.append(a) }
      d.tasks.append(.init(name: parts[0], score: max(1, min(5, score)), actors: actors, section: max(0, d.sections.count - 1)))
    }
    if d.sections.isEmpty { d.sections = [""] }
    return d
  }
}

struct JourneyRenderer {
  let diagram: JourneyDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let column: Double = 120
  private let gap: Double = 10
  private let scoreArea: Double = 100
  private var taskHeight: Double = 0
  private var taskTexts: [String] = []
  private var style: TextStyle { theme.style(theme.fontSize - 1, weight: .medium, color: DiagramColor(hex: 0xFFFFFF)) }

  init(diagram: JourneyDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    taskTexts = diagram.tasks.map { ChartSupport.wrap($0.name, width: column - 20, style: style) }
    taskHeight = (taskTexts.map { TextMetrics.measure($0, style: style).height }.max() ?? 0) + 16
  }

  private var hasSections: Bool { diagram.sections.contains { !$0.isEmpty } }
  private var top: Double { margin + (diagram.title == nil ? 0 : 30) + (diagram.actors.isEmpty ? 0 : 24) + (hasSections ? 30 : 0) }

  var size: CGSize {
    CGSize(width: max(200, margin * 2 + Double(diagram.tasks.count) * (column + gap) - gap), height: top + scoreArea + 16 + taskHeight + margin)
  }

  func draw<C: Canvas>(on canvas: inout C) {
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    // Actor legend.
    var lx = margin
    let legendY = margin + (diagram.title == nil ? 0 : 30)
    for (i, a) in diagram.actors.enumerated() {
      let color = theme.palette[i % theme.palette.count]
      canvas.ellipse(in: CGRect(x: lx, y: legendY + 3, width: 10, height: 10), fill: color, stroke: nil)
      let w = TextMetrics.measure(a, style: theme.style(theme.fontSize - 2)).width
      canvas.text(a, at: CGPoint(x: lx + 14, y: legendY), width: w + 4, align: .left, style: theme.style(theme.fontSize - 2))
      lx += w + 30
    }
    let xs = diagram.tasks.indices.map { margin + Double($0) * (column + gap) }
    if hasSections {
      for (s, name) in diagram.sections.enumerated() {
        let idx = diagram.tasks.indices.filter { diagram.tasks[$0].section == s }
        guard let a = idx.first, let b = idx.last else { continue }
        let color = theme.palette[s % theme.palette.count]
        let rect = CGRect(x: xs[a], y: top - 30, width: xs[b] + column - xs[a], height: 22)
        canvas.rect(rect, radius: 6, fill: color.withAlpha(0.18), stroke: nil)
        canvas.text(name, at: CGPoint(x: rect.minX + 6, y: rect.minY + 3), width: rect.width - 12, align: .center, style: theme.style(theme.fontSize - 1, weight: .semibold))
      }
    }
    // Score band with a faint grid, then the line.
    let bandTop = top, bandBottom = top + scoreArea
    for level in 1...5 {
      let y = bandBottom - Double(level - 1) / 4 * (scoreArea - 20) - 10
      canvas.line(CGPoint(x: margin, y: y), CGPoint(x: size.width - margin, y: y), stroke: Stroke(color: theme.nodeStroke.withAlpha(0.2), width: 1))
    }
    func scoreY(_ s: Int) -> Double { bandBottom - Double(s - 1) / 4 * (scoreArea - 20) - 10 }
    var previous: CGPoint? = nil
    for (i, t) in diagram.tasks.enumerated() {
      let p = CGPoint(x: xs[i] + column / 2, y: scoreY(t.score))
      if let previous { canvas.line(previous, p, stroke: Stroke(color: theme.edge, width: 1.5)) }
      previous = p
    }
    for (i, t) in diagram.tasks.enumerated() {
      let p = CGPoint(x: xs[i] + column / 2, y: scoreY(t.score))
      let mood = t.score >= 4 ? DiagramColor(hex: 0x34C759) : t.score == 3 ? DiagramColor(hex: 0xFFCC00) : DiagramColor(hex: 0xFF3B30)
      canvas.ellipse(in: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18), fill: mood, stroke: Stroke(color: theme.background.a > 0 ? theme.background : DiagramColor(hex: 0xFFFFFF), width: 1.5))
      // Actor dots beside the score.
      for (k, a) in t.actors.enumerated() {
        let idx = diagram.actors.firstIndex(of: a) ?? 0
        canvas.ellipse(in: CGRect(x: p.x + 12 + Double(k) * 10, y: p.y - 4, width: 8, height: 8), fill: theme.palette[idx % theme.palette.count], stroke: nil)
      }
      let color = theme.palette[t.section % theme.palette.count]
      _ = ChartSupport.labelBox(taskTexts[i], at: CGPoint(x: xs[i], y: bandBottom + 16), width: column, style: style, fill: color, stroke: nil, on: &canvas)
    }
    _ = bandTop
  }
}
