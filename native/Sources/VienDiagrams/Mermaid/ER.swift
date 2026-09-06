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
      if let entity = open {
        if line == "}" { open = nil; continue }
        // `type name PK "comment"`
        var parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var comment: String? = nil
        if let q = line.firstIndex(of: "\"") { comment = Mermaid.cleanLabel(String(line[q...])); parts = line[..<q].split(separator: " ").map(String.init) }
        guard parts.count >= 2 else { continue }
        var text = parts[0] + "  " + parts[1]
        let keys = parts.dropFirst(2).joined(separator: ",")
        if !keys.isEmpty { text += "  " + keys }
        if let comment { text += "  " + comment }
        if let i = g.nodes.firstIndex(where: { $0.id == entity }) { g.nodes[i].compartments[1].append(text) }
        continue
      }
      if line.hasSuffix("{") {
        open = ensure(String(line.dropLast()))
        continue
      }
      // A rel B : label — the relation is <left><line><right>, e.g. ||--o{ or }|..|{
      guard let rel = line.range(of: #"(\|\||\|o|o\||\}\||\}o)(--|\.\.)(\|\||\|o|o\||\|\{|o\{)"#, options: .regularExpression) else {
        throw DiagramSyntaxError(line: n, message: "expected an entity relationship like “A ||--o{ B : label”")
      }
      let token = String(line[rel])
      let left = String(token.prefix(2)), lineKind = String(token.dropFirst(2).prefix(2)), right = String(token.suffix(2))
      let from = ensure(String(line[..<rel.lowerBound]))
      var rest = String(line[rel.upperBound...])
      var label: String? = nil
      if let colon = rest.firstIndex(of: ":") { label = Mermaid.cleanLabel(String(rest[rest.index(after: colon)...])); rest = String(rest[..<colon]) }
      let to = ensure(rest)
      var e = GraphDiagram.Edge(from: from, to: to)
      e.label = label
      e.line = lineKind == ".." ? .dotted : .solid
      e.tail = head(left)
      e.head = head(right)
      g.edges.append(e)
    }
    return g
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
