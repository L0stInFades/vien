import Testing
@testable import VienCode

/// The kind of the token covering `needle` (first occurrence) in `code`, or nil when plain.
private func kind(of needle: String, in code: String, _ lang: String) -> TokenKind? {
  let language = Language.named(lang)!
  let bytes = Array(code.utf8)
  let pat = Array(needle.utf8)
  var at = -1
  outer: for i in 0...(bytes.count - pat.count) {
    for j in 0..<pat.count where bytes[i + j] != pat[j] { continue outer }
    at = i
    break
  }
  precondition(at >= 0, "\(needle) not in code")
  return Highlighter.tokens(bytes, language: language).first { $0.range.contains(at) }?.kind
}

@Suite("Syntax highlighting")
struct HighlightTests {
  @Test func swift() {
    let code = """
      import Foundation
      /* outer /* nested */ still comment */
      @MainActor final class Foo: NSObject {
        let s = "a \\" b" + #"raw "q" "#
        var n = 0x1F + 3.5e2
        func run(_ x: Int) -> Bool { #if DEBUG
          return true // done
          #endif }
      }
      """
    #expect(kind(of: "import", in: code, "swift") == .keyword)
    #expect(kind(of: "still comment", in: code, "swift") == .comment)
    #expect(kind(of: "@MainActor", in: code, "swift") == .attribute)
    #expect(kind(of: "NSObject", in: code, "swift") == .type)
    #expect(kind(of: "b\"", in: code, "swift") == .string)
    #expect(kind(of: "\"q\"", in: code, "swift") == .string)
    #expect(kind(of: "0x1F", in: code, "swift") == .number)
    #expect(kind(of: "3.5e2", in: code, "swift") == .number)
    #expect(kind(of: "run", in: code, "swift") == .function)
    #expect(kind(of: "#if", in: code, "swift") == .keyword)
    #expect(kind(of: "true", in: code, "swift") == .constant)
    #expect(kind(of: "// done", in: code, "swift") == .comment)
    #expect(kind(of: "Foo", in: code, "swift") == .type)
  }

  @Test func python() {
    let code = """
      @dataclass
      class Point:
          '''doc
          string'''
          def norm(self) -> float:  # comment
              return (self.x ** 2) ** 0.5 if True else None
      name = f"hi {x}"
      """
    #expect(kind(of: "@dataclass", in: code, "python") == .attribute)
    #expect(kind(of: "class Point", in: code, "python") == .keyword)
    #expect(kind(of: "string'''", in: code, "python") == .string)
    #expect(kind(of: "norm", in: code, "python") == .function)
    #expect(kind(of: "# comment", in: code, "python") == .comment)
    #expect(kind(of: "0.5", in: code, "python") == .number)
    #expect(kind(of: "None", in: code, "python") == .constant)
    #expect(kind(of: "f\"hi", in: code, "py") == .string)
  }

  @Test func cAndRust() {
    let c = "#include <stdio.h>\nint main(void) { char c = '\\n'; /* multi\nline */ return NULL; }"
    #expect(kind(of: "#include", in: c, "c") == .meta)
    #expect(kind(of: "int", in: c, "c") == .type)
    #expect(kind(of: "main", in: c, "c") == .function)
    #expect(kind(of: "'\\n'", in: c, "c") == .string)
    #expect(kind(of: "line */", in: c, "c") == .comment)
    #expect(kind(of: "NULL", in: c, "c") == .constant)
    let rust = "fn f<'a>(x: &'a str) -> Option<u8> { let c = 'x'; let r = r#\"raw\"#; Some(1u8) }"
    #expect(kind(of: "'a>", in: rust, "rust") == nil)
    #expect(kind(of: "'x'", in: rust, "rust") == .string)
    #expect(kind(of: "raw", in: rust, "rust") == .string)
    #expect(kind(of: "1u8", in: rust, "rust") == .number)
    #expect(kind(of: "Option", in: rust, "rust") == .type)
    #expect(kind(of: "fn", in: rust, "rs") == .keyword)
  }

