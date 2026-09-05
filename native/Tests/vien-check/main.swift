/// vien-check — the quality gate for VienMarkdown, runnable with plain `swift run vien-check`
/// (no XCTest/Testing framework is needed, which keeps the Command Line Tools sufficient).
///
///   spec      CommonMark 0.31.2 + GFM 0.29 examples, ratcheted against Tests/spec-baseline.txt
///   corpus    every fixture under test/corpus/lossless parses and renders; spans cover the source
///   inc       random edits: incremental reparse must equal a full reparse
///   perf      parse/render timings for synthetic 1 MB and 10 MB documents
///
/// Environment: VIEN_REPO (repo root, defaults to ../ relative to the package), UPDATE_BASELINE=1.

import Foundation
import VienMarkdown

struct Example: Decodable {
  let markdown: String
  let html: String
  let example: Int
  let section: String
}

let arguments = CommandLine.arguments.dropFirst()
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let repo = ProcessInfo.processInfo.environment["VIEN_REPO"].map { URL(fileURLWithPath: $0) } ?? packageDir.deletingLastPathComponent()
let baselineURL = packageDir.appendingPathComponent("Tests/spec-baseline.txt")
var failures = 0

@MainActor func fail(_ message: String) {
  failures += 1
  print("✗ \(message)")
}

/// Whitespace-insensitive HTML comparison in the spirit of the spec's normaliser.
@MainActor func normalize(_ html: String) -> String {
  var s = html
  // Self-closing forms and attribute quoting differences.
  s = s.replacingOccurrences(of: " />", with: ">")
  s = s.replacingOccurrences(of: "/>", with: ">")
  // Newlines directly adjacent to tags carry no meaning outside <pre>.
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
      if prev == ">" || next == "<" || next == nil || prev == nil {
        i = j
        continue
      }
    }
    out.append(ch)
    i = s.index(after: i)
  }
  return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

@MainActor func runSpec() {
  var examples: [(String, [Example])] = []
  for (label, path) in [
    ("CommonMark 0.31.2", "test/specs/commonMark/commonmark.0.31.2.json"),
    ("GFM 0.29", "test/specs/gfm/gfm.0.29.json"),
  ] {
    let url = repo.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Example].self, from: data) else {
      fail("cannot load \(path)")
      return
    }
    examples.append((label, decoded))
  }
  let baseline: Set<String> = (try? String(contentsOf: baselineURL, encoding: .utf8))
    .map { Set($0.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty }) } ?? []
  var current: [String] = []
  var summary: [String: (pass: Int, total: Int)] = [:]
  var order: [String] = []
  var options = ParserOptions.default
  options.math = false  // the spec has `$` in plain text
  options.emoji = false
  options.frontMatter = false
  options.footnotes = false
  for (label, list) in examples {
    options.autolinks = label.hasPrefix("GFM")
    var pass = 0
    let only = ProcessInfo.processInfo.environment["VIEN_ONLY"].flatMap(Int.init)
    for ex in list {
      if let only, ex.example != only { continue }
      if ProcessInfo.processInfo.environment["VIEN_TRACE"] == "1" { print("example \(ex.example)"); fflush(stdout) }
      let doc = MarkdownDocument(text: ex.markdown, options: options)
      var renderOptions = HTMLRenderer.Options()
      renderOptions.diagrams = false
      renderOptions.filterDisallowedHTML = options.autolinks
      let html = HTMLRenderer.render(doc, options: renderOptions)
      let ok = html == ex.html || normalize(html) == normalize(ex.html)
      let key = "\(label) #\(ex.example) (\(ex.section))"
      if ok { pass += 1 } else {
        current.append(key)
        if !baseline.contains(key) {
          fail("regression: \(key)\n--- markdown ---\n\(ex.markdown)--- expected ---\n\(ex.html)--- actual ---\n\(html)")
        }
      }
      let sec = "\(label) › \(ex.section)"
      if summary[sec] == nil { order.append(sec) }
      summary[sec, default: (0, 0)].total += 1
      if ok { summary[sec, default: (0, 0)].pass += 1 }
    }
    print("\(label): \(pass)/\(list.count) pass")
  }
  for sec in order where summary[sec]!.pass != summary[sec]!.total {
    let s = summary[sec]!
    print("  \(sec): \(s.pass)/\(s.total)")
  }
  let recovered = baseline.subtracting(current)
  if !recovered.isEmpty {
    print("↑ \(recovered.count) baseline failures now pass; run with UPDATE_BASELINE=1 to ratchet")
  }
  if ProcessInfo.processInfo.environment["UPDATE_BASELINE"] == "1" {
    let text = "# Known spec failures (ratchet). Regenerate with UPDATE_BASELINE=1 swift run vien-check spec\n" + current.sorted().joined(separator: "\n") + "\n"
    try? text.write(to: baselineURL, atomically: true, encoding: .utf8)
    print("baseline written: \(current.count) entries")
  }
}

