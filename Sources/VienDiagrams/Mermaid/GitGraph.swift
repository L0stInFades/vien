import CoreGraphics
import Foundation

public struct GitGraphDiagram: Sendable {
  public enum CommitType: Sendable { case normal, reverse, highlight }
  public struct Commit: Sendable {
    var id: String
    var branch: Int
    var type: CommitType = .normal
    var tag: String?
    /// Indexes of parent commits (a merge has two, a cherry-pick links to its source with a dashed line).
    var parents: [Int] = []
    var cherryPick: Int?
  }
  var branches: [String] = ["main"]
  var commits: [Commit] = []
  var vertical = false
}

enum GitGraphParser {
  static func parse(_ lines: [(Int, String)]) throws -> GitGraphDiagram {
    var d = GitGraphDiagram()
    let header = lines.first?.1.lowercased() ?? ""
    d.vertical = header.contains("tb:") || header.contains("bt:")
    var current = 0
    var heads: [Int: Int] = [:]  // branch → last commit index
    var branchOrder: [String: Int] = [:]
    var counter = 0
    func option(_ line: String, _ key: String) -> String? {
      guard let r = line.range(of: "\\b\(key)\\s*:\\s*", options: .regularExpression) else { return nil }
      var rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
      if rest.hasPrefix("\"") { rest = String(rest.dropFirst()); if let q = rest.firstIndex(of: "\"") { rest = String(rest[..<q]) } }
      else { rest = String(rest.split(separator: " ").first ?? "") }
      return rest
    }
    func type(_ line: String) -> GitGraphDiagram.CommitType {
      switch option(line, "type")?.uppercased() { case "REVERSE": return .reverse; case "HIGHLIGHT": return .highlight; default: return .normal }
    }
    var inOptions = false
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if inOptions { if lower == "end" { inOptions = false }; continue }
      if lower == "options" { inOptions = true; continue }
      if lower.hasPrefix("commit") {
        counter += 1
        var c = GitGraphDiagram.Commit(id: option(line, "id") ?? "\(counter)", branch: current, type: type(line), tag: option(line, "tag"))
        if let h = heads[current] { c.parents = [h] }
        d.commits.append(c)
        heads[current] = d.commits.count - 1
        continue
      }
      if lower.hasPrefix("branch ") {
        let rest = String(line.dropFirst(7))
        let name = String(rest.split(separator: " ").first ?? "")
        if let orderStr = option(rest, "order"), let order = Int(orderStr) { branchOrder[name] = order }
        if !d.branches.contains(name) { d.branches.append(name) }
        let index = d.branches.firstIndex(of: name)!
        if let h = heads[current] { heads[index] = h }  // branches from the current head
        current = index
        continue
      }
      if lower.hasPrefix("checkout ") || lower.hasPrefix("switch ") {
        let name = String(line.split(separator: " ").dropFirst().first ?? "")
        guard let index = d.branches.firstIndex(of: name) else { throw DiagramSyntaxError(line: n, message: "unknown branch “\(name)”") }
        current = index
        continue
      }
      if lower.hasPrefix("merge ") {
        let name = String(line.dropFirst(6).split(separator: " ").first ?? "")
        guard let other = d.branches.firstIndex(of: name) else { throw DiagramSyntaxError(line: n, message: "unknown branch “\(name)”") }
        counter += 1
        var c = GitGraphDiagram.Commit(id: option(line, "id") ?? "\(counter)", branch: current, type: type(line), tag: option(line, "tag"))
        c.parents = [heads[current], heads[other]].compactMap { $0 }
        d.commits.append(c)
        heads[current] = d.commits.count - 1
        continue
      }
      if lower.hasPrefix("cherry-pick") {
        guard let id = option(line, "id"), let source = d.commits.firstIndex(where: { $0.id == id }) else { throw DiagramSyntaxError(line: n, message: "cherry-pick needs the id of an existing commit") }
        counter += 1
        var c = GitGraphDiagram.Commit(id: "\(counter)", branch: current, tag: option(line, "tag"))
        if let h = heads[current] { c.parents = [h] }
        c.cherryPick = source
        d.commits.append(c)
        heads[current] = d.commits.count - 1
        continue
      }
      throw DiagramSyntaxError(line: n, message: "expected commit, branch, checkout, merge or cherry-pick")
    }
    // Order the lanes: explicit `order:` first (ascending), then declaration order.
    if !branchOrder.isEmpty {
      // Effective order: the explicit `order:` value, else the branch's declaration index.
      func effective(_ name: String, _ offset: Int) -> Int { branchOrder[name] ?? offset }
      let ordered = d.branches.enumerated().sorted { a, b in
        let oa = effective(a.element, a.offset), ob = effective(b.element, b.offset)
        return oa != ob ? oa < ob : a.offset < b.offset
      }
      let remap = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.offset, $0.offset) })
      d.branches = ordered.map { $0.element }
      for i in d.commits.indices { d.commits[i].branch = remap[d.commits[i].branch] ?? d.commits[i].branch }
    }
    return d
  }
}

