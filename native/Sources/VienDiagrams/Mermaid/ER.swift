import CoreGraphics
import Foundation

/// `erDiagram`: entities become class-like boxes (name + attribute rows), relationships edges with
/// crow's-foot markers; the layered graph layout does the rest.
enum ERParser {
  static func parse(_ lines: [(Int, String)]) throws -> GraphDiagram {
    var g = GraphDiagram()
    g.direction = .TB
    var open: String? = nil
    func ensure(_ raw: String) -> String {
      var id = raw.trimmingCharacters(in: .whitespaces)
      var label = id
      if let br = id.firstIndex(of: "["), id.hasSuffix("]") { label = String(id[id.index(after: br)...].dropLast()); id = String(id[..<br]) }
      id = Mermaid.cleanLabel(id)
      label = Mermaid.cleanLabel(label)
      if !g.nodes.contains(where: { $0.id == id }) {
        var n = GraphDiagram.Node(id: id, label: label, shape: .classBox)
        n.compartments = [[label], []]
        g.nodes.append(n)
      }
      return id
    }
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("%%") { continue }
      if line.lowercased().hasPrefix("direction ") {
        g.direction = GraphDiagram.Direction(rawValue: String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces).uppercased().replacingOccurrences(of: "TD", with: "TB")) ?? .TB
        continue
      }
      if let entity = open {
        if line == "}" { open = nil; continue }
        // `type name PK "comment"`
        var parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var comment: String? = nil
        if let q = line.firstIndex(of: "\"") { comment = Mermaid.cleanLabel(String(line[q...])); parts = line[..<q].split(separator: " ").map(String.init) }
        guard parts.count >= 2 else { continue }
        var text = parts[0] + "  " + parts[1]
        let keys = parts.dropFirst(2).joined(separator: " ").split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init).filter { !$0.isEmpty }
        if !keys.isEmpty { text += "  " + keys.joined(separator: ", ") }
        if let comment { text += "  " + comment }
        if let i = g.nodes.firstIndex(where: { $0.id == entity }) { g.nodes[i].compartments[1].append(text) }
        continue
      }
      if line.hasSuffix("{") {
        open = ensure(String(line.dropLast()))
        continue
      }
      // A rel B : label — <left><line><right> (e.g. ||--o{, }|..|{) or the word forms.
      if let rel = line.range(of: #"(\|\||\|o|o\||\}\||\}o)(--|\.\.)(\|\||\|o|o\||\|\{|o\{)"#, options: .regularExpression) {
        let token = String(line[rel])
        let left = String(token.prefix(2)), lineKind = String(token.dropFirst(2).prefix(2)), right = String(token.suffix(2))
        let from = ensure(String(line[..<rel.lowerBound]))
        var rest = String(line[rel.upperBound...])
        var label: String? = nil
        if let colon = rest.firstIndex(of: ":") { label = Mermaid.cleanLabel(String(rest[rest.index(after: colon)...])); rest = String(rest[..<colon]) }
        var e = GraphDiagram.Edge(from: from, to: ensure(rest))
        e.label = label
        e.line = lineKind == ".." ? .dotted : .solid
        e.tail = head(left)
        e.head = head(right)
        g.edges.append(e)
      } else if let e = wordRelationship(line, ensure: ensure) {
        g.edges.append(e)
      } else {
        throw DiagramSyntaxError(line: n, message: "expected an entity relationship like “A ||--o{ B : label”")
      }
    }
    return g
  }

  /// Word forms: `A only one to zero or more B : label`, `A optionally to many B`, etc.
  private static func wordRelationship(_ line: String, ensure: (String) -> String) -> GraphDiagram.Edge? {
    let colonIdx = line.firstIndex(of: ":")
    let body = String(colonIdx.map { line[..<$0] } ?? line[...]).trimmingCharacters(in: .whitespaces)
    guard let to = body.range(of: #"\s+to\s+"#, options: .regularExpression) else { return nil }
    func cardinality(_ phrase: String) -> GraphDiagram.ArrowHead? {
      let w = phrase.lowercased()
      if w.contains("zero or one") || w.contains("optionally") { return .erZeroOrOne }
      if w.contains("zero or more") || w.contains("many") { return .erZeroOrMore }
      if w.contains("one or more") || w.contains("one or many") { return .erOneOrMore }
      if w.contains("only one") || w.hasSuffix(" one") || w == "one" { return .erOne }
      return nil
    }
    // `<entityA> <cardinality> to <cardinality> <entityB>`: the entities are the outer words.
    let leftWords = String(body[..<to.lowerBound]).split(separator: " ").map(String.init)
    let rightWords = String(body[to.upperBound...]).split(separator: " ").map(String.init)
    guard leftWords.count >= 2, rightWords.count >= 2,
      let tail = cardinality(leftWords.dropFirst().joined(separator: " ")),
      let headMark = cardinality(rightWords.dropLast().joined(separator: " "))
    else { return nil }
    var e = GraphDiagram.Edge(from: ensure(leftWords[0]), to: ensure(rightWords.last!))
    e.tail = tail
    e.head = headMark
    if let colonIdx { e.label = Mermaid.cleanLabel(String(line[line.index(after: colonIdx)...])) }
    return e
  }

  private static func head(_ s: String) -> GraphDiagram.ArrowHead {
    switch s {
    case "||": return .erOne
    case "|o", "o|": return .erZeroOrOne
    case "}o", "o{": return .erZeroOrMore
    default: return .erOneOrMore  // }| |{
    }
  }
}
