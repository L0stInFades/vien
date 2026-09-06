import CoreGraphics
import CoreText
import Foundation

/// Colours are plain values so the same drawing code can target Core Graphics and SVG.
public struct DiagramColor: Sendable, Equatable {
  public var r: Double, g: Double, b: Double, a: Double
  public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
  public init(hex: UInt32, alpha: Double = 1) {
    self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: alpha)
  }
  /// Parses `#rgb`, `#rrggbb`, `rgb(r,g,b)` and a few CSS names; nil when unrecognised.
  public init?(css: String) {
    let s = css.trimmingCharacters(in: .whitespaces).lowercased()
    if s.hasPrefix("#") {
      let hex = String(s.dropFirst())
      guard let v = UInt32(hex, radix: 16) else { return nil }
      if hex.count == 3 { self.init(hex: ((v >> 8) & 0xF) * 0x110000 + ((v >> 4) & 0xF) * 0x1100 + (v & 0xF) * 0x11) }
      else if hex.count == 6 { self.init(hex: v) }
      else { return nil }
      return
    }
    if s.hasPrefix("rgb") {
      let nums = s.drop(while: { $0 != "(" }).dropFirst().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ")", with: "")) }
      guard nums.count >= 3 else { return nil }
      self.init(r: nums[0] / 255, g: nums[1] / 255, b: nums[2] / 255, a: nums.count > 3 ? nums[3] : 1)
      return
    }
    let names: [String: UInt32] = [
      "black": 0x000000, "white": 0xFFFFFF, "red": 0xFF3B30, "green": 0x34C759, "blue": 0x007AFF, "yellow": 0xFFCC00,
      "orange": 0xFF9500, "purple": 0xAF52DE, "pink": 0xFF2D55, "gray": 0x8E8E93, "grey": 0x8E8E93, "teal": 0x5AC8FA,
      "indigo": 0x5856D6, "brown": 0xA2845E, "lightblue": 0xADD8E6, "lightgreen": 0x90EE90, "lightgray": 0xD3D3D3,
      "lightgrey": 0xD3D3D3, "transparent": 0x000000, "none": 0x000000,
    ]
    guard let hex = names[s] else { return nil }
    self.init(hex: hex, alpha: (s == "transparent" || s == "none") ? 0 : 1)
  }
  var css: String {
    let h = String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    return a < 1 ? "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(String(format: "%.2f", a)))" : h
  }
  var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
  func withAlpha(_ alpha: Double) -> DiagramColor { DiagramColor(r: r, g: g, b: b, a: alpha) }
}

public struct Stroke: Sendable, Equatable {
  public var color: DiagramColor
  public var width: Double
  public var dash: [Double]
  public init(color: DiagramColor, width: Double = 1, dash: [Double] = []) { self.color = color; self.width = width; self.dash = dash }
}

public enum TextWeight: Sendable { case regular, medium, semibold, bold }

public struct TextStyle: Sendable, Equatable {
  public var size: Double
  public var weight: TextWeight
  public var color: DiagramColor
  public var italic: Bool
  public var monospace: Bool
  public init(size: Double = 13, weight: TextWeight = .regular, color: DiagramColor, italic: Bool = false, monospace: Bool = false) {
    self.size = size; self.weight = weight; self.color = color; self.italic = italic; self.monospace = monospace
  }
}

public enum TextAlign: Sendable { case left, center, right }