/// Every byte of the source must be reachable from the tree (blocks or the gaps between them are
/// whitespace/terminators only).
@MainActor func checkCoverage(_ doc: MarkdownDocument, name: String) {
  var cursor = 0
  func gapIsBlank(_ r: Range<Int>) -> Bool {
    for i in r where !doc.bytes[i].isASCIIWhitespace { return false }
    return true
  }
  for b in doc.blocks {
    if b.range.lowerBound < cursor { fail("\(name): overlapping blocks at \(b.range)") }
    if b.range.lowerBound > cursor, !gapIsBlank(cursor..<b.range.lowerBound) {
      fail("\(name): non-blank gap before block at \(b.range.lowerBound)")
    }
    cursor = b.range.upperBound
  }
  if cursor < doc.bytes.count, !gapIsBlank(cursor..<doc.bytes.count) { fail("\(name): trailing content not covered") }
}

extension UInt8 {
  var isASCIIWhitespace: Bool { self == 0x20 || (self >= 0x09 && self <= 0x0D) }
}

@MainActor func runCorpus() {
  let dir = repo.appendingPathComponent("test/corpus/lossless")
  guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { fail("no corpus"); return }
  var count = 0
  for case let url as URL in files where url.pathExtension == "md" {
    guard let data = try? Data(contentsOf: url) else { continue }
    let doc = MarkdownDocument(bytes: Array(data))
    _ = HTMLRenderer.render(doc)
    checkCoverage(doc, name: url.lastPathComponent)
    if doc.text.utf8.elementsEqual(data) == false, data.first != 0xEF {
      fail("\(url.lastPathComponent): text round-trip changed bytes")
    }
    count += 1
  }
  print("corpus: \(count) fixtures parsed")
}

@MainActor func runIncremental() {
  var rng = SystemRandomNumberGenerator()
  let dir = repo.appendingPathComponent("test/corpus/lossless")
  var sources: [String] = []
  if let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
    for case let url as URL in files where url.pathExtension == "md" {
      if let s = try? String(contentsOf: url, encoding: .utf8) { sources.append(s) }
    }
  }
  sources.append(syntheticDocument(paragraphs: 400))
  let snippets = ["\n", "\n\n", "# ", "- ", "> ", "```\n", "$$\n", "*", "**", "`", "[x](y)", "| a | b |\n|---|---|\n", "    ", "\t", "abc", "1. ", "---\n", "<div>\n", "  \n"]
  var edits = 0
  for src in sources {
    var doc = MarkdownDocument(text: src)
    for _ in 0..<40 {
      let n = doc.bytes.count
      // Choose scalar-aligned positions to keep UTF-8 valid.
      func aligned(_ i: Int) -> Int {
        var j = min(i, n)
        while j > 0, j < n, doc.bytes[j] & 0xC0 == 0x80 { j -= 1 }
        return j
      }
      let a = aligned(Int.random(in: 0...n, using: &rng))
      let b = aligned(min(n, a + Int.random(in: 0...40, using: &rng)))
      let replacement = Bool.random(using: &rng) ? Array(snippets.randomElement(using: &rng)!.utf8) : []
      let incremental = doc.replacing(a..<b, with: replacement)
      let full = MarkdownDocument(bytes: incremental.bytes)
      if incremental.lines != full.lines {
        fail("line table mismatch after replacing \(a)..<\(b) with \(String(decoding: replacement, as: UTF8.self).debugDescription)")
        return
      }
      if incremental.blocks != full.blocks {
        fail("incremental mismatch after replacing \(a)..<\(b) with \(String(decoding: replacement, as: UTF8.self).debugDescription)")
        try? doc.text.write(to: URL(fileURLWithPath: "/tmp/vien-inc-before.md"), atomically: true, encoding: .utf8)
        try? incremental.text.write(to: URL(fileURLWithPath: "/tmp/vien-inc-after.md"), atomically: true, encoding: .utf8)
        let ib = Array(incremental.blocks), fb = Array(full.blocks)
        print("  incremental: \(ib.count) blocks, full: \(fb.count) blocks")
        for i in 0..<max(ib.count, fb.count) {
          let x = i < ib.count ? "\(ib[i].kind) \(ib[i].range)" : "—"
          let y = i < fb.count ? "\(fb[i].kind) \(fb[i].range)" : "—"
          if i >= ib.count || i >= fb.count || ib[i] != fb[i] {
            print("  first mismatch at top-level block \(i):\n    incremental: \(x)\n    full:        \(y)")
            break
          }
        }
        return
      }
      doc = incremental
      edits += 1
    }
  }
  print("incremental: \(edits) random edits matched full reparse")
}

