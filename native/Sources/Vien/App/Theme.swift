import AppKit
import VienCode

/// Typography and colour tokens. Everything derives from the system font and semantic system colours
/// so the editor looks native in light and dark mode without a theme engine.
struct Theme {
  let baseSize: CGFloat
  let lineHeightMultiple: CGFloat
  let fontFamily: String
  let codeFontFamily: String

  init(preferences p: Preferences = .shared, zoom: CGFloat = 1) {
    baseSize = CGFloat(p.fontSize) * zoom
    lineHeightMultiple = CGFloat(p.lineHeight)
    fontFamily = p.fontFamily
    codeFontFamily = p.codeFontFamily
  }

  func body(weight: NSFont.Weight = .regular, size: CGFloat? = nil, italic: Bool = false) -> NSFont {
    let s = size ?? baseSize
    var font: NSFont
    if !fontFamily.isEmpty, let f = NSFont(name: fontFamily, size: s) {
      font = weight == .regular ? f : (NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask))
    } else {
      font = NSFont.systemFont(ofSize: s, weight: weight)
    }
    if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
    return font
  }

  func code(size: CGFloat? = nil) -> NSFont {
    let s = (size ?? baseSize) * 0.88
    if !codeFontFamily.isEmpty, let f = NSFont(name: codeFontFamily, size: s) { return f }
    return NSFont.monospacedSystemFont(ofSize: s, weight: .regular)
  }

  func heading(level: Int) -> NSFont {
    let scale: [CGFloat] = [1.9, 1.5, 1.25, 1.1, 1.0, 1.0]
    let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
    return body(weight: weight, size: baseSize * scale[max(0, min(5, level - 1))])
  }

  static let text = NSColor.labelColor
  static let secondary = NSColor.secondaryLabelColor
  static let marker = NSColor.tertiaryLabelColor
  static let quote = NSColor.secondaryLabelColor
  static let link = NSColor.linkColor
  static let codeBackground = NSColor.quaternarySystemFill
  static let rule = NSColor.separatorColor
  static let accent = NSColor.controlAccentColor
  static let background = NSColor.textBackgroundColor
  /// Makes markup take (almost) no space: a hairline font in a clear colour. The characters stay
  /// in the text, so nothing is rewritten and the caret can still land on them.
  static let hiddenAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]

  /// Colour for a code token; light and dark values follow Xcode's default presentation.
  static func syntax(_ kind: TokenKind) -> NSColor { syntaxColors[kind] ?? text }

  private static let syntaxColors: [TokenKind: NSColor] = {
    func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
      func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
      }
      return NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? color(dark) : color(light) }
    }
    return [
      .keyword: dynamic(0x9B2393, 0xFC5FA3), .type: dynamic(0x0B4F79, 0x5DD8FF), .tag: dynamic(0x0B4F79, 0x5DD8FF),
      .constant: dynamic(0x1C00CF, 0xD0BF69), .number: dynamic(0x1C00CF, 0xD0BF69), .string: dynamic(0xC41A16, 0xFC6A5D),
      .comment: dynamic(0x5D6C79, 0x6C7986), .function: dynamic(0x326D74, 0x67B7A4), .property: dynamic(0x326D74, 0x67B7A4),
      .variable: dynamic(0x6C36A5, 0xA167E6), .attribute: dynamic(0x643820, 0xBF8555), .meta: dynamic(0x643820, 0xBF8555),
      .heading: dynamic(0x9B2393, 0xFC5FA3), .inserted: dynamic(0x008A00, 0x6AD26A), .deleted: dynamic(0xC41A16, 0xFC6A5D),
    ]
  }()

  var paragraphSpacing: CGFloat { baseSize * 0.6 }
  var headingSpacingBefore: CGFloat { baseSize * 1.1 }

  func paragraphStyle(lineHeight: CGFloat? = nil, indent: CGFloat = 0, firstLineIndent: CGFloat? = nil, spacingBefore: CGFloat = 0, spacingAfter: CGFloat = 0) -> NSParagraphStyle {
    let s = NSMutableParagraphStyle()
    s.lineHeightMultiple = lineHeight ?? lineHeightMultiple
    s.headIndent = indent
    s.firstLineHeadIndent = firstLineIndent ?? indent
    s.paragraphSpacingBefore = spacingBefore
    s.paragraphSpacing = spacingAfter
    s.lineBreakMode = .byWordWrapping
    return s
  }
}
