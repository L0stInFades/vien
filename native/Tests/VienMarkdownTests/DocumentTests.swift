import Foundation
import Testing
@testable import VienMarkdown

@Suite("Lossless corpus")
struct CorpusTests {
  @Test("fixtures parse and their blocks cover the source", arguments: Fixtures.corpus.map(\.lastPathComponent))
  func coverage(_ name: String) throws {
    let url = try #require(Fixtures.corpus.first { $0.lastPathComponent == name })
    let data = try Data(contentsOf: url)
    let doc = MarkdownDocument(bytes: Array(data))
    _ = HTMLRenderer.render(doc)
    func blank(_ r: Range<Int>) -> Bool { r.allSatisfy { doc.bytes[$0] == 0x20 || (doc.bytes[$0] >= 0x09 && doc.bytes[$0] <= 0x0D) } }
    var cursor = 0
    for b in doc.blocks {
      #expect(b.range.lowerBound >= cursor, "overlapping blocks at \(b.range)")
      if b.range.lowerBound > cursor { #expect(blank(cursor..<b.range.lowerBound), "non-blank gap before \(b.range.lowerBound)") }
      cursor = b.range.upperBound
    }
    if cursor < doc.bytes.count { #expect(blank(cursor..<doc.bytes.count), "trailing content not covered") }
    // The document never rewrites what it was given.
    #expect(Array(doc.text.utf8) == Array(data) || data.first == 0xEF)
  }
}

@Suite("Incremental parsing")
struct IncrementalTests {
  struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E3779B97F4A7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
      z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
      return z ^ (z >> 31)
    }
  }

  static let snippets = ["\n", "\n\n", "# ", "- ", "> ", "```\n", "$$\n", "*", "**", "`", "[x](y)", "| a | b |\n|---|---|\n", "    ", "\t", "abc", "1. ", "---\n", "<div>\n", "  \n", "[^1]: note\n", "[^1]"]

  @Test("random edits match a full reparse", arguments: Fixtures.corpus.map(\.lastPathComponent) + ["synthetic"])
  func randomEdits(_ name: String) throws {
    let source: String
    if name == "synthetic" { source = Fixtures.synthetic(paragraphs: 200) } else {
      source = try String(contentsOf: try #require(Fixtures.corpus.first { $0.lastPathComponent == name }), encoding: .utf8)
    }
    var rng = SeededGenerator(state: UInt64(name.utf8.reduce(17) { $0 &* 31 &+ UInt64($1) }))
    var doc = MarkdownDocument(text: source)
    for step in 0..<60 {
      let n = doc.bytes.count
      func aligned(_ i: Int) -> Int {
        var j = min(i, n)
        while j > 0, j < n, doc.bytes[j] & 0xC0 == 0x80 { j -= 1 }
        return j
      }
      let a = aligned(Int.random(in: 0...n, using: &rng))
      let b = aligned(min(n, a + Int.random(in: 0...40, using: &rng)))
      let replacement = Bool.random(using: &rng) ? Array(Self.snippets.randomElement(using: &rng)!.utf8) : []
      doc.replace(a..<b, with: replacement)
      let full = MarkdownDocument(bytes: doc.bytes)
      #expect(doc.lines == full.lines, "\(name) step \(step): line table differs after replacing \(a)..<\(b)")
      #expect(doc.blocks == full.blocks, "\(name) step \(step): blocks differ after replacing \(a)..<\(b) with \(String(decoding: replacement, as: UTF8.self).debugDescription)")
      #expect(doc.references == full.references && doc.footnotes == full.footnotes, "\(name) step \(step): definitions differ")
      if doc.blocks != full.blocks { break }
    }
  }

  @Test func editReturnsAffectedRange() {
    var doc = MarkdownDocument(text: "# Title\n\nParagraph one.\n\nParagraph two.\n")
    let affected = doc.replace(utf16Range: 12..<12, with: "x")
    #expect(affected.lowerBound <= 12 && affected.upperBound >= 13)
    #expect(doc.text == "# Title\n\nParxagraph one.\n\nParagraph two.\n")
  }

  @Test func utf16Bridging() {
    let doc = MarkdownDocument(text: "héllo 😀 world\nsecond")
    #expect(doc.utf16Offset(forByte: doc.byteOffset(forUTF16: 9)) == 9)
    #expect(doc.byteOffset(forUTF16: 6) == 7)  // "héllo " is 7 bytes
    #expect(doc.lines.utf16Start(1) == 15)
  }
}

@Suite("Document queries")
struct QueryTests {
  @Test func headingsAndWordCount() {
    let doc = MarkdownDocument(text: "# One\n\ntext here 中文字\n\n## Two *em*\n\n- item\n")
    let h = doc.headings()
    #expect(h.map(\.level) == [1, 2])
    #expect(h.map(\.text) == ["One", "Two em"])
    let wc = doc.wordCount()
    #expect(wc.words == 1 + 2 + 3 + 2 + 1)  // One / text here / 中 文 字 / Two em / item (markers do not count)
    #expect(wc.paragraphs == 4)
  }

  @Test func pathAtOffset() {
    let doc = MarkdownDocument(text: "> - item\n")
    let path = doc.path(at: 4)
    #expect(path.count == 4)
    if case .blockQuote = path[0].kind {} else { Issue.record("expected block quote") }
    if case .paragraph = path[3].kind {} else { Issue.record("expected paragraph leaf") }
  }

  @Test func extensions() {
    let doc = MarkdownDocument(text: "Math $x^2$ and :smile: and[^n].\n\n[^n]: Note.\n\n$$\nE=mc^2\n$$\n")
    let html = HTMLRenderer.render(doc)
    #expect(html.contains("<span class=\"math inline\">x^2</span>"))
    #expect(html.contains("😄"))
    #expect(html.contains("footnote-ref"))
    #expect(html.contains("<div class=\"math display\">E=mc^2</div>"))
  }
}
