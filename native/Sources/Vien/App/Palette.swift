import AppKit
import VienCode

/// Editor colours. `System` follows macOS (dynamic colours, light or dark); the others are fixed
/// palettes that bring their own window appearance so chrome and text agree.
nonisolated struct Palette {
  let name: String
  /// nil follows the system appearance.
  let isDark: Bool?
  let background: NSColor
  let text: NSColor
  let secondary: NSColor
  let marker: NSColor
  let quote: NSColor
  let link: NSColor
  let accent: NSColor
  let codeBackground: NSColor
  let rule: NSColor
  let syntax: [TokenKind: NSColor]

  var appearance: NSAppearance? { isDark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) } }

  static let all: [Palette] = [system, paper, graphite, solarizedLight, solarizedDark, nord, oneDark]

  static func named(_ name: String) -> Palette { all.first { $0.name == name } ?? system }

  private static func hex(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
  }

  /// A colour that resolves per appearance (used by the System palette).
  private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? hex(dark) : hex(light) }
  }

  private static func syntax(keyword: UInt32, string: UInt32, comment: UInt32, number: UInt32, type: UInt32, function: UInt32, constant: UInt32, attribute: UInt32, variable: UInt32, inserted: UInt32, deleted: UInt32, make: (UInt32) -> NSColor) -> [TokenKind: NSColor] {
    [
      .keyword: make(keyword), .heading: make(keyword), .string: make(string), .comment: make(comment), .number: make(number),
      .constant: make(constant), .type: make(type), .tag: make(type), .function: make(function), .property: make(function),
      .attribute: make(attribute), .meta: make(attribute), .variable: make(variable), .inserted: make(inserted), .deleted: make(deleted),
    ]
  }

  private static func fixedSyntax(keyword: UInt32, string: UInt32, comment: UInt32, number: UInt32, type: UInt32, function: UInt32, constant: UInt32, attribute: UInt32, variable: UInt32, inserted: UInt32, deleted: UInt32) -> [TokenKind: NSColor] {
    syntax(keyword: keyword, string: string, comment: comment, number: number, type: type, function: function, constant: constant, attribute: attribute, variable: variable, inserted: inserted, deleted: deleted, make: hex)
  }

  // Xcode's default presentation, light and dark.
  static let system = Palette(
    name: "System", isDark: nil, background: .textBackgroundColor, text: .labelColor, secondary: .secondaryLabelColor,
    marker: .tertiaryLabelColor, quote: .secondaryLabelColor, link: .linkColor, accent: .controlAccentColor,
    codeBackground: .quaternarySystemFill, rule: .separatorColor,
    syntax: [
      .keyword: dynamic(0x9B2393, 0xFC5FA3), .heading: dynamic(0x9B2393, 0xFC5FA3), .type: dynamic(0x0B4F79, 0x5DD8FF), .tag: dynamic(0x0B4F79, 0x5DD8FF),
      .constant: dynamic(0x1C00CF, 0xD0BF69), .number: dynamic(0x1C00CF, 0xD0BF69), .string: dynamic(0xC41A16, 0xFC6A5D),
      .comment: dynamic(0x5D6C79, 0x6C7986), .function: dynamic(0x326D74, 0x67B7A4), .property: dynamic(0x326D74, 0x67B7A4),
      .variable: dynamic(0x6C36A5, 0xA167E6), .attribute: dynamic(0x643820, 0xBF8555), .meta: dynamic(0x643820, 0xBF8555),
      .inserted: dynamic(0x008A00, 0x6AD26A), .deleted: dynamic(0xC41A16, 0xFC6A5D),
    ])

  static let paper = Palette(
    name: "Paper", isDark: false, background: hex(0xFAF7F0), text: hex(0x33312C), secondary: hex(0x7C766A), marker: hex(0xBDB6A7),
    quote: hex(0x6E685C), link: hex(0x9A5B2E), accent: hex(0xB7803C), codeBackground: hex(0xEFEAE0), rule: hex(0xDED8CB),
    syntax: fixedSyntax(keyword: 0x8A3D8E, string: 0xB03A2E, comment: 0x8C857A, number: 0x2F5BB7, type: 0x1F6A7A, function: 0x3B6B6E, constant: 0x2F5BB7, attribute: 0x7A4E23, variable: 0x6B3FA0, inserted: 0x2E7D32, deleted: 0xB03A2E))

  static let graphite = Palette(
    name: "Graphite", isDark: false, background: hex(0xF4F5F7), text: hex(0x2F3237), secondary: hex(0x7A7F87), marker: hex(0xB9BEC6),
    quote: hex(0x676C74), link: hex(0x3A6EA5), accent: hex(0x5B6B7F), codeBackground: hex(0xE9EBEF), rule: hex(0xD9DCE1),
    syntax: fixedSyntax(keyword: 0x8E2C86, string: 0xB4372F, comment: 0x6B7580, number: 0x2A45B5, type: 0x175A6E, function: 0x2F6A6D, constant: 0x2A45B5, attribute: 0x6A4A2A, variable: 0x5F3F9A, inserted: 0x2E7D32, deleted: 0xB4372F))

  static let solarizedLight = Palette(
    name: "Solarized Light", isDark: false, background: hex(0xFDF6E3), text: hex(0x586E75), secondary: hex(0x657B83), marker: hex(0xC7BFA9),
    quote: hex(0x657B83), link: hex(0x268BD2), accent: hex(0x2AA198), codeBackground: hex(0xEEE8D5), rule: hex(0xE3DCC6),
    syntax: fixedSyntax(keyword: 0x859900, string: 0x2AA198, comment: 0x93A1A1, number: 0xD33682, type: 0xB58900, function: 0x268BD2, constant: 0xCB4B16, attribute: 0x6C71C4, variable: 0x6C71C4, inserted: 0x859900, deleted: 0xDC322F))

  static let solarizedDark = Palette(
    name: "Solarized Dark", isDark: true, background: hex(0x002B36), text: hex(0x93A1A1), secondary: hex(0x657B83), marker: hex(0x3E5860),
    quote: hex(0x839496), link: hex(0x268BD2), accent: hex(0x2AA198), codeBackground: hex(0x073642), rule: hex(0x0E3A46),
    syntax: fixedSyntax(keyword: 0x859900, string: 0x2AA198, comment: 0x586E75, number: 0xD33682, type: 0xB58900, function: 0x268BD2, constant: 0xCB4B16, attribute: 0x6C71C4, variable: 0x6C71C4, inserted: 0x859900, deleted: 0xDC322F))

  static let nord = Palette(
    name: "Nord", isDark: true, background: hex(0x2E3440), text: hex(0xD8DEE9), secondary: hex(0x8F98A8), marker: hex(0x4C566A),
    quote: hex(0xB0B8C8), link: hex(0x88C0D0), accent: hex(0x81A1C1), codeBackground: hex(0x3B4252), rule: hex(0x434C5E),
    syntax: fixedSyntax(keyword: 0x81A1C1, string: 0xA3BE8C, comment: 0x616E88, number: 0xB48EAD, type: 0x8FBCBB, function: 0x88C0D0, constant: 0xD08770, attribute: 0xEBCB8B, variable: 0xD8DEE9, inserted: 0xA3BE8C, deleted: 0xBF616A))

  static let oneDark = Palette(
    name: "One Dark", isDark: true, background: hex(0x282C34), text: hex(0xABB2BF), secondary: hex(0x7F848E), marker: hex(0x4B5263),
    quote: hex(0x9DA5B4), link: hex(0x61AFEF), accent: hex(0x61AFEF), codeBackground: hex(0x2F343E), rule: hex(0x3B4048),
    syntax: fixedSyntax(keyword: 0xC678DD, string: 0x98C379, comment: 0x5C6370, number: 0xD19A66, type: 0xE5C07B, function: 0x61AFEF, constant: 0xD19A66, attribute: 0xE06C75, variable: 0xABB2BF, inserted: 0x98C379, deleted: 0xE06C75))
}
