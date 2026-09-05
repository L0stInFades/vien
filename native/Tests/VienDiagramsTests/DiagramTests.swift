import CoreGraphics
import Foundation
import Testing
@testable import VienDiagrams

@Suite("Mermaid")
struct DiagramTests {
  static let samples: [(String, String)] = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/diagrams.txt")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    var out: [(String, String)] = []
    var name = "", body = ""
    for line in text.components(separatedBy: "\n") {
      if line.hasPrefix("=== ") { if !name.isEmpty { out.append((name, body)) }; name = String(line.dropFirst(4)); body = "" } else { body += line + "\n" }
    }
    if !name.isEmpty { out.append((name, body)) }
    return out
  }()

  @Test("samples render", arguments: samples.map(\.0))
  func renders(_ name: String) throws {
    let src = try #require(Self.samples.first { $0.0 == name }?.1)
    let r = try DiagramRenderer.render(src, dark: false, maxWidth: 800)
    #expect(r.size.width > 20 && r.size.height > 20)
    #expect(r.svg.hasPrefix("<svg"))
    #expect(r.image.width == Int(r.size.width * 2))
  }

  @Test func flowchartParsing() throws {
    let d = try Mermaid.parse("graph LR\n  A[Start] -->|go| B{Choice}\n  B -. no .-> C((End))\n  A & B ==> D\n  subgraph S[Sub]\n    D --> E\n  end\n")
    guard case .graph(let g) = d else { Issue.record("expected graph"); return }
    #expect(g.direction == .LR)
    #expect(g.nodes.map(\.id) == ["A", "B", "C", "D", "E"])
    #expect(g.nodes[1].shape == .diamond && g.nodes[2].shape == .circle)
    #expect(g.edges.count == 5)
    #expect(g.edges[0].label == "go")
    #expect(g.edges[1].line == .dotted && g.edges[1].label == "no")
    #expect(g.edges[2].line == .thick)
    #expect(g.clusters.first?.title == "Sub")
    #expect(g.node(withID: "E")?.cluster == "S")
  }

  @Test func sequenceParsing() throws {
    let d = try Mermaid.parse("sequenceDiagram\n  Alice->>+Bob: hi\n  Bob-->>-Alice: hello\n  Note over Alice,Bob: done\n")
    guard case .sequence(let s) = d else { Issue.record("expected sequence"); return }
    #expect(s.participants.map(\.id) == ["Alice", "Bob"])
    #expect(s.items.count == 3)
  }

  @Test func unsupportedKindsFailClearly() {
    #expect(throws: DiagramSyntaxError.self) { try DiagramRenderer.render("gantt\n  title x\n", dark: false, maxWidth: 400) }
    #expect(DiagramRenderer.validate("graph TD\n  A --> B\n") == nil)
  }
}
