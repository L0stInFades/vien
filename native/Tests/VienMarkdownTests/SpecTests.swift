import Testing
@testable import VienMarkdown

/// Every CommonMark 0.31.2 and GFM 0.29 example must render to the reference HTML.
@Suite("Specification conformance")
struct SpecTests {
  static var commonMarkOptions: ParserOptions {
    var o = ParserOptions.default
    o.math = false; o.emoji = false; o.frontMatter = false; o.footnotes = false; o.autolinks = false
    return o
  }

  static var gfmOptions: ParserOptions {
    var o = commonMarkOptions
    o.autolinks = true
    return o
  }

  @Test("CommonMark", arguments: Fixtures.commonMark)
  func commonMark(_ ex: Fixtures.Example) {
    var render = HTMLRenderer.Options()
    render.diagrams = false
    let html = HTMLRenderer.render(MarkdownDocument(text: ex.markdown, options: Self.commonMarkOptions), options: render)
    #expect(html == ex.html || Fixtures.normalize(html) == Fixtures.normalize(ex.html), "example \(ex.example) (\(ex.section))\n--- markdown ---\n\(ex.markdown)--- expected ---\n\(ex.html)--- actual ---\n\(html)")
  }

  @Test("GFM", arguments: Fixtures.gfm)
  func gfm(_ ex: Fixtures.Example) {
    var render = HTMLRenderer.Options()
    render.diagrams = false
    render.filterDisallowedHTML = true
    let html = HTMLRenderer.render(MarkdownDocument(text: ex.markdown, options: Self.gfmOptions), options: render)
    #expect(html == ex.html || Fixtures.normalize(html) == Fixtures.normalize(ex.html), "example \(ex.example) (\(ex.section))\n--- markdown ---\n\(ex.markdown)--- expected ---\n\(ex.html)--- actual ---\n\(html)")
  }

  @Test func fixturesAreLoaded() {
    #expect(Fixtures.commonMark.count == 652)
    #expect(Fixtures.gfm.count == 28)
  }
}