struct GitGraphRenderer {
  let diagram: GitGraphDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let step: Double = 56
  private let lane: Double = 44
  private var labelWidth: Double = 0
  private var idStyle: TextStyle { theme.style(theme.fontSize - 4, color: theme.secondaryText) }

  init(diagram: GitGraphDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    labelWidth = (diagram.branches.map { TextMetrics.measure($0, style: theme.style(theme.fontSize - 2, weight: .medium)).width }.max() ?? 0) + 24
  }

  var size: CGSize {
    let lanes = Double(diagram.branches.count)
    let commits = Double(max(1, diagram.commits.count))
    if diagram.vertical { return CGSize(width: margin * 2 + labelWidth + lanes * lane + 60, height: margin * 2 + commits * step + 20) }
    return CGSize(width: margin * 2 + labelWidth + commits * step + 20, height: margin * 2 + lanes * lane + 24)
  }

  private func point(_ index: Int) -> CGPoint {
    let c = diagram.commits[index]
    if diagram.vertical { return CGPoint(x: margin + labelWidth + Double(c.branch) * lane + lane / 2, y: margin + 20 + Double(index) * step + step / 2) }
    return CGPoint(x: margin + labelWidth + Double(index) * step + step / 2, y: margin + Double(c.branch) * lane + lane / 2)
  }

  func draw<C: Canvas>(on canvas: inout C) {
    func color(_ branch: Int) -> DiagramColor { theme.palette[branch % theme.palette.count] }
    // Branch labels.
    for (i, name) in diagram.branches.enumerated() {
      let style = theme.style(theme.fontSize - 2, weight: .medium, color: color(i))
      if diagram.vertical {
        canvas.text(name, at: CGPoint(x: margin + labelWidth + Double(i) * lane - 20, y: margin), width: lane + 40, align: .center, style: style)
      } else {
        canvas.text(name, at: CGPoint(x: margin, y: margin + Double(i) * lane + lane / 2 - 8), width: labelWidth - 8, align: .right, style: style)
      }
    }
    // Links: parents first so dots draw on top.
    for (i, c) in diagram.commits.enumerated() {
      let p = point(i)
      for parent in c.parents {
        let q = point(parent)
        let stroke = Stroke(color: color(diagram.commits[parent].branch == c.branch ? c.branch : diagram.commits[parent].branch), width: 2)
        if diagram.commits[parent].branch == c.branch {
          canvas.line(q, p, stroke: stroke)
        } else if diagram.vertical {
          canvas.path(start: q, segments: [(CGPoint(x: q.x, y: (q.y + p.y) / 2), CGPoint(x: p.x, y: (q.y + p.y) / 2), p)], closed: false, fill: nil, stroke: stroke)
        } else {
          canvas.path(start: q, segments: [(CGPoint(x: (q.x + p.x) / 2, y: q.y), CGPoint(x: (q.x + p.x) / 2, y: p.y), p)], closed: false, fill: nil, stroke: stroke)
        }
      }
      if let source = c.cherryPick {
        canvas.line(point(source), p, stroke: Stroke(color: theme.edge, width: 1, dash: [4, 3]))
      }
    }
    for (i, c) in diagram.commits.enumerated() {
      let p = point(i)
      let fill = color(c.branch)
      switch c.type {
      case .normal:
        canvas.ellipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14), fill: fill, stroke: nil)
      case .highlight:
        canvas.rect(CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16), radius: 3, fill: fill.withAlpha(0.35), stroke: Stroke(color: fill, width: 2))
      case .reverse:
        canvas.ellipse(in: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14), fill: fill, stroke: nil)
        let white = Stroke(color: DiagramColor(hex: 0xFFFFFF), width: 1.5)
        canvas.line(CGPoint(x: p.x - 3.5, y: p.y - 3.5), CGPoint(x: p.x + 3.5, y: p.y + 3.5), stroke: white)
        canvas.line(CGPoint(x: p.x - 3.5, y: p.y + 3.5), CGPoint(x: p.x + 3.5, y: p.y - 3.5), stroke: white)
      }
      if c.parents.count > 1 {  // merge ring
        canvas.ellipse(in: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20), fill: nil, stroke: Stroke(color: fill, width: 1.5))
      }
      if diagram.vertical {
        canvas.text(c.id, at: CGPoint(x: p.x + 14, y: p.y - 7), width: 120, align: .left, style: idStyle)
      } else {
        canvas.text(c.id, at: CGPoint(x: p.x - step / 2, y: p.y + 12), width: step, align: .center, style: idStyle)
      }
      if let tag = c.tag {
        let style = theme.style(theme.fontSize - 3, weight: .medium)
        let w = TextMetrics.measure(tag, style: style).width + 10
        let origin = diagram.vertical ? CGPoint(x: p.x - w - 14, y: p.y - 9) : CGPoint(x: p.x - w / 2, y: p.y - 30)
        canvas.rect(CGRect(x: origin.x, y: origin.y, width: w, height: 18), radius: 4, fill: theme.noteFill, stroke: Stroke(color: theme.noteStroke, width: 1))
        canvas.text(tag, at: CGPoint(x: origin.x + 5, y: origin.y + 2), width: w - 10, align: .center, style: style)
      }
    }
  }
}
