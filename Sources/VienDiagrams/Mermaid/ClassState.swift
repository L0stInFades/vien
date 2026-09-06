import Foundation

/// `classDiagram` → GraphDiagram with class boxes and UML arrowheads.
enum ClassParser {
  static func parse(_ lines: [(Int, String)]) throws -> GraphDiagram {
    var g = GraphDiagram()
    g.direction = .TB
    var open: String? = nil  // class whose `{ … }` body is being read
    func ensure(_ id: String) {
      if g.node(withID: id) == nil {
        var n = GraphDiagram.Node(id: id, label: id, shape: .classBox)
        n.compartments = [[id], [], []]
        g.nodes.append(n)
      }
    }
    func addMember(_ id: String, _ member: String) {
      ensure(id)
      guard let i = g.nodes.firstIndex(where: { $0.id == id }) else { return }
      let m = member.trimmingCharacters(in: .whitespaces)
      if m.hasPrefix("<<") { g.nodes[i].compartments[0].insert(m, at: 0); return }
      if m.contains("(") { g.nodes[i].compartments[2].append(m) } else { g.nodes[i].compartments[1].append(m) }
    }
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if let o = open {
        if line == "}" { open = nil; continue }
        addMember(o, line.hasSuffix("}") ? String(line.dropLast()) : line)
        if line.hasSuffix("}") { open = nil }
        continue
      }
      let lower = line.lowercased()
      if lower.hasPrefix("direction ") { g.direction = GraphDiagram.Direction(rawValue: String(line.dropFirst(10)).uppercased().replacingOccurrences(of: "TD", with: "TB")) ?? .TB; continue }
      if lower.hasPrefix("class ") {
        var rest = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        var body: String? = nil
        if let br = rest.firstIndex(of: "{") { body = String(rest[rest.index(after: br)...]); rest = String(rest[..<br]).trimmingCharacters(in: .whitespaces) }
        var id = rest
        var label: String? = nil
        if let ann = rest.range(of: "~") { id = String(rest[..<ann.lowerBound]) }
        if let r = rest.range(of: "[\"") , rest.hasSuffix("\"]") { id = String(rest[..<r.lowerBound]); label = String(rest[r.upperBound...].dropLast(2)) }
        ensure(id)
        if let label, let i = g.nodes.firstIndex(where: { $0.id == id }) { g.nodes[i].compartments[0] = [label] }
        if let body {
          if body.trimmingCharacters(in: .whitespaces).hasSuffix("}") {
            for m in body.dropLast().split(separator: "\n") { addMember(id, String(m)) }
          } else { open = id }
        }
        continue
      }
      if lower.hasPrefix("<<") , let end = line.range(of: ">>") {
        let ann = String(line[..<end.upperBound])
        let id = String(line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
        ensure(id)
        if let i = g.nodes.firstIndex(where: { $0.id == id }) { g.nodes[i].compartments[0].insert(ann, at: 0) }
        continue
      }
      if lower.hasPrefix("note ") || lower.hasPrefix("callback") || lower.hasPrefix("link ") || lower.hasPrefix("click ") || lower.hasPrefix("style ") || lower.hasPrefix("classdef ") || lower.hasPrefix("cssclass") || lower.hasPrefix("namespace ") || line == "}" { continue }
      // Member: `Class : +int age`
      if let colon = line.firstIndex(of: ":"), !line.contains("--"), !line.contains("..") {
        let id = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        addMember(id, String(line[line.index(after: colon)...]))
        continue
      }
      // Relation: A <|-- B : label
      guard let m = relation(in: line) else { throw DiagramSyntaxError(line: n, message: "unrecognised statement") }
      ensure(m.from); ensure(m.to)
      g.edges.append(m.edge)
    }
    return g
  }