  @Test func markupCSSAndData() {
    let html = "<!DOCTYPE html>\n<div class=\"x\" data-id=1>a &amp; b</div><!-- c --><script>var x = \"<b>\";</script><p>"
    #expect(kind(of: "<!DOCTYPE", in: html, "html") == .meta)
    #expect(kind(of: "<div", in: html, "html") == .tag)
    #expect(kind(of: "class", in: html, "html") == .attribute)
    #expect(kind(of: "\"x\"", in: html, "html") == .string)
    #expect(kind(of: "&amp;", in: html, "html") == .constant)
    #expect(kind(of: "<!-- c -->", in: html, "html") == .comment)
    #expect(kind(of: "\"<b>\"", in: html, "html") == nil, "script bodies stay plain")
    #expect(kind(of: "<p>", in: html, "html") == .tag)
    let css = "@media (max-width: 600px) { .card:hover { color: #fff; margin: 1.5em 0 !important; } }"
    #expect(kind(of: "@media", in: css, "css") == .keyword)
    #expect(kind(of: ".card", in: css, "css") == .attribute)
    #expect(kind(of: ":hover", in: css, "css") == .keyword)
    #expect(kind(of: "color", in: css, "css") == .property)
    #expect(kind(of: "#fff", in: css, "css") == .constant)
    #expect(kind(of: "1.5em", in: css, "css") == .number)
    #expect(kind(of: "!important", in: css, "css") == .keyword)
    let json = "{\"name\": \"vien\", \"n\": 3, \"ok\": true}"
    #expect(kind(of: "\"name\"", in: json, "json") == .property)
    #expect(kind(of: "\"vien\"", in: json, "json") == .string)
    #expect(kind(of: "true", in: json, "json") == .constant)
    let yaml = "---\nname: vien # app\nlist:\n  - item: 1\n  - &anchor two\n"
    #expect(kind(of: "---", in: yaml, "yaml") == .meta)
    #expect(kind(of: "name", in: yaml, "yml") == .property)
    #expect(kind(of: "# app", in: yaml, "yaml") == .comment)
    #expect(kind(of: "item", in: yaml, "yaml") == .property)
    #expect(kind(of: "&anchor", in: yaml, "yaml") == .meta)
    let toml = "[package]\nname = \"vien\"\nversion = 1\n"
    #expect(kind(of: "[package]", in: toml, "toml") == .meta)
    #expect(kind(of: "name", in: toml, "toml") == .property)
  }

  @Test func shellDiffMarkdownMakefile() {
    let sh = "#!/bin/sh\nfor f in *.md; do echo $f \"${HOME}\" # note\ndone"
    #expect(kind(of: "#!/bin/sh", in: sh, "bash") == .meta)
    #expect(kind(of: "for", in: sh, "sh") == .keyword)
    #expect(kind(of: "echo", in: sh, "zsh") == .function)
    #expect(kind(of: "$f", in: sh, "bash") == .variable)
    #expect(kind(of: "# note", in: sh, "bash") == .comment)
    let diff = "--- a\n+++ b\n@@ -1 +1 @@\n-old\n+new\n same"
    #expect(kind(of: "--- a", in: diff, "diff") == .meta)
    #expect(kind(of: "@@", in: diff, "patch") == .meta)
    #expect(kind(of: "-old", in: diff, "diff") == .deleted)
    #expect(kind(of: "+new", in: diff, "diff") == .inserted)
    #expect(kind(of: "same", in: diff, "diff") == nil)
    let md = "# Title\n> quote\n- item `code` [x](u)\n"
    #expect(kind(of: "# Title", in: md, "markdown") == .heading)
    #expect(kind(of: "> quote", in: md, "md") == .comment)
    #expect(kind(of: "`code`", in: md, "markdown") == .string)
    #expect(kind(of: "(u)", in: md, "markdown") == .string)
    let mk = "CC = clang\nall: main.o\n\t$(CC) -o app $(OBJS)\n"
    #expect(kind(of: "CC =", in: mk, "makefile") == .property)
    #expect(kind(of: "all", in: mk, "make") == .function)
    #expect(kind(of: "$(CC)", in: mk, "makefile") == .variable)
  }

  @Test func aliasesAndUnknown() {
    #expect(Language.named("C++")?.name == "cpp")
    #expect(Language.named("ts")?.name == "typescript")
    #expect(Language.named("mermaid") == nil)
    #expect(Language.named("") == nil)
    #expect(Language.names.count >= 40)
  }

  /// Every language must terminate on arbitrary input and return in-bounds, sorted, non-overlapping tokens.
  @Test("robust on random bytes", arguments: Language.names)
  func robustness(language name: String) {
    let language = Language.named(name)!
    var seed: UInt64 = 0x9E3779B97F4A7C15 ^ UInt64(name.utf8.reduce(0) { $0 &* 31 &+ Int($1) })
    func next() -> UInt64 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return seed }
    let alphabet = Array("abc XYZ_09 \n\t\"'`#/*-+=<>@$:;.,(){}[]!?&%\\\u{E9}\u{4E2D}".utf8)
    for _ in 0..<40 {
      let len = Int(next() % 400)
      let bytes = (0..<len).map { _ in alphabet[Int(next() % UInt64(alphabet.count))] }
      let tokens = Highlighter.tokens(bytes, language: language)
      var last = 0
      for t in tokens {
        #expect(t.range.lowerBound >= last && t.range.upperBound <= bytes.count && !t.range.isEmpty, "\(name): bad token \(t)")
        last = t.range.upperBound
      }
    }
  }
}