/// Drawing surface used by every diagram renderer. Coordinates are points, origin top-left, y down.
public protocol Canvas {
  mutating func rect(_ r: CGRect, radius: Double, fill: DiagramColor?, stroke: Stroke?)
  mutating func ellipse(in r: CGRect, fill: DiagramColor?, stroke: Stroke?)
  mutating func polygon(_ points: [CGPoint], fill: DiagramColor?, stroke: Stroke?)
  /// Polyline or bezier path: `segments` are (control1, control2, end) triples after `start`; straight segments repeat the end point.
  mutating func path(start: CGPoint, segments: [(CGPoint, CGPoint, CGPoint)], closed: Bool, fill: DiagramColor?, stroke: Stroke?)
  mutating func line(_ a: CGPoint, _ b: CGPoint, stroke: Stroke)
  /// Draws `text` (may contain newlines) with its layout box anchored at `origin` (top-left of the box); `width` is the box width for alignment.
  mutating func text(_ text: String, at origin: CGPoint, width: Double, align: TextAlign, style: TextStyle)
  mutating func pieSlice(center: CGPoint, radius: Double, start: Double, end: Double, fill: DiagramColor, stroke: Stroke?)
}

/// Text measurement shared by layout and both canvases.
public enum TextMetrics {
  static func font(_ style: TextStyle) -> CTFont {
    let weightValue: CGFloat = switch style.weight { case .regular: 0; case .medium: 0.23; case .semibold: 0.3; case .bold: 0.4 }
    let base: CTFont
    if style.monospace {
      base = CTFontCreateUIFontForLanguage(.userFixedPitch, style.size, nil) ?? CTFontCreateWithName("Menlo" as CFString, style.size, nil)
    } else {
      base = CTFontCreateUIFontForLanguage(.system, style.size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, style.size, nil)
    }
    var traits: [CFString: Any] = [:]
    if weightValue > 0 { traits[kCTFontWeightTrait] = weightValue }
    if style.italic { traits[kCTFontSlantTrait] = 0.2 }
    guard !traits.isEmpty else { return base }
    let desc = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary)
    return CTFontCreateCopyWithAttributes(base, style.size, nil, desc)
  }

  static func lines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br />", with: "\n")
      .components(separatedBy: "\n")
  }

  static func lineHeight(_ style: TextStyle) -> Double {
    let f = font(style)
    return (CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f)).rounded(.up) + 2
  }

  /// Size of the multi-line text box.
  public static func measure(_ text: String, style: TextStyle) -> CGSize {
    let f = font(style)
    var width: Double = 0
    for line in lines(text) {
      let attributed = NSAttributedString(string: line, attributes: [kCTFontAttributeName as NSAttributedString.Key: f])
      let ctLine = CTLineCreateWithAttributedString(attributed)
      width = max(width, CTLineGetTypographicBounds(ctLine, nil, nil, nil))
    }
    return CGSize(width: width.rounded(.up), height: lineHeight(style) * Double(lines(text).count))
  }
}

/// Core Graphics backend. The context must be flipped (origin top-left), which `CGCanvas.makeImage` arranges.
public struct CGCanvas: Canvas {
  public let context: CGContext

  public init(context: CGContext) { self.context = context }

  private func apply(fill: DiagramColor?, stroke: Stroke?, path: CGPath) {
    if let fill, fill.a > 0 {
      context.setFillColor(fill.cg)
      context.addPath(path)
      context.fillPath()
    }
    if let stroke, stroke.width > 0, stroke.color.a > 0 {
      context.setStrokeColor(stroke.color.cg)
      context.setLineWidth(stroke.width)
      context.setLineDash(phase: 0, lengths: stroke.dash.map { CGFloat($0) })
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.addPath(path)
      context.strokePath()
      context.setLineDash(phase: 0, lengths: [])
    }
  }

