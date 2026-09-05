import AppKit

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
