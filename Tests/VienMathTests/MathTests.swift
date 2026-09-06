import CoreGraphics
import Foundation
import Testing
@testable import VienMath

@Suite("Math")
struct MathTests {
  static let samples: [(String, String)] = {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/math.txt")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    var out: [(String, String)] = []
    var name = "", body = ""
    for line in text.components(separatedBy: "\n") {
      if line.hasPrefix("=== ") { if !name.isEmpty { out.append((name, body.trimmingCharacters(in: .whitespacesAndNewlines))) }; name = String(line.dropFirst(4)); body = "" } else { body += line + "\n" }
    }
    if !name.isEmpty { out.append((name, body.trimmingCharacters(in: .whitespacesAndNewlines))) }
    return out
  }()

  @Test("samples render", arguments: samples.map(\.0))
  func renders(_ name: String) throws {
    let src = try #require(Self.samples.first { $0.0 == name }?.1)
    let r = try MathRenderer.render(src, display: true, fontSize: 18, dark: false)
    #expect(r.size.width > 10 && r.size.height > 10)
    #expect(r.baseline > 0 && r.baseline <= r.size.height)
    let mathml = try MathRenderer.mathML(src, display: true)
    #expect(mathml.hasPrefix("<math") && mathml.hasSuffix("</math>"))
  }

  @Test func parsing() throws {
    let n = try MathParser.parse("\\frac{a}{b} + x_i^2")
    guard case .row(let items) = n, items.count == 3 else { Issue.record("expected 3 items: \(n)"); return }
    if case .fraction = items[0] {} else { Issue.record("expected fraction") }
    if case .scripts(_, let sub, let sup, _) = items[2] { #expect(sub != nil && sup != nil) } else { Issue.record("expected scripts") }
  }

  @Test func errorsAreReported() {
    #expect(MathRenderer.validate("\\frac{a}") != nil)
    #expect(MathRenderer.validate("\\unknowncommand") != nil)
    #expect(MathRenderer.validate("a^b_c") == nil)
  }

  @Test func mathMLShape() throws {
    let s = try MathRenderer.mathML("\\sqrt{2}", display: false)
    #expect(s.contains("<msqrt><mn>2</mn></msqrt>"))
    let f = try MathRenderer.mathML("\\frac{1}{2}", display: true)
    #expect(f.contains("<mfrac><mn>1</mn><mn>2</mn></mfrac>"))
  }

  @Test func fontHasMathTable() {
    #expect(MathFont.shared.available)
    #expect(MathFont.shared.constant(.axisHeight, size: 100) > 10)
  }
}
