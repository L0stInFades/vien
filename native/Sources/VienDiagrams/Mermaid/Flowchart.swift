import Foundation

/// Parser for `graph` / `flowchart` diagrams.
enum FlowchartParser {
  static func parse(_ lines: [(Int, String)]) throws -> GraphDiagram {
    var g = GraphDiagram()
    var clusterStack: [String] = []
    var clusterCount = 0
    var first = true
    for (n, line) in lines {
      if first {
        first = false
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        if parts.count >= 2, let d = GraphDiagram.Direction(rawValue: String(parts[1]).uppercased().replacingOccurrences(of: "TD", with: "TB")) { g.direction = d }
        if line.hasPrefix("%%{") { first = true }
        continue
      }
      if line.hasPrefix("%%{") { continue }
      let lower = line.lowercased()
      if lower.hasPrefix("subgraph") {
        let rest = line.dropFirst("subgraph".count).trimmingCharacters(in: .whitespaces)
        var id: String
        var title: String? = nil
        if let br = rest.firstIndex(of: "["), rest.hasSuffix("]") {
          id = String(rest[..<br]).trimmingCharacters(in: .whitespaces)
          title = Mermaid.cleanLabel(String(rest[rest.index(after: br)..<rest.index(before: rest.endIndex)]))
        } else {
          id = Mermaid.cleanLabel(rest)
          title = id
        }
        if id.isEmpty { clusterCount += 1; id = "subgraph\(clusterCount)" }
        let clusterID = id.replacingOccurrences(of: " ", with: "_")
        g.clusters.append(GraphDiagram.Cluster(id: clusterID, title: title, parent: clusterStack.last, direction: nil))
        clusterStack.append(clusterID)
        continue
      }
      if lower == "end" {
        _ = clusterStack.popLast()
        continue
      }
      if lower.hasPrefix("direction ") {
        if let d = GraphDiagram.Direction(rawValue: String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "TD", with: "TB")),
          let last = clusterStack.last, let i = g.clusters.firstIndex(where: { $0.id == last })
        {
          g.clusters[i].direction = d
        }
        continue
      }
      if lower.hasPrefix("classdef ") {
        let rest = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
        guard let sp = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
        let names = rest[..<sp].split(separator: ",").map(String.init)
        let style = GraphDiagram.NodeStyle.parse(String(rest[sp...]))
        for name in names { g.classDefs[name] = style }
        continue
      }
      if lower.hasPrefix("class ") {
        let rest = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        let parts = rest.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2 else { continue }
        let ids = parts[0].split(separator: ",").map(String.init)
        let cls = String(parts[1])
        for id in ids { if let i = g.nodes.firstIndex(where: { $0.id == id }) { g.nodes[i].classes.append(cls) } }
        continue
      }
      if lower.hasPrefix("style ") {
        let rest = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
        guard let sp = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
        let id = String(rest[..<sp])
        let style = GraphDiagram.NodeStyle.parse(String(rest[sp...]))
        if let i = g.nodes.firstIndex(where: { $0.id == id }) { g.nodes[i].style = style }
        else if let i = g.clusters.firstIndex(where: { $0.id == id }) { g.clusters[i].style = style }
        continue
      }
      if lower.hasPrefix("linkstyle ") || lower.hasPrefix("click ") || lower.hasPrefix("accTitle") || lower.hasPrefix("accDescr") || lower.hasPrefix("title ") {
        if lower.hasPrefix("title ") { g.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        continue
      }
      try parseStatement(line, lineNumber: n, into: &g, cluster: clusterStack.last)
    }
    return g
  }

  // MARK: - Statements: node chains with edges

  private struct Scanner {
    let chars: [Character]
    var i = 0
    init(_ s: String) { chars = Array(s) }
    var atEnd: Bool { i >= chars.count }
    func peek(_ k: Int = 0) -> Character? { i + k < chars.count ? chars[i + k] : nil }
    mutating func skipSpaces() { while let c = peek(), c == " " || c == "\t" { i += 1 } }
    func rest() -> String { String(chars[i...]) }
    func startsWith(_ s: String) -> Bool {
      let a = Array(s)
      guard i + a.count <= chars.count else { return false }
      return Array(chars[i..<(i + a.count)]) == a
    }
  }