@MainActor func syntheticDocument(paragraphs: Int) -> String {
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

@MainActor func runPerf() {
  let sizes = ProcessInfo.processInfo.environment["VIEN_PERF_BIG"] != nil ? [40_000] : [1_300, 13_000]
  for paragraphs in sizes {
    let text = syntheticDocument(paragraphs: paragraphs)
    let bytes = Array(text.utf8)
    let mb = Double(bytes.count) / 1_048_576
    var t = Date()
    let doc = MarkdownDocument(bytes: bytes)
    let parse = Date().timeIntervalSince(t)
    t = Date()
    let html = HTMLRenderer.render(doc)
    let render = Date().timeIntervalSince(t)
    var editable = doc
    let mid = bytes.count / 2
    editable.replace(mid..<mid, with: Array("x".utf8))  // warm up (this copy shares buffers with `doc`)
    t = Date()
    var total = 0.0
    for i in 0..<20 {
      let at = mid + i * 3
      let t0 = Date()
      editable.replace(at..<at, with: Array("y".utf8))
      total += Date().timeIntervalSince(t0)
    }
    let inc = total / 20
    let edited = editable
    print(String(format: "perf %.1f MB: block parse %.1f ms · full HTML %.1f ms · incremental edit %.2f ms · %d blocks · %d KB html",
      mb, parse * 1000, render * 1000, inc * 1000, doc.blocks.count, html.utf8.count / 1024))
    _ = edited
  }
}

@MainActor func dumpTree(_ doc: MarkdownDocument) {
  func walk(_ blocks: [Block], _ depth: Int) {
    for b in blocks {
      let pad = String(repeating: "  ", count: depth)
      let text = b.lines.map { String(decoding: doc.bytes[$0.range], as: UTF8.self) }
      print("\(pad)\(b.kind) \(b.range) lines=\(text)")
      if !b.children.isEmpty { walk(b.children, depth + 1) }
      switch b.kind {
      case .paragraph, .heading, .tableCell:
        for i in doc.inlines(of: b) { print("\(pad)  · \(i.kind) \(i.range) children=\(i.children.count)") }
      default: break
      }
    }
  }
  walk(Array(doc.blocks), 0)
}

@MainActor func runDump() {
  let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
  let doc = MarkdownDocument(text: input)
  dumpTree(doc)
  print("--- html ---")
  print(HTMLRenderer.render(doc), terminator: "")
}

let selected = arguments.isEmpty ? ["spec", "corpus", "inc", "perf"] : Array(arguments)
for step in selected {
  switch step {
  case "spec": runSpec()
  case "corpus": runCorpus()
  case "inc": runIncremental()
  case "perf": runPerf()
  case "dump": runDump()
  default: fail("unknown step \(step)")
  }
}
if failures > 0 {
  print("\(failures) failure(s)")
  exit(1)
}
print("all checks passed")
