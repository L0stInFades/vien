import CoreGraphics
import Foundation

/// `sequenceDiagram` model, parser and renderer.
public struct SequenceDiagram: Sendable {
  public struct Participant: Sendable { var id: String; var label: String; var actor: Bool }
  public enum Arrow: Sendable { case solid, dotted }
  public enum Head: Sendable { case none, arrow, open, cross, async }
  public enum Item: Sendable {
    case message(from: String, to: String, text: String, line: Arrow, head: Head, activate: Bool, deactivate: Bool, bidirectional: Bool)
    case note(participants: [String], position: String, text: String)  // position: left, right, over
    case blockStart(kind: String, label: String)
    case blockElse(label: String)
    case blockEnd
    case activate(String)
    case deactivate(String)
  }
  var participants: [Participant] = []
  var items: [Item] = []
  var autonumber = false
  var title: String?
}

enum SequenceParser {
  static func parse(_ lines: [(Int, String)]) throws -> SequenceDiagram {
    var d = SequenceDiagram()
    func ensure(_ id: String) {
      if !d.participants.contains(where: { $0.id == id }) { d.participants.append(.init(id: id, label: id, actor: false)) }
    }
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("participant ") || lower.hasPrefix("actor ") {
        let actor = lower.hasPrefix("actor ")
        let rest = line.dropFirst(actor ? 6 : 12).trimmingCharacters(in: .whitespaces)
        var id = rest, label = rest
        if let r = rest.range(of: " as ") { id = String(rest[..<r.lowerBound]).trimmingCharacters(in: .whitespaces); label = String(rest[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        if let i = d.participants.firstIndex(where: { $0.id == id }) { d.participants[i].label = label; d.participants[i].actor = actor }
        else { d.participants.append(.init(id: id, label: Mermaid.cleanLabel(label), actor: actor)) }
        continue
      }
      if lower == "autonumber" { d.autonumber = true; continue }
      if lower.hasPrefix("title ") || lower.hasPrefix("title:") { d.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
      if lower.hasPrefix("activate ") { d.items.append(.activate(String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces))); continue }
      if lower.hasPrefix("deactivate ") { d.items.append(.deactivate(String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces))); continue }
      if lower.hasPrefix("note ") {
        let rest = line.dropFirst(5)
        guard let colon = rest.firstIndex(of: ":") else { throw DiagramSyntaxError(line: n, message: "note needs “: text”") }
        let head = rest[..<colon].trimmingCharacters(in: .whitespaces)
        let text = Mermaid.cleanLabel(String(rest[rest.index(after: colon)...]))
        let hl = head.lowercased()
        var position = "over"
        var who = head
        if hl.hasPrefix("left of ") { position = "left"; who = String(head.dropFirst(8)) }
        else if hl.hasPrefix("right of ") { position = "right"; who = String(head.dropFirst(9)) }
        else if hl.hasPrefix("over ") { position = "over"; who = String(head.dropFirst(5)) }
        let ids = who.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        ids.forEach(ensure)
        d.items.append(.note(participants: ids, position: position, text: text))
        continue
      }
      for kind in ["loop", "alt", "opt", "par", "critical", "break", "rect", "box"] {
        if lower == kind || lower.hasPrefix(kind + " ") {
          let label = String(line.dropFirst(kind.count)).trimmingCharacters(in: .whitespaces)
          if kind == "box" || kind == "rect" { d.items.append(.blockStart(kind: kind, label: kind == "rect" ? "" : label)) }
          else { d.items.append(.blockStart(kind: kind, label: label)) }
          continue
        }
      }
      if lower.hasPrefix("loop ") || lower.hasPrefix("alt ") || lower.hasPrefix("opt ") || lower.hasPrefix("par ") || lower.hasPrefix("critical ") || lower.hasPrefix("break ") || lower.hasPrefix("rect ") || lower.hasPrefix("box ") || ["loop", "alt", "opt", "par", "critical", "break", "rect", "box"].contains(lower) { continue }
      if lower.hasPrefix("else") || lower.hasPrefix("and ") || lower.hasPrefix("option ") || lower == "and" {
        let label = line.drop(while: { $0.isLetter }).trimmingCharacters(in: .whitespaces)
        d.items.append(.blockElse(label: label))
        continue
      }
      if lower == "end" { d.items.append(.blockEnd); continue }
      if lower.hasPrefix("%%") || lower.hasPrefix("link ") || lower.hasPrefix("links ") || lower.hasPrefix("properties ") || lower.hasPrefix("details ") || lower.hasPrefix("acctitle") || lower.hasPrefix("accdescr") || lower.hasPrefix("create ") || lower.hasPrefix("destroy ") { continue }
      // Message: A->>B: text
      guard let arrowRange = line.range(of: #"(<<)?-(-)?(>>|>|x|X|\)|\(|-)?[+-]?"#, options: .regularExpression), let colon = line[arrowRange.upperBound...].firstIndex(of: ":") ?? (line.range(of: ":", range: arrowRange.upperBound..<line.endIndex)?.lowerBound) else {
        throw DiagramSyntaxError(line: n, message: "expected a message like “A->>B: text”")
      }
      var from = String(line[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
      var arrow = String(line[arrowRange])
      var to = String(line[arrowRange.upperBound..<colon]).trimmingCharacters(in: .whitespaces)
      let text = Mermaid.cleanLabel(String(line[line.index(after: colon)...]))
      var activate = false, deactivate = false
      if to.hasPrefix("+") { activate = true; to = String(to.dropFirst()).trimmingCharacters(in: .whitespaces) }
      if to.hasPrefix("-") { deactivate = true; to = String(to.dropFirst()).trimmingCharacters(in: .whitespaces) }
      if arrow.hasSuffix("+") { activate = true; arrow.removeLast() }
      if arrow.hasSuffix("-") && arrow.count > 2 && !arrow.hasSuffix("--") { deactivate = true; arrow.removeLast() }
      let bidirectional = arrow.hasPrefix("<<")
      if bidirectional { arrow = String(arrow.dropFirst(2)) }
      let dotted = arrow.hasPrefix("--")
      var head: SequenceDiagram.Head = .none
      if arrow.hasSuffix(">>") { head = .arrow } else if arrow.hasSuffix(">") { head = .open }
      else if arrow.lowercased().hasSuffix("x") { head = .cross } else if arrow.hasSuffix(")") { head = .async }
      if from.isEmpty { from = to }
      ensure(from); ensure(to)
      d.items.append(.message(from: from, to: to, text: text, line: dotted ? .dotted : .solid, head: head, activate: activate, deactivate: deactivate, bidirectional: bidirectional))
    }
    return d
  }
}

struct SequenceRenderer {
  let diagram: SequenceDiagram
  let theme: DiagramTheme
  private let boxWidth: Double
  private let boxHeight: Double = 34
  private let columnGap: Double = 150
  private let rowHeight: Double = 30
  private let margin: Double = 16
  private var xs: [String: Double] = [:]
  private var rows: [(y: Double, item: SequenceDiagram.Item, height: Double)] = []
  private var totalHeight: Double = 0
  private var blockLevels: [(kind: String, label: String, startY: Double, endY: Double, elses: [(Double, String)], depth: Int)] = []
  private var activations: [(id: String, start: Double, end: Double, level: Int)] = []

  init(diagram: SequenceDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    var w: Double = 90
    for p in diagram.participants { w = max(w, TextMetrics.measure(p.label, style: theme.style(weight: .medium)).width + 28) }
    boxWidth = min(w, 220)
    layout()
  }

  var size: CGSize {
    let cols = Double(diagram.participants.count)
    let width = margin * 2 + 40 + boxWidth + max(0, cols - 1) * columnGap
    return CGSize(width: width, height: totalHeight)
  }

  private var messageStyle: TextStyle { theme.style(theme.fontSize - 1) }

  private mutating func layout() {
    let x0 = margin + boxWidth / 2 + 20
    for (i, p) in diagram.participants.enumerated() { xs[p.id] = x0 + Double(i) * columnGap }
    var y = margin + (diagram.title == nil ? 0 : 28) + boxHeight + 20
    var stack: [(kind: String, label: String, startY: Double, elses: [(Double, String)], depth: Int)] = []
    var active: [String: [Double]] = [:]
    var number = 0
    _ = number
    for item in diagram.items {
      switch item {
      case .message(let from, let to, let text, _, _, let activate, let deactivate, _):
        let h = max(rowHeight, TextMetrics.measure(text, style: messageStyle).height + 14)
        if from == to { rows.append((y, item, h + 14)); y += h + 14 } else { rows.append((y, item, h)); y += h }
        if activate { active[to, default: []].append(y - 4) }
        if deactivate, var starts = active[from], let s = starts.popLast() { active[from] = starts; activations.append((from, s, y, starts.count)) }
      case .note(_, _, let text):
        let h = TextMetrics.measure(text, style: messageStyle).height + 18
        rows.append((y, item, h)); y += h + 6
      case .blockStart(let kind, let label):
        stack.append((kind, label, y, [], stack.count))
        y += 26
      case .blockElse(let label):
        if !stack.isEmpty { stack[stack.count - 1].elses.append((y, label)) }
        y += 22
      case .blockEnd:
        if let b = stack.popLast() { blockLevels.append((b.kind, b.label, b.startY, y + 6, b.elses, b.depth)); y += 14 }
      case .activate(let id): active[id, default: []].append(y)
      case .deactivate(let id):
        if var starts = active[id], let s = starts.popLast() { active[id] = starts; activations.append((id, s, y, starts.count)) }
      }
      number += 1
    }
    for (id, starts) in active { for (i, s) in starts.enumerated() { activations.append((id, s, y, i)) } }
    totalHeight = y + 10 + boxHeight + margin
  }

  func draw<C: Canvas>(on canvas: inout C) {
    let bottom = totalHeight - margin - boxHeight
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    // Blocks (outer first).
    for b in blockLevels.sorted(by: { $0.depth < $1.depth }) {
      let inset = Double(b.depth) * 8
      let r = CGRect(x: margin + inset, y: b.startY, width: size.width - margin * 2 - inset * 2, height: b.endY - b.startY)
      canvas.rect(r, radius: 4, fill: b.kind == "rect" ? theme.clusterFill : nil, stroke: Stroke(color: theme.clusterStroke, width: 1, dash: b.kind == "rect" ? [] : [4, 3]))
      if b.kind != "rect" {
        let tag = b.kind
        let ts = theme.style(theme.fontSize - 2, weight: .semibold, color: theme.secondaryText)
        let tw = TextMetrics.measure(tag, style: ts).width + 10
        canvas.rect(CGRect(x: r.minX, y: r.minY, width: tw, height: 18), radius: 0, fill: theme.clusterStroke.withAlpha(0.25), stroke: nil)
        canvas.text(tag, at: CGPoint(x: r.minX + 5, y: r.minY + 1), width: tw - 10, align: .left, style: ts)
        if !b.label.isEmpty { canvas.text("[\(b.label)]", at: CGPoint(x: r.minX + tw + 6, y: r.minY + 1), width: r.width - tw - 8, align: .left, style: theme.style(theme.fontSize - 2, color: theme.secondaryText)) }
        for (y, label) in b.elses {
          canvas.line(CGPoint(x: r.minX, y: y + 12), CGPoint(x: r.maxX, y: y + 12), stroke: Stroke(color: theme.clusterStroke, width: 1, dash: [4, 3]))
          canvas.text("[\(label)]", at: CGPoint(x: r.minX + 6, y: y + 14), width: r.width - 12, align: .left, style: theme.style(theme.fontSize - 2, color: theme.secondaryText))
        }
      }
    }
    // Lifelines and participant boxes.
    for p in diagram.participants {
      guard let x = xs[p.id] else { continue }
      let top = margin + (diagram.title == nil ? 0 : 28)
      canvas.line(CGPoint(x: x, y: top + boxHeight), CGPoint(x: x, y: bottom), stroke: Stroke(color: theme.nodeStroke, width: 1, dash: [5, 4]))
      for y in [top, bottom] { drawParticipant(p, at: CGPoint(x: x, y: y), on: &canvas) }
    }
    // Activations.
    for a in activations {
      guard let x = xs[a.id] else { continue }
      let w: Double = 10
      canvas.rect(CGRect(x: x - w / 2 + Double(a.level) * 5, y: a.start, width: w, height: max(6, a.end - a.start)), radius: 1, fill: theme.nodeFill, stroke: Stroke(color: theme.nodeStroke))
    }
    // Messages and notes.
    var number = 0
    for row in rows {
      switch row.item {
      case .message(let from, let to, let text, let line, let head, _, _, let bidirectional):
        number += 1
        guard let x1 = xs[from], let x2 = xs[to] else { continue }
        let stroke = Stroke(color: theme.edge, width: 1.2, dash: line == .dotted ? [4, 3] : [])
        let ty = row.y + 4
        if from == to {
          let r = CGRect(x: x1, y: ty + 16, width: 28, height: row.height - 30)
          canvas.path(start: CGPoint(x: x1 + 5, y: r.minY), segments: [(CGPoint(x: r.maxX + 10, y: r.minY), CGPoint(x: r.maxX + 10, y: r.maxY), CGPoint(x: x1 + 5, y: r.maxY))], closed: false, fill: nil, stroke: stroke)
          drawHead(head, at: CGPoint(x: x1 + 5, y: r.maxY), dir: -1, on: &canvas, stroke: stroke)
          canvas.text(numbered(text, number), at: CGPoint(x: x1 + 24, y: ty), width: 300, align: .left, style: messageStyle)
        } else {
          let y = row.y + row.height - 10
          let dir: Double = x2 > x1 ? 1 : -1
          let a = CGPoint(x: x1 + dir * 5, y: y), b = CGPoint(x: x2 - dir * 5, y: y)
          canvas.line(a, b, stroke: stroke)
          drawHead(head, at: b, dir: dir, on: &canvas, stroke: stroke)
          if bidirectional { drawHead(head, at: a, dir: -dir, on: &canvas, stroke: stroke) }
          let width = abs(x2 - x1)
          canvas.text(numbered(text, number), at: CGPoint(x: min(x1, x2), y: ty), width: width, align: .center, style: messageStyle)
        }
      case .note(let ids, let position, let text):
        let s = TextMetrics.measure(text, style: messageStyle)
        let w = s.width + 20
        var r: CGRect
        let x = ids.compactMap { xs[$0] }
        guard let first = x.first else { continue }
        switch position {
        case "left": r = CGRect(x: first - 14 - w, y: row.y, width: w, height: row.height)
        case "right": r = CGRect(x: first + 14, y: row.y, width: w, height: row.height)
        default:
          let lo = x.min()!, hi = x.max()!
          let ww = max(w, hi - lo + 40)
          r = CGRect(x: (lo + hi) / 2 - ww / 2, y: row.y, width: ww, height: row.height)
        }
        canvas.rect(r, radius: 3, fill: theme.noteFill, stroke: Stroke(color: theme.noteStroke))
        canvas.text(text, at: CGPoint(x: r.minX + 10, y: r.minY + 9), width: r.width - 20, align: .center, style: theme.style(theme.fontSize - 1, color: DiagramColor(hex: theme.text.r > 0.5 ? 0xF5F5F7 : 0x3A3200)))
      default: break
      }
    }
  }

  private func numbered(_ text: String, _ n: Int) -> String { diagram.autonumber ? "\(n). \(text)" : text }

  private func drawParticipant<C: Canvas>(_ p: SequenceDiagram.Participant, at c: CGPoint, on canvas: inout C) {
    if p.actor {
      let hx = c.x, hy = c.y + 8
      canvas.ellipse(in: CGRect(x: hx - 6, y: hy - 6, width: 12, height: 12), fill: theme.nodeFill, stroke: Stroke(color: theme.nodeStroke, width: 1.2))
      canvas.line(CGPoint(x: hx, y: hy + 6), CGPoint(x: hx, y: hy + 18), stroke: Stroke(color: theme.nodeStroke, width: 1.2))
      canvas.line(CGPoint(x: hx - 9, y: hy + 10), CGPoint(x: hx + 9, y: hy + 10), stroke: Stroke(color: theme.nodeStroke, width: 1.2))
      canvas.line(CGPoint(x: hx, y: hy + 18), CGPoint(x: hx - 7, y: hy + 27), stroke: Stroke(color: theme.nodeStroke, width: 1.2))
      canvas.line(CGPoint(x: hx, y: hy + 18), CGPoint(x: hx + 7, y: hy + 27), stroke: Stroke(color: theme.nodeStroke, width: 1.2))
      canvas.text(p.label, at: CGPoint(x: c.x - boxWidth / 2, y: c.y + 30), width: boxWidth, align: .center, style: theme.style(theme.fontSize - 1))
    } else {
      let r = CGRect(x: c.x - boxWidth / 2, y: c.y, width: boxWidth, height: boxHeight)
      canvas.rect(r, radius: 6, fill: theme.nodeFill, stroke: Stroke(color: theme.nodeStroke))
      let s = TextMetrics.measure(p.label, style: theme.style(weight: .medium))
      canvas.text(p.label, at: CGPoint(x: r.minX, y: r.midY - s.height / 2), width: r.width, align: .center, style: theme.style(weight: .medium))
    }
  }

  private func drawHead<C: Canvas>(_ head: SequenceDiagram.Head, at tip: CGPoint, dir: Double, on canvas: inout C, stroke: Stroke) {
    let solid = Stroke(color: stroke.color, width: stroke.width, dash: [])
    switch head {
    case .arrow:
      canvas.polygon([tip, CGPoint(x: tip.x - dir * 9, y: tip.y - 4.5), CGPoint(x: tip.x - dir * 9, y: tip.y + 4.5)], fill: stroke.color, stroke: nil)
    case .open, .async:
      canvas.line(tip, CGPoint(x: tip.x - dir * 9, y: tip.y - 5), stroke: solid)
      canvas.line(tip, CGPoint(x: tip.x - dir * 9, y: tip.y + 5), stroke: solid)
    case .cross:
      canvas.line(CGPoint(x: tip.x - 5, y: tip.y - 5), CGPoint(x: tip.x + 5, y: tip.y + 5), stroke: solid)
      canvas.line(CGPoint(x: tip.x - 5, y: tip.y + 5), CGPoint(x: tip.x + 5, y: tip.y - 5), stroke: solid)
    case .none: break
    }
  }
}

