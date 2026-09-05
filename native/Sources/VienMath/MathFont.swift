import CoreGraphics
import CoreText
import Foundation

/// STIX Two Math (bundled with macOS) plus the parts of its OpenType MATH table that typesetting
/// needs: constants, italics corrections, top-accent attachments and glyph variants/assemblies.
final class MathFont: @unchecked Sendable {
  static let shared = MathFont()

  let font: CTFont  // at `unit` size
  let unit: Double = 100
  let unitsPerEm: Double
  private(set) var constants: [Int: Double] = [:]  // index → font units
  private var italicsCorrection: [CGGlyph: Double] = [:]
  private var topAccent: [CGGlyph: Double] = [:]
  private var verticalVariants: [CGGlyph: Construction] = [:]
  private var horizontalVariants: [CGGlyph: Construction] = [:]
  private(set) var minConnectorOverlap: Double = 0
  let available: Bool

  struct Construction {
    var variants: [(glyph: CGGlyph, advance: Double)]
    var assembly: [Part]
  }

  struct Part {
    var glyph: CGGlyph
    var startConnector: Double
    var endConnector: Double
    var fullAdvance: Double
    var isExtender: Bool
  }

  // MathConstants indices (OpenType MATH order).
  enum C: Int {
    case scriptPercentScaleDown = 0, scriptScriptPercentScaleDown, delimitedSubFormulaMinHeight, displayOperatorMinHeight
    case mathLeading, axisHeight, accentBaseHeight, flattenedAccentBaseHeight, subscriptShiftDown, subscriptTopMax
    case subscriptBaselineDropMin, superscriptShiftUp, superscriptShiftUpCramped, superscriptBottomMin, superscriptBaselineDropMax
    case subSuperscriptGapMin, superscriptBottomMaxWithSubscript, spaceAfterScript, upperLimitGapMin, upperLimitBaselineRiseMin
    case lowerLimitGapMin, lowerLimitBaselineDropMin, stackTopShiftUp, stackTopDisplayStyleShiftUp, stackBottomShiftDown
    case stackBottomDisplayStyleShiftDown, stackGapMin, stackDisplayStyleGapMin, stretchStackTopShiftUp, stretchStackBottomShiftDown
    case stretchStackGapAboveMin, stretchStackGapBelowMin, fractionNumeratorShiftUp, fractionNumeratorDisplayStyleShiftUp
    case fractionDenominatorShiftDown, fractionDenominatorDisplayStyleShiftDown, fractionNumeratorGapMin, fractionNumDisplayStyleGapMin
    case fractionRuleThickness, fractionDenominatorGapMin, fractionDenomDisplayStyleGapMin, skewedFractionHorizontalGap
    case skewedFractionVerticalGap, overbarVerticalGap, overbarRuleThickness, overbarExtraAscender, underbarVerticalGap
    case underbarRuleThickness, underbarExtraDescender, radicalVerticalGap, radicalDisplayStyleVerticalGap, radicalRuleThickness
    case radicalExtraAscender, radicalKernBeforeDegree, radicalKernAfterDegree, radicalDegreeBottomRaisePercent
  }

  private init() {
    let candidates = ["STIXTwoMath-Regular", "STIX Two Math", "STIXGeneral"]
    var f: CTFont? = nil
    for name in candidates {
      let c = CTFontCreateWithName(name as CFString, unit, nil)
      if (CTFontCopyPostScriptName(c) as String).lowercased().contains("stix") { f = c; break }
    }
    let chosen = f ?? CTFontCreateUIFontForLanguage(.system, unit, nil)!
    font = chosen
    unitsPerEm = Double(CTFontGetUnitsPerEm(chosen))
    available = f != nil
    if let data = CTFontCopyTable(chosen, CTFontTableTag(0x4D41_5448), []) as Data? { parseMATH(data) }
  }

  /// Value of a MATH constant in points at `size`; percentages are returned as plain numbers.
  func constant(_ c: C, size: Double) -> Double {
    let isPercent = c == .scriptPercentScaleDown || c == .scriptScriptPercentScaleDown || c == .radicalDegreeBottomRaisePercent
    guard let v = constants[c.rawValue] else { return isPercent ? fallback(c) : fallback(c) * size }
    return isPercent ? v : v / unitsPerEm * size
  }

