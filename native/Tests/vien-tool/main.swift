/// vien-tool — developer utilities that are not tests:
///
///   perf       parse/render timings for synthetic 0.5 MB, 5 MB and (VIEN_PERF_BIG=1) 15 MB documents
///   diagrams   renders Tests/Fixtures/diagrams.txt to /tmp/vien-diagrams/*.png|svg
///   dump       prints the block/inline tree and HTML for Markdown read from stdin
///
/// Conformance and regression checks live in the swift-testing targets (`swift test`).

import Foundation
import VienDiagrams
import VienMarkdown
import VienMath
import ImageIO
import UniformTypeIdentifiers

struct Example: Decodable {
  let markdown: String
  let html: String
  let example: Int
  let section: String
}

let arguments = CommandLine.arguments.dropFirst()
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let repo = ProcessInfo.processInfo.environment["VIEN_REPO"].map { URL(fileURLWithPath: $0) } ?? packageDir.deletingLastPathComponent()
var failures = 0

@MainActor func fail(_ message: String) {
  failures += 1
  print("✗ \(message)")
}

func syntheticDocument(paragraphs: Int) -> String {
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

/// Renders the sample diagrams to /tmp/vien-diagrams/*.png (+ .svg) for eyeballing; fails on parse errors.
@MainActor func runDiagrams() {
  let file = packageDir.appendingPathComponent("Tests/Fixtures/diagrams.txt")
  guard let text = try? String(contentsOf: file, encoding: .utf8) else { fail("no diagram samples"); return }
  let outDir = URL(fileURLWithPath: "/tmp/vien-diagrams")
  try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
  var name = ""
  var body = ""
  var samples: [(String, String)] = []
  for line in text.components(separatedBy: "\n") {
    if line.hasPrefix("=== ") { if !name.isEmpty { samples.append((name, body)) }; name = String(line.dropFirst(4)); body = "" } else { body += line + "\n" }
  }
  if !name.isEmpty { samples.append((name, body)) }
  var count = 0
  for (n, src) in samples {
    for dark in [false, true] {
      do {
        let t = Date()
        let r = try DiagramRenderer.render(src, dark: dark, maxWidth: 800)
        let ms = Date().timeIntervalSince(t) * 1000
        let png = outDir.appendingPathComponent("\(n)\(dark ? "-dark" : "").png")
        if let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) {
          CGImageDestinationAddImage(dest, r.image, nil)
          CGImageDestinationFinalize(dest)
        }
        if !dark { try? r.svg.write(to: outDir.appendingPathComponent("\(n).svg"), atomically: true, encoding: .utf8) }
        print(String(format: "diagram %@%@: %.0f×%.0f in %.1f ms", n, dark ? " (dark)" : "", r.size.width, r.size.height, ms))
        count += 1
      } catch {
        fail("diagram \(n): \(error)")
      }
    }
  }
  print("diagrams: \(count) rendered → \(outDir.path)")
}

/// Renders Tests/Fixtures/math.txt to /tmp/vien-math/*.png for eyeballing.
@MainActor func runMath() {
  let file = packageDir.appendingPathComponent("Tests/Fixtures/math.txt")
  guard let text = try? String(contentsOf: file, encoding: .utf8) else { fail("no math samples"); return }
  let outDir = URL(fileURLWithPath: "/tmp/vien-math")
  try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
  var name = "", body = ""
  var samples: [(String, String)] = []
  for line in text.components(separatedBy: "\n") {
    if line.hasPrefix("=== ") { if !name.isEmpty { samples.append((name, body.trimmingCharacters(in: .whitespacesAndNewlines))) }; name = String(line.dropFirst(4)); body = "" } else { body += line + "\n" }
  }
  if !name.isEmpty { samples.append((name, body.trimmingCharacters(in: .whitespacesAndNewlines))) }
  for (n, src) in samples {
    do {
      let t = Date()
      let r = try MathRenderer.render(src, display: true, fontSize: 20, dark: false)
      let ms = Date().timeIntervalSince(t) * 1000
      let png = outDir.appendingPathComponent("\(n).png")
      if let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, r.image, nil)
        CGImageDestinationFinalize(dest)
      }
      print(String(format: "math %@: %.0f×%.0f in %.1f ms", n, r.size.width, r.size.height, ms))
    } catch { fail("math \(n): \(error)") }
  }
  print("math → \(outDir.path)")
}

let selected = arguments.isEmpty ? ["perf", "diagrams", "math"] : Array(arguments)
for step in selected {
  switch step {
  case "perf": runPerf()
  case "dump": runDump()
  case "diagrams": runDiagrams()
  case "math": runMath()
  default: fail("unknown step \(step)")
  }
}
if failures > 0 {
  print("\(failures) failure(s)")
  exit(1)
}
print("all checks passed")