  private static let shapeDelimiters: [(String, String, GraphDiagram.Shape)] = [
    ("(((", ")))", .doubleCircle), ("([", "])", .stadium), ("[[", "]]", .subroutine), ("[(", ")]", .cylinder),
    ("((", "))", .circle), ("{{", "}}", .hexagon), ("[/", "/]", .parallelogram), ("[\\", "\\]", .parallelogramAlt),
    ("[/", "\\]", .trapezoid), ("[\\", "/]", .trapezoidAlt), ("[", "]", .rect), ("(", ")", .rounded), ("{", "}", .diamond),
    (">", "]", .asymmetric),
  ]

  static func parseStatement(_ line: String, lineNumber: Int, into g: inout GraphDiagram, cluster: String?) throws {
    var sc = Scanner(line)
    var previous: [String] = try parseNodeGroup(&sc, into: &g, cluster: cluster, line: lineNumber)
    while true {
      sc.skipSpaces()
      if sc.atEnd { break }
      guard let edge = parseEdge(&sc, line: lineNumber) else {
        throw DiagramSyntaxError(line: lineNumber, message: "unexpected “\(sc.rest().prefix(12))”")
      }
      let next = try parseNodeGroup(&sc, into: &g, cluster: cluster, line: lineNumber)
      for a in previous { for b in next {
        var e = edge
        e.from = a; e.to = b
        g.edges.append(e)
      } }
      previous = next
    }
  }

  /// `A & B` or a single node; each node may carry a shape and label, and `:::class`.
  private static func parseNodeGroup(_ sc: inout Scanner, into g: inout GraphDiagram, cluster: String?, line: Int) throws -> [String] {
    var ids: [String] = []
    while true {
      sc.skipSpaces()
      let id = try parseNode(&sc, into: &g, cluster: cluster, line: line)
      ids.append(id)
      sc.skipSpaces()
      if sc.peek() == "&" { sc.i += 1; continue }
      break
    }
    return ids
  }

  private static func parseNode(_ sc: inout Scanner, into g: inout GraphDiagram, cluster: String?, line: Int) throws -> String {
    sc.skipSpaces()
    var id = ""
    while let c = sc.peek(), c.isLetter || c.isNumber || c == "_" || c == "-" || c == "." || c.unicodeScalars.first!.value > 0x7F {
      // A `-` that begins an edge (`-->`, `---`, `-.`) ends the identifier.
      if c == "-", sc.startsWith("--") || sc.startsWith("-.") || sc.startsWith("-)") { break }
      id.append(c)
      sc.i += 1
    }
    if id.isEmpty {
      // A quoted id/label without a shape.
      if sc.peek() == "\"" {
        sc.i += 1
        var s = ""
        while let c = sc.peek(), c != "\"" { s.append(c); sc.i += 1 }
        sc.i += 1
        id = s
      } else {
        throw DiagramSyntaxError(line: line, message: "expected a node")
      }
    }
    var label: String? = nil
    var shape: GraphDiagram.Shape? = nil
    for (open, close, sh) in shapeDelimiters where sc.startsWith(open) {
      // Trapezoid variants share openers: pick by the closer that actually appears.
      let saved = sc.i
      sc.i += open.count
      var s = ""
      var quote = false
      var found = false
      while !sc.atEnd {
        if sc.peek() == "\"" { quote.toggle() }
        if !quote, sc.startsWith(close) { found = true; break }
        s.append(sc.peek()!)
        sc.i += 1
      }
      if !found { sc.i = saved; continue }
      sc.i += close.count
      label = Mermaid.cleanLabel(s)
      shape = sh
      break
    }
    if sc.startsWith(":::") {
      sc.i += 3
      var cls = ""
      while let c = sc.peek(), c.isLetter || c.isNumber || c == "_" || c == "-" { cls.append(c); sc.i += 1 }
      g.node(id, label: label, shape: shape, cluster: cluster)
      if let i = g.nodes.firstIndex(where: { $0.id == id }) { g.nodes[i].classes.append(cls) }
      return id
    }
    g.node(id, label: label, shape: shape, cluster: cluster)
    return id
  }