  /// Approximate TeX-like defaults (fractions of the em) when the MATH table is missing.
  private func fallback(_ c: C) -> Double {
    switch c {
    case .scriptPercentScaleDown: return 70
    case .scriptScriptPercentScaleDown: return 55
    case .axisHeight: return 0.25
    case .fractionRuleThickness, .overbarRuleThickness, .underbarRuleThickness, .radicalRuleThickness: return 0.045
    case .fractionNumeratorShiftUp: return 0.4
    case .fractionNumeratorDisplayStyleShiftUp: return 0.68
    case .fractionDenominatorShiftDown: return 0.35
    case .fractionDenominatorDisplayStyleShiftDown: return 0.68
    case .fractionNumeratorGapMin, .fractionDenominatorGapMin: return 0.045
    case .fractionNumDisplayStyleGapMin, .fractionDenomDisplayStyleGapMin: return 0.135
    case .superscriptShiftUp: return 0.36
    case .superscriptShiftUpCramped: return 0.29
    case .subscriptShiftDown: return 0.15
    case .subscriptTopMax: return 0.36
    case .superscriptBottomMin: return 0.12
    case .subSuperscriptGapMin: return 0.18
    case .superscriptBottomMaxWithSubscript: return 0.36
    case .spaceAfterScript: return 0.05
    case .upperLimitGapMin, .lowerLimitGapMin: return 0.1
    case .upperLimitBaselineRiseMin, .lowerLimitBaselineDropMin: return 0.2
    case .radicalVerticalGap: return 0.05
    case .radicalDisplayStyleVerticalGap: return 0.12
    case .radicalExtraAscender: return 0.05
    case .radicalKernBeforeDegree: return 0.28
    case .radicalKernAfterDegree: return -0.55
    case .radicalDegreeBottomRaisePercent: return 60
    case .accentBaseHeight: return 0.45
    case .overbarVerticalGap, .underbarVerticalGap: return 0.1
    case .overbarExtraAscender, .underbarExtraDescender: return 0.05
    case .displayOperatorMinHeight: return 1.4
    case .subscriptBaselineDropMin: return 0.05
    case .superscriptBaselineDropMax: return 0.25
    case .stackTopShiftUp: return 0.45
    case .stackTopDisplayStyleShiftUp: return 0.7
    case .stackBottomShiftDown: return 0.35
    case .stackBottomDisplayStyleShiftDown: return 0.7
    case .stackGapMin: return 0.15
    case .stackDisplayStyleGapMin: return 0.35
    default: return 0
    }
  }

  // MARK: - Glyphs

  func glyph(for scalar: Unicode.Scalar) -> CGGlyph? {
    var chars = Array(String(Character(scalar)).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: chars.count)
    guard CTFontGetGlyphsForCharacters(font, &chars, &glyphs, chars.count), glyphs[0] != 0 else { return nil }
    return glyphs[0]
  }

  struct Metrics {
    var advance: Double
    var bounds: CGRect  // glyph-space, y up, at `size`
  }

  func metrics(_ glyph: CGGlyph, size: Double) -> Metrics {
    var g = glyph
    var adv = CGSize.zero
    CTFontGetAdvancesForGlyphs(font, .horizontal, &g, &adv, 1)
    var box = CGRect.zero
    CTFontGetBoundingRectsForGlyphs(font, .horizontal, &g, &box, 1)
    let s = size / unit
    return Metrics(advance: adv.width * s, bounds: CGRect(x: box.minX * s, y: box.minY * s, width: box.width * s, height: box.height * s))
  }

  func italicCorrection(_ glyph: CGGlyph, size: Double) -> Double { (italicsCorrection[glyph] ?? 0) / unitsPerEm * size }
  func topAccentAttachment(_ glyph: CGGlyph, size: Double) -> Double? { topAccent[glyph].map { $0 / unitsPerEm * size } }

  func variants(_ glyph: CGGlyph, vertical: Bool) -> Construction? { vertical ? verticalVariants[glyph] : horizontalVariants[glyph] }

