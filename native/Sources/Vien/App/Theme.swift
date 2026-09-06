import AppKit
import VienCode

/// Typography and colour tokens: fonts from the preferences, colours from the chosen palette
/// (the system palette by default, so the editor looks native in light and dark mode).
struct Theme {
  let baseSize: CGFloat
  let lineHeightMultiple: CGFloat
  let fontFamily: String
  let codeFontFamily: String
  let palette: Palette

  init(preferences p: Preferences = .shared, zoom: CGFloat = 1, palette: Palette? = nil) {
    baseSize = CGFloat(p.fontSize) * zoom
    lineHeightMultiple = CGFloat(p.lineHeight)
    fontFamily = p.fontFamily
    codeFontFamily = p.codeFontFamily
    self.palette = palette ?? Palette.named(p.theme)
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

  /// The theme the editor is using; the static colour tokens read from it.
  static var current = Theme()

  static var text: NSColor { current.palette.text }
  static var secondary: NSColor { current.palette.secondary }
  static var marker: NSColor { current.palette.marker }
  static var quote: NSColor { current.palette.quote }
  static var link: NSColor { current.palette.link }
  static var codeBackground: NSColor { current.palette.codeBackground }
  static var rule: NSColor { current.palette.rule }
  static var accent: NSColor { current.palette.accent }
  static var background: NSColor { current.palette.background }
  /// Makes markup take (almost) no space: a hairline font in a clear colour. The characters stay
  /// in the text, so nothing is rewritten and the caret can still land on them.
  static let hiddenAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 0.01), .foregroundColor: NSColor.clear]

  /// Colour for a code token in the current palette.
  static func syntax(_ kind: TokenKind) -> NSColor { current.palette.syntax[kind] ?? current.palette.text }

  /// Runs `body` with another palette current (printing uses the system palette whatever the editor shows).
  static func using<T>(_ palette: Palette, _ body: () throws -> T) rethrows -> T {
    let saved = current
    current = Theme(zoom: saved.baseSize / CGFloat(Preferences.shared.fontSize), palette: palette)
    defer { current = saved }
    return try body()
  }

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
