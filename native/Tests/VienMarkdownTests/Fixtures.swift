import Foundation
@testable import VienMarkdown

/// Shared access to the repository fixtures (spec JSON and the lossless corpus).
enum Fixtures {
  static let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  static let repo = ProcessInfo.processInfo.environment["VIEN_REPO"].map { URL(fileURLWithPath: $0) } ?? packageDir.deletingLastPathComponent()

  struct Example: Decodable, CustomTestStringConvertible, Sendable {
    let markdown: String
    let html: String
    let example: Int
    let section: String
    var testDescription: String { "#\(example) \(section)" }
  }

  static func examples(_ path: String) -> [Example] {
    guard let data = try? Data(contentsOf: repo.appendingPathComponent(path)) else { return [] }
    return (try? JSONDecoder().decode([Example].self, from: data)) ?? []
  }

  static let commonMark = examples("test/specs/commonMark/commonmark.0.31.2.json")
  static let gfm = examples("test/specs/gfm/gfm.0.29.json")

  static var corpus: [URL] {
    let dir = repo.appendingPathComponent("test/corpus/lossless")
    guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }.sorted { $0.path < $1.path }
  }

  /// Whitespace-insensitive HTML comparison in the spirit of the spec's normaliser.
  static func normalize(_ html: String) -> String {
    var s = html.replacingOccurrences(of: " />", with: ">").replacingOccurrences(of: "/>", with: ">")
    var out = ""
    var inPre = false
    var i = s.startIndex
    while i < s.endIndex {
      if s[i...].hasPrefix("<pre") { inPre = true }
      if s[i...].hasPrefix("</pre>") { inPre = false }
      let ch = s[i]
      if !inPre, ch == "\n" {
        let prev = out.last
        var j = s.index(after: i)
        while j < s.endIndex, s[j] == "\n" { j = s.index(after: j) }
        let next = j < s.endIndex ? s[j] : nil
        if prev == ">" || next == "<" || next == nil || prev == nil { i = j; continue }
      }
      out.append(ch)
      i = s.index(after: i)
    }
    s = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return s
  }

  /// A deterministic document with every block kind, for incremental and performance tests.
  static func synthetic(paragraphs: Int) -> String {
    var s = "---\ntitle: Perf\n---\n\n# Performance corpus\n\n"
    for i in 0..<paragraphs {
      s += "## Section \(i)\n\nLorem ipsum **dolor** sit _amet_, `code` and [a link](https://example.com/\(i)) with $x^2$ math. "
      s += "Consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.\n\n"
      s += "- item one\n- item two with **bold**\n  - nested item\n- [ ] task\n\n"
      s += "> quoted text line one\n> quoted line two\n\n"
      s += "```swift\nlet x = \(i)\nprint(x)\n```\n\n"
      s += "| a | b |\n|---|:-:|\n| 1 | 2 |\n\n"
    }
    return s
  }
}

extension Fixtures.Example: CustomStringConvertible {
  var description: String { testDescription }
}

import Testing