  public mutating func rect(_ r: CGRect, radius: Double, fill: DiagramColor?, stroke: Stroke?) {
    let p = radius > 0 ? CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil) : CGPath(rect: r, transform: nil)
    apply(fill: fill, stroke: stroke, path: p)
  }

  public mutating func ellipse(in r: CGRect, fill: DiagramColor?, stroke: Stroke?) {
    apply(fill: fill, stroke: stroke, path: CGPath(ellipseIn: r, transform: nil))
  }

  public mutating func polygon(_ points: [CGPoint], fill: DiagramColor?, stroke: Stroke?) {
    guard points.count > 1 else { return }
    let p = CGMutablePath()
    p.addLines(between: points)
    p.closeSubpath()
    apply(fill: fill, stroke: stroke, path: p)
  }

  public mutating func path(start: CGPoint, segments: [(CGPoint, CGPoint, CGPoint)], closed: Bool, fill: DiagramColor?, stroke: Stroke?) {
    let p = CGMutablePath()
    p.move(to: start)
    for (c1, c2, end) in segments {
      if c1 == end && c2 == end { p.addLine(to: end) } else { p.addCurve(to: end, control1: c1, control2: c2) }
    }
    if closed { p.closeSubpath() }
    apply(fill: fill, stroke: stroke, path: p)
  }

  public mutating func line(_ a: CGPoint, _ b: CGPoint, stroke: Stroke) {
    let p = CGMutablePath()
    p.move(to: a)
    p.addLine(to: b)
    apply(fill: nil, stroke: stroke, path: p)
  }

  public mutating func text(_ text: String, at origin: CGPoint, width: Double, align: TextAlign, style: TextStyle) {
    let f = TextMetrics.font(style)
    let lh = TextMetrics.lineHeight(style)
    let ascent = CTFontGetAscent(f)
    context.saveGState()
    context.setFillColor(style.color.cg)
    for (i, line) in TextMetrics.lines(text).enumerated() {
      let attributed = NSAttributedString(string: line, attributes: [
        kCTFontAttributeName as NSAttributedString.Key: f,
        kCTForegroundColorAttributeName as NSAttributedString.Key: style.color.cg,
      ])
      let ctLine = CTLineCreateWithAttributedString(attributed)
      let w = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
      var x = origin.x
      switch align {
      case .center: x += (width - w) / 2
      case .right: x += width - w
      case .left: break
      }
      let baseline = origin.y + Double(i) * lh + ascent + 1
      // The context is flipped (y down); a flipped text matrix keeps glyphs upright.
      context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
      context.textPosition = CGPoint(x: x, y: baseline)
      CTLineDraw(ctLine, context)
    }
    context.restoreGState()
  }

  public mutating func pieSlice(center: CGPoint, radius: Double, start: Double, end: Double, fill: DiagramColor, stroke: Stroke?) {
    let p = CGMutablePath()
    p.move(to: center)
    p.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    p.closeSubpath()
    apply(fill: fill, stroke: stroke, path: p)
  }

  /// Renders `draw` into a bitmap of `size` points at `scale`, with a top-left origin.
  public static func makeImage(size: CGSize, scale: CGFloat, background: DiagramColor?, draw: (inout CGCanvas) -> Void) -> CGImage? {
    let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.setShouldSmoothFonts(true)
    if let background { ctx.setFillColor(background.cg); ctx.fill(CGRect(origin: .zero, size: size)) }
    var canvas = CGCanvas(context: ctx)
    draw(&canvas)
    return ctx.makeImage()
  }
}

/// SVG backend: produces a standalone `<svg>` string.
public struct SVGCanvas: Canvas {
  public private(set) var body = ""
  public let size: CGSize
  private let fontFamily = "-apple-system, 'SF Pro Text', 'Helvetica Neue', Helvetica, Arial, sans-serif"

  public init(size: CGSize) { self.size = size }

  private func attrs(fill: DiagramColor?, stroke: Stroke?) -> String {
    var s = " fill=\"\(fill.map { $0.a > 0 ? $0.css : "none" } ?? "none")\""
    if let stroke, stroke.width > 0, stroke.color.a > 0 {
      s += " stroke=\"\(stroke.color.css)\" stroke-width=\"\(f(stroke.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
      if !stroke.dash.isEmpty { s += " stroke-dasharray=\"\(stroke.dash.map(f).joined(separator: " "))\"" }
    }
    return s
  }

  private func f(_ v: Double) -> String { String(format: "%.1f", v) }

  public mutating func rect(_ r: CGRect, radius: Double, fill: DiagramColor?, stroke: Stroke?) {
    body += "<rect x=\"\(f(r.minX))\" y=\"\(f(r.minY))\" width=\"\(f(r.width))\" height=\"\(f(r.height))\" rx=\"\(f(radius))\"\(attrs(fill: fill, stroke: stroke))/>\n"
  }

