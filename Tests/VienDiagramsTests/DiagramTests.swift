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

  @Test func newKindsParse() throws {
    guard case .gantt(let g) = try Mermaid.parse("gantt\n  dateFormat YYYY-MM-DD\n  section S\n  A :a1, 2024-01-01, 3d\n  B :after a1, 2d\n  M :milestone, 2024-01-04, 0d\n") else { Issue.record("gantt"); return }
    #expect(g.tasks.count == 3 && g.tasks[1].start == g.tasks[0].end && g.tasks[2].milestone)
    guard case .graph(let er) = try Mermaid.parse("erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  CUSTOMER {\n    string name PK\n  }\n") else { Issue.record("er"); return }
    #expect(er.nodes.count == 2 && er.edges.first?.head == .erZeroOrMore && er.edges.first?.tail == .erOne)
    #expect(er.nodes.first?.compartments[1].first == "string  name  PK")
    guard case .gitGraph(let git) = try Mermaid.parse("gitGraph\n  commit\n  branch dev\n  commit id: \"x\" tag: \"v1\"\n  checkout main\n  merge dev\n") else { Issue.record("git"); return }
    #expect(git.commits.count == 3 && git.commits[2].parents.count == 2 && git.commits[1].tag == "v1")
    guard case .mindmap(let mm) = try Mermaid.parse("mindmap\n  root((Root))\n    A\n      A1\n    B[Box]\n") else { Issue.record("mindmap"); return }
    #expect(mm.nodes.count == 4 && mm.nodes[0].children == [1, 3] && mm.nodes[3].shape == .square)
    guard case .xychart(let xy) = try Mermaid.parse("xychart-beta\n  x-axis [a, b]\n  y-axis \"y\" 0 --> 10\n  bar [1, 2]\n  line [2, 3]\n") else { Issue.record("xy"); return }
    #expect(xy.categories == ["a", "b"] && xy.series.count == 2)
    guard case .timeline(let tl) = try Mermaid.parse("timeline\n  title T\n  2002 : LinkedIn\n  2004 : Facebook : Google\n       : Extra\n") else { Issue.record("timeline"); return }
    #expect(tl.periods.count == 2 && tl.periods[1].events == ["Facebook", "Google", "Extra"])
    guard case .journey(let j) = try Mermaid.parse("journey\n  section S\n    Make tea: 5: Me\n") else { Issue.record("journey"); return }
    #expect(j.tasks.first?.score == 5 && j.actors == ["Me"])
    guard case .quadrant(let q) = try Mermaid.parse("quadrantChart\n  x-axis Low --> High\n  quadrant-1 Q1\n  A: [0.3, 0.6]\n") else { Issue.record("quadrant"); return }
    #expect(q.points.count == 1 && q.quadrants[0] == "Q1" && q.xRight == "High")
  }

  @Test func audit2Fixes() throws {
    // Front matter before the diagram keyword.
    guard case .graph = try Mermaid.parse("---\ntitle: X\n---\nerDiagram\n  A ||--o{ B : r\n") else { Issue.record("front matter"); return }
    // ER: direction, word form, key normalisation.
    guard case .graph(let er) = try Mermaid.parse("erDiagram\n  direction LR\n  MANUFACTURER only one to zero or more CAR : makes\n  CAR {\n    string reg PK, FK\n  }\n") else { Issue.record("er"); return }
    #expect(er.direction == .LR)
    #expect(er.edges.first?.tail == .erOne && er.edges.first?.head == .erZeroOrMore)
    #expect(er.node(withID: "CAR")?.compartments[1].first == "string  reg  PK, FK")
    // Mindmap: :::class stripped, multi-line label joined.
    guard case .mindmap(let mm) = try Mermaid.parse("mindmap\n  root((r))\n    A:::urgent\n    id[\"line one\nline two\"]\n") else { Issue.record("mindmap"); return }
    #expect(mm.nodes.contains { $0.text == "A" })
    #expect(mm.nodes.contains { $0.text.contains("line one") && $0.text.contains("line two") })
    // Gantt: vert tag, forward until.
    guard case .gantt(let g) = try Mermaid.parse("gantt\n  dateFormat YYYY-MM-DD\n  A :a1, 2024-01-02, until a2\n  B :a2, 2024-01-08, 2d\n") else { Issue.record("gantt"); return }
    #expect(g.tasks.count == 2 && g.tasks[0].end == g.tasks[1].start)
    // Quadrant: styled point.
    guard case .quadrant(let q) = try Mermaid.parse("quadrantChart\n  A: [0.9, 0.1] radius: 12\n  B:::c: [0.2, 0.3]\n") else { Issue.record("quadrant"); return }
    #expect(q.points.count == 2 && q.points[1].0 == "B")
    // gitGraph: order.
    guard case .gitGraph(let git) = try Mermaid.parse("gitGraph\n  commit\n  branch hotfix order: 3\n  branch develop order: 1\n  checkout develop\n  commit\n") else { Issue.record("git"); return }
    #expect(git.branches == ["main", "develop", "hotfix"])
    // xychart horizontal parses and renders.
    let r = try DiagramRenderer.render("xychart-beta horizontal\n  x-axis [a, b]\n  bar [3, 5]\n", dark: false, maxWidth: 600)
    #expect(r.size.width > 20)
  }


  @Test func unsupportedKindsFailClearly() {
    #expect(throws: DiagramSyntaxError.self) { try DiagramRenderer.render("sankey-beta\n  a,b,1\n", dark: false, maxWidth: 400) }
    #expect(DiagramRenderer.validate("graph TD\n  A --> B\n") == nil)
  }
}
