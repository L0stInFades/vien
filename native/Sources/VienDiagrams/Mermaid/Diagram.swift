import CoreGraphics
import Foundation

/// Colours and metrics for a diagram. The defaults follow macOS system colours so diagrams sit in the
/// editor like native controls rather than a web widget.
public struct DiagramTheme: Sendable {
  public var background: DiagramColor
  public var nodeFill: DiagramColor
  public var nodeStroke: DiagramColor
  public var text: DiagramColor
  public var secondaryText: DiagramColor
  public var edge: DiagramColor
  public var accent: DiagramColor
  public var clusterFill: DiagramColor
  public var clusterStroke: DiagramColor
  public var noteFill: DiagramColor
  public var noteStroke: DiagramColor
  public var fontSize: Double = 13
  public var palette: [DiagramColor]

  public static let light = DiagramTheme(
    background: DiagramColor(hex: 0xFFFFFF, alpha: 0),
    nodeFill: DiagramColor(hex: 0xF2F2F7),
    nodeStroke: DiagramColor(hex: 0x8E8E93, alpha: 0.6),
    text: DiagramColor(hex: 0x1D1D1F),
    secondaryText: DiagramColor(hex: 0x6E6E73),
    edge: DiagramColor(hex: 0x6E6E73),
    accent: DiagramColor(hex: 0x007AFF),
    clusterFill: DiagramColor(hex: 0x8E8E93, alpha: 0.07),
    clusterStroke: DiagramColor(hex: 0x8E8E93, alpha: 0.45),
    noteFill: DiagramColor(hex: 0xFFF8D6),
    noteStroke: DiagramColor(hex: 0xE5D48A),
    palette: [0x007AFF, 0x34C759, 0xFF9500, 0xAF52DE, 0xFF3B30, 0x5AC8FA, 0xFFCC00, 0xFF2D55, 0x5856D6, 0xA2845E].map { DiagramColor(hex: $0) }
  )

  public static let dark = DiagramTheme(
    background: DiagramColor(hex: 0x000000, alpha: 0),
    nodeFill: DiagramColor(hex: 0x2C2C2E),
    nodeStroke: DiagramColor(hex: 0x98989D, alpha: 0.6),
    text: DiagramColor(hex: 0xF5F5F7),
    secondaryText: DiagramColor(hex: 0x98989D),
    edge: DiagramColor(hex: 0x98989D),
    accent: DiagramColor(hex: 0x0A84FF),
    clusterFill: DiagramColor(hex: 0x98989D, alpha: 0.1),
    clusterStroke: DiagramColor(hex: 0x98989D, alpha: 0.5),
    noteFill: DiagramColor(hex: 0x4A4520),
    noteStroke: DiagramColor(hex: 0x8A7F3A),
    palette: [0x0A84FF, 0x30D158, 0xFF9F0A, 0xBF5AF2, 0xFF453A, 0x64D2FF, 0xFFD60A, 0xFF375F, 0x5E5CE6, 0xAC8E68].map { DiagramColor(hex: $0) }
  )

  public func style(_ size: Double? = nil, weight: TextWeight = .regular, color: DiagramColor? = nil, italic: Bool = false, mono: Bool = false) -> TextStyle {
    TextStyle(size: size ?? fontSize, weight: weight, color: color ?? text, italic: italic, monospace: mono)
  }
}

public struct DiagramSyntaxError: Error, CustomStringConvertible, Sendable {
  public let line: Int
  public let message: String
  public var description: String { "line \(line): \(message)" }
}

/// A parsed Mermaid diagram of any supported kind.
public enum Diagram: Sendable {
  case graph(GraphDiagram)
  case sequence(SequenceDiagram)
  case pie(PieDiagram)
  case unsupported(String)
}

public enum Mermaid {
  /// Splits into logical lines: comments (`%%`) and blank lines dropped, `;` treated as a line break
  /// outside quotes and brackets.
  static func lines(_ source: String) -> [(Int, String)] {
    var out: [(Int, String)] = []
    for (n, raw) in source.components(separatedBy: "\n").enumerated() {
      var line = raw.replacingOccurrences(of: "\r", with: "")
      if let c = line.range(of: "%%") , !insideQuotes(line, c.lowerBound) { line = String(line[..<c.lowerBound]) }
      // Split on `;` outside quotes/brackets.
      var depth = 0, quote = false
      var current = ""
      for ch in line {
        if ch == "\"" { quote.toggle() }
        if !quote { if "([{".contains(ch) { depth += 1 } else if ")]}".contains(ch) { depth -= 1 } }
        if ch == ";" && !quote && depth <= 0 {
          let t = current.trimmingCharacters(in: .whitespaces)
          if !t.isEmpty { out.append((n + 1, t)) }
          current = ""
        } else {
          current.append(ch)
        }
      }
      let t = current.trimmingCharacters(in: .whitespaces)
      if !t.isEmpty { out.append((n + 1, t)) }
    }
    return out
  }

  private static func insideQuotes(_ s: String, _ i: String.Index) -> Bool {
    s[..<i].filter { $0 == "\"" }.count % 2 == 1
  }

  /// Parses the diagram; the first meaningful line selects the kind.
  public static func parse(_ source: String) throws -> Diagram {
    let ls = lines(source)
    guard let first = ls.first(where: { !$0.1.hasPrefix("%%{") }) else { throw DiagramSyntaxError(line: 1, message: "empty diagram") }
    let head = first.1.trimmingCharacters(in: .whitespaces)
    let keyword = head.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)?.lowercased() ?? ""
    switch keyword {
    case "graph", "flowchart", "flowchart-elk":
      return .graph(try FlowchartParser.parse(ls))
    case "sequencediagram":
      return .sequence(try SequenceParser.parse(ls))
    case "pie":
      return .pie(try PieParser.parse(ls))
    case "classdiagram", "classdiagram-v2":
      return .graph(try ClassParser.parse(ls))
    case "statediagram", "statediagram-v2":
      return .graph(try StateParser.parse(ls))
    default:
      return .unsupported(keyword.isEmpty ? head : keyword)
    }
  }

  /// Unquotes a Mermaid label: strips one level of quotes and backticks, decodes `#quot;`-style entities.
  static func cleanLabel(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 { s = String(s.dropFirst().dropLast()) }
    if s.hasPrefix("`") && s.hasSuffix("`") && s.count >= 2 { s = String(s.dropFirst().dropLast()) }
    s = s.replacingOccurrences(of: "#quot;", with: "\"").replacingOccurrences(of: "#39;", with: "'")
      .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br />", with: "\n")
    // Markdown-ish emphasis inside labels is shown as plain text.
    s = s.replacingOccurrences(of: "**", with: "")
    // #num; numeric entities
    while let r = s.range(of: #"#(\d+);"#, options: .regularExpression) {
      let num = s[r].dropFirst().dropLast()
      if let v = UInt32(num), let u = Unicode.Scalar(v) { s.replaceSubrange(r, with: String(Character(u))) } else { break }
    }
    return s
  }
}