  /// A CTFont at `size`, with an optional transform (used to stretch fallback delimiters).
  func ctFont(size: Double, transform: CGAffineTransform = .identity) -> CTFont {
    var t = transform
    return CTFontCreateCopyWithAttributes(font, size, &t, nil)
  }

  // MARK: - MATH table parsing

  private func parseMATH(_ data: Data) {
    let b = [UInt8](data)
    func u16(_ o: Int) -> Int { o + 1 < b.count ? Int(b[o]) << 8 | Int(b[o + 1]) : 0 }
    func i16(_ o: Int) -> Int { let v = u16(o); return v >= 0x8000 ? v - 0x10000 : v }
    guard b.count >= 10 else { return }
    let constantsOffset = u16(4), glyphInfoOffset = u16(6), variantsOffset = u16(8)
    // Constants.
    if constantsOffset > 0 {
      var o = constantsOffset
      constants[0] = Double(i16(o)); constants[1] = Double(i16(o + 2))
      constants[2] = Double(u16(o + 4)); constants[3] = Double(u16(o + 6))
      o += 8
      for i in 4..<55 { constants[i] = Double(i16(o)); o += 4 }
      constants[55] = Double(i16(o))
    }
    func coverage(_ o: Int) -> [CGGlyph] {
      var out: [CGGlyph] = []
      let format = u16(o)
      if format == 1 {
        let n = u16(o + 2)
        for i in 0..<n { out.append(CGGlyph(u16(o + 4 + i * 2))) }
      } else if format == 2 {
        let n = u16(o + 2)
        for i in 0..<n {
          let r = o + 4 + i * 6
          let start = u16(r), end = u16(r + 2)
          if end >= start, end - start < 5000 { for g in start...end { out.append(CGGlyph(g)) } }
        }
      }
      return out
    }
    // Glyph info: italics correction and top accent attachment.
    if glyphInfoOffset > 0 {
      let icOffset = u16(glyphInfoOffset), taOffset = u16(glyphInfoOffset + 2)
      if icOffset > 0 {
        let base = glyphInfoOffset + icOffset
        let glyphs = coverage(base + u16(base))
        let count = u16(base + 2)
        for (i, g) in glyphs.prefix(count).enumerated() { italicsCorrection[g] = Double(i16(base + 4 + i * 4)) }
      }
      if taOffset > 0 {
        let base = glyphInfoOffset + taOffset
        let glyphs = coverage(base + u16(base))
        let count = u16(base + 2)
        for (i, g) in glyphs.prefix(count).enumerated() { topAccent[g] = Double(i16(base + 4 + i * 4)) }
      }
    }
    // Variants.
    if variantsOffset > 0 {
      let base = variantsOffset
      minConnectorOverlap = Double(u16(base))
      let vCov = u16(base + 2), hCov = u16(base + 4)
      let vCount = u16(base + 6), hCount = u16(base + 8)
      func construction(_ o: Int) -> Construction {
        let assemblyOffset = u16(o)
        let count = u16(o + 2)
        var variants: [(CGGlyph, Double)] = []
        for i in 0..<count { variants.append((CGGlyph(u16(o + 4 + i * 4)), Double(u16(o + 6 + i * 4)))) }
        var parts: [Part] = []
        if assemblyOffset > 0 {
          let a = o + assemblyOffset
          let n = u16(a + 4)
          for i in 0..<n {
            let p = a + 6 + i * 10
            parts.append(Part(glyph: CGGlyph(u16(p)), startConnector: Double(u16(p + 2)), endConnector: Double(u16(p + 4)), fullAdvance: Double(u16(p + 6)), isExtender: u16(p + 8) & 1 == 1))
          }
        }
        return Construction(variants: variants, assembly: parts)
      }
      if vCov > 0 {
        let glyphs = coverage(base + vCov)
        for (i, g) in glyphs.prefix(vCount).enumerated() { verticalVariants[g] = construction(base + u16(base + 10 + i * 2)) }
      }
      if hCov > 0 {
        let glyphs = coverage(base + hCov)
        for (i, g) in glyphs.prefix(hCount).enumerated() { horizontalVariants[g] = construction(base + u16(base + 10 + vCount * 2 + i * 2)) }
      }
    }
  }
}