  /// Edges: `-->`, `---`, `-.->`, `==>`, `--o`, `--x`, `<-->`, `~~~`, with optional `|label|` or inline `-- text -->`.
  private static func parseEdge(_ sc: inout Scanner, line: Int) -> GraphDiagram.Edge? {
    sc.skipSpaces()
    var e = GraphDiagram.Edge(from: "", to: "")
    var tailArrow = false
    if sc.startsWith("<") { tailArrow = true; sc.i += 1 }
    if sc.startsWith("o") && (sc.startsWith("o--") || sc.startsWith("o==") || sc.startsWith("o-.")) { e.tail = .circle; sc.i += 1 }
    else if sc.startsWith("x") && (sc.startsWith("x--") || sc.startsWith("x==") || sc.startsWith("x-.")) { e.tail = .cross; sc.i += 1 }
    let start = sc.i
    guard let first = sc.peek(), first == "-" || first == "=" || first == "~" else { return nil }
    let lineChar = first
    var count = 0
    while sc.peek() == lineChar { count += 1; sc.i += 1 }
    if lineChar == "-" && count == 1 && sc.peek() == "." {
      // dotted: -.-> or -. text .->
      e.line = .dotted
      var dots = 0
      while sc.peek() == "." { dots += 1; sc.i += 1 }
      sc.skipSpaces()
      if sc.peek() != "-" && sc.peek() != ">" {
        // inline label: -. text .->
        var text = ""
        while !sc.atEnd, !sc.startsWith(".-") { text.append(sc.peek()!); sc.i += 1 }
        e.label = Mermaid.cleanLabel(text)
        while sc.peek() == "." { sc.i += 1 }
      }
      while sc.peek() == "-" { sc.i += 1 }
    } else if lineChar == "=" {
      e.line = .thick
      e.minLength = max(1, count - 1)
    } else if lineChar == "~" {
      e.line = .invisible
      e.head = .none
      return e
    } else {
      e.minLength = max(1, count - 2)
    }
    // Arrow head.
    if sc.peek() == ">" { e.head = .arrow; sc.i += 1 }
    else if sc.peek() == "o", !(sc.peek(1)?.isLetter ?? false) { e.head = .circle; sc.i += 1 }
    else if sc.peek() == "x", !(sc.peek(1)?.isLetter ?? false) { e.head = .cross; sc.i += 1 }
    else if count >= 2 || e.line == .dotted {
      // `-- text -->`: text follows, then the closing dashes/arrow.
      if e.label == nil {
        let save = sc.i
        sc.skipSpaces()
        var text = ""
        var closed = false
        while !sc.atEnd {
          if sc.startsWith("-->") || sc.startsWith("---") || sc.startsWith("==>") || sc.startsWith("===") || sc.startsWith("--o") || sc.startsWith("--x") { closed = true; break }
          text.append(sc.peek()!)
          sc.i += 1
        }
        if closed, !text.trimmingCharacters(in: .whitespaces).isEmpty {
          e.label = Mermaid.cleanLabel(text)
          while sc.peek() == "-" || sc.peek() == "=" { sc.i += 1 }
          if sc.peek() == ">" { e.head = .arrow; sc.i += 1 }
          else if sc.peek() == "o" { e.head = .circle; sc.i += 1 }
          else if sc.peek() == "x" { e.head = .cross; sc.i += 1 }
          else { e.head = .none }
        } else {
          sc.i = save
          e.head = .none
        }
      } else {
        e.head = .none
      }
    } else {
      sc.i = start
      return nil
    }
    if tailArrow { e.tail = .arrow }
    // |label|
    sc.skipSpaces()
    if sc.peek() == "|" {
      sc.i += 1
      var text = ""
      while let c = sc.peek(), c != "|" { text.append(c); sc.i += 1 }
      sc.i += 1
      e.label = Mermaid.cleanLabel(text)
    }
    return e
  }
}