  public mutating func ellipse(in r: CGRect, fill: DiagramColor?, stroke: Stroke?) {
    body += "<ellipse cx=\"\(f(r.midX))\" cy=\"\(f(r.midY))\" rx=\"\(f(r.width / 2))\" ry=\"\(f(r.height / 2))\"\(attrs(fill: fill, stroke: stroke))/>\n"
  }

  public mutating func polygon(_ points: [CGPoint], fill: DiagramColor?, stroke: Stroke?) {
    let pts = points.map { "\(f($0.x)),\(f($0.y))" }.joined(separator: " ")
    body += "<polygon points=\"\(pts)\"\(attrs(fill: fill, stroke: stroke))/>\n"
  }

  public mutating func path(start: CGPoint, segments: [(CGPoint, CGPoint, CGPoint)], closed: Bool, fill: DiagramColor?, stroke: Stroke?) {
    var d = "M\(f(start.x)) \(f(start.y))"
    for (c1, c2, end) in segments {
      if c1 == end && c2 == end { d += " L\(f(end.x)) \(f(end.y))" } else { d += " C\(f(c1.x)) \(f(c1.y)) \(f(c2.x)) \(f(c2.y)) \(f(end.x)) \(f(end.y))" }
    }
    if closed { d += " Z" }
    body += "<path d=\"\(d)\"\(attrs(fill: fill, stroke: stroke))/>\n"
  }

  public mutating func line(_ a: CGPoint, _ b: CGPoint, stroke: Stroke) {
    body += "<line x1=\"\(f(a.x))\" y1=\"\(f(a.y))\" x2=\"\(f(b.x))\" y2=\"\(f(b.y))\"\(attrs(fill: nil, stroke: stroke))/>\n"
  }

  public mutating func text(_ text: String, at origin: CGPoint, width: Double, align: TextAlign, style: TextStyle) {
    let lh = TextMetrics.lineHeight(style)
    let ascent = CTFontGetAscent(TextMetrics.font(style))
    let anchor = switch align { case .left: "start"; case .center: "middle"; case .right: "end" }
    let x = switch align { case .left: origin.x; case .center: origin.x + width / 2; case .right: origin.x + width }
    let weight = switch style.weight { case .regular: 400; case .medium: 500; case .semibold: 600; case .bold: 700 }
    let family = style.monospace ? "'SF Mono', ui-monospace, Menlo, monospace" : fontFamily
    for (i, line) in TextMetrics.lines(text).enumerated() {
      let y = origin.y + Double(i) * lh + ascent + 1
      body += "<text x=\"\(f(x))\" y=\"\(f(y))\" text-anchor=\"\(anchor)\" font-family=\"\(family)\" font-size=\"\(f(style.size))\" font-weight=\"\(weight)\"\(style.italic ? " font-style=\"italic\"" : "") fill=\"\(style.color.css)\">\(escape(line))</text>\n"
    }
  }

  public mutating func pieSlice(center: CGPoint, radius: Double, start: Double, end: Double, fill: DiagramColor, stroke: Stroke?) {
    let a = CGPoint(x: center.x + radius * cos(start), y: center.y + radius * sin(start))
    let b = CGPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
    let large = (end - start) > .pi ? 1 : 0
    body += "<path d=\"M\(f(center.x)) \(f(center.y)) L\(f(a.x)) \(f(a.y)) A\(f(radius)) \(f(radius)) 0 \(large) 1 \(f(b.x)) \(f(b.y)) Z\"\(attrs(fill: fill, stroke: stroke))/>\n"
  }

  private func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
  }

  public var svg: String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(f(size.width))\" height=\"\(f(size.height))\" viewBox=\"0 0 \(f(size.width)) \(f(size.height))\" role=\"img\">\n\(body)</svg>"
  }
}