  private static func relation(in line: String) -> (from: String, to: String, edge: GraphDiagram.Edge)? {
    // Find the arrow token: combinations of <| |> * o -- .. > and cardinalities in quotes.
    guard let r = line.range(of: #"(<\||\*|o|<)?(--|\.\.)(\|>|\*|o|>)?"#, options: .regularExpression) else { return nil }
    let token = String(line[r])
    var left = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
    var right = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
    var label: String? = nil
    if let colon = right.firstIndex(of: ":") { label = String(right[right.index(after: colon)...]).trimmingCharacters(in: .whitespaces); right = String(right[..<colon]).trimmingCharacters(in: .whitespaces) }
    // Strip cardinalities.
    func strip(_ s: String) -> (String, String?) {
      var s = s
      var card: String? = nil
      if let q = s.range(of: #""[^"]*""#, options: .regularExpression) { card = String(s[q]).replacingOccurrences(of: "\"", with: ""); s.removeSubrange(q) }
      return (s.trimmingCharacters(in: .whitespaces), card)
    }
    let (l, lc) = strip(left); let (rr, rc) = strip(right)
    left = l; right = rr
    guard !left.isEmpty, !right.isEmpty else { return nil }
    let dotted = token.contains("..")
    var e = GraphDiagram.Edge(from: left, to: right)
    e.line = dotted ? .dotted : .solid
    e.head = .none
    e.tail = .none
    if token.hasPrefix("<|") { e.tail = .triangle } else if token.hasPrefix("*") { e.tail = .diamondFilled } else if token.hasPrefix("o") { e.tail = .diamond } else if token.hasPrefix("<") { e.tail = .arrow }
    if token.hasSuffix("|>") { e.head = .triangle } else if token.hasSuffix("*") { e.head = .diamondFilled } else if token.hasSuffix("o") { e.head = .diamond } else if token.hasSuffix(">") { e.head = .arrow }
    var parts: [String] = []
    if let lc { parts.append(lc) }
    if let label { parts.append(label) }
    if let rc { parts.append(rc) }
    e.label = parts.isEmpty ? nil : parts.joined(separator: " ")
    // UML draws inheritance pointing at the parent; keep declaration direction for layout but
    // make the parent the rank source when the arrow points left.
    if e.tail != .none && e.head == .none {
      swap(&e.from, &e.to)
      swap(&e.head, &e.tail)
    }
    return (left, right, e)
  }
}

/// `stateDiagram(-v2)` → GraphDiagram with rounded states, start/end dots and composite clusters.
enum StateParser {
  static func parse(_ lines: [(Int, String)]) throws -> GraphDiagram {
    var g = GraphDiagram()
    g.direction = .TB
    var clusterStack: [String] = []
    var startCount = 0, endCount = 0
    func stateID(_ raw: String) -> String {
      let s = raw.trimmingCharacters(in: .whitespaces)
      if s == "[*]" { return "" }
      return s
    }
    func ensure(_ raw: String, isSource: Bool) -> String {
      let s = raw.trimmingCharacters(in: .whitespaces)
      if s == "[*]" {
        if isSource { startCount += 1; let id = "\u{1}start\(startCount)"; g.node(id, label: "", shape: .start, cluster: clusterStack.last); return id }
        endCount += 1; let id = "\u{1}end\(endCount)"; g.node(id, label: "", shape: .end, cluster: clusterStack.last); return id
      }
      g.node(s, label: nil, shape: .rounded, cluster: clusterStack.last)
      return s
    }
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("direction ") { g.direction = GraphDiagram.Direction(rawValue: String(line.dropFirst(10)).uppercased().replacingOccurrences(of: "TD", with: "TB")) ?? .TB; continue }
      if lower.hasPrefix("state ") {
        var rest = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        let composite = rest.hasSuffix("{")
        if composite { rest = String(rest.dropLast()).trimmingCharacters(in: .whitespaces) }
        var id = rest, label: String? = nil
        if rest.hasPrefix("\""), let r = rest.range(of: "\" as ") { label = String(rest[rest.index(after: rest.startIndex)..<r.lowerBound]); id = String(rest[r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        if id.hasSuffix("<<fork>>") || id.hasSuffix("<<join>>") || id.hasSuffix("<<choice>>") {
          let base = id.replacingOccurrences(of: #"<<[a-z]+>>"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
          g.node(base, label: id.contains("choice") ? " " : "", shape: id.contains("choice") ? .diamond : .rect, cluster: clusterStack.last)
          continue
        }
        if composite {
          g.clusters.append(GraphDiagram.Cluster(id: id, title: label ?? id, parent: clusterStack.last, direction: nil))
          clusterStack.append(id)
        } else {
          g.node(id, label: label, shape: .rounded, cluster: clusterStack.last)
        }
        continue
      }
      if line == "}" { _ = clusterStack.popLast(); continue }
      if lower.hasPrefix("note ") || lower.hasPrefix("end note") || lower.hasPrefix("%%") || lower == "--" || lower.hasPrefix("classdef") || lower.hasPrefix("class ") { continue }
      if let r = line.range(of: "-->") {
        let from = ensure(String(line[..<r.lowerBound]), isSource: true)
        var rest = String(line[r.upperBound...])
        var label: String? = nil
        if let colon = rest.firstIndex(of: ":") { label = String(rest[rest.index(after: colon)...]).trimmingCharacters(in: .whitespaces); rest = String(rest[..<colon]) }
        let to = ensure(rest, isSource: false)
        var e = GraphDiagram.Edge(from: from, to: to)
        e.label = label
        g.edges.append(e)
        continue
      }
      if let colon = line.firstIndex(of: ":") {
        let id = ensure(String(line[..<colon]), isSource: true)
        let desc = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        if let i = g.nodes.firstIndex(where: { $0.id == id }) { g.nodes[i].label = desc }
        continue
      }
      _ = ensure(line, isSource: true)
      _ = n
    }
    return g
  }
}
