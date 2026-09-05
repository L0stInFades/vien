import CoreGraphics
import CoreText
import Foundation

/// A typeset formula: Retina bitmap in points, plus the baseline offset for inline placement.
public struct RenderedMath: Sendable {
  public let image: CGImage
  public let size: CGSize
  /// Distance from the top of the image to the baseline, in points.
  public let baseline: Double
}

/// Native TeX math: parse → box layout with STIX Two Math → Core Graphics; MathML for exports.
public enum MathRenderer {
  /// Fill colour for the formula being drawn (CGContext cannot report its own fill colour).
  nonisolated(unsafe) static var currentColor: CGColor?

  public static func render(_ source: String, display: Bool, fontSize: Double, dark: Bool, scale: CGFloat = 2) throws -> RenderedMath {
    let node = try MathParser.parse(source)
    let layout = MathLayout(size: fontSize)
    let box = layout.layout(node, MathLayout.Style(level: display ? .display : .text))
    let pad = fontSize * 0.25
    let width = max(4, box.width + pad * 2).rounded(.up)
    let height = max(4, box.height + pad * 2).rounded(.up)
    let w = Int(width * scale), h = Int(height * scale)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw MathSyntaxError(description: "could not allocate a bitmap")
    }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.setShouldSmoothFonts(true)
    let color = dark ? CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1) : CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    ctx.setFillColor(color)
    ctx.setStrokeColor(color)
    currentColor = color
    box.draw(ctx, CGPoint(x: pad, y: pad + box.ascent))
    currentColor = nil
    guard let image = ctx.makeImage() else { throw MathSyntaxError(description: "could not render") }
    return RenderedMath(image: image, size: CGSize(width: width, height: height), baseline: pad + box.ascent)
  }

  /// Parses without rendering; returns a message when the source is invalid.
  public static func validate(_ source: String) -> String? {
    do { _ = try MathParser.parse(source); return nil } catch { return "\(error)" }
  }

  public static func mathML(_ source: String, display: Bool) throws -> String {
    let node = try MathParser.parse(source)
    return "<math xmlns=\"http://www.w3.org/1998/Math/MathML\" display=\"\(display ? "block" : "inline")\">\(MathML.render(node))</math>"
  }
}

enum MathML {
  static func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
  }

  static func render(_ node: MathNode) -> String {
    switch node {
    case .symbol(let s, let atom, let variant):
      let mapped = String(String.UnicodeScalarView(s.unicodeScalars.map { MathAlphabet.map($0, variant) }))
      if s.unicodeScalars.allSatisfy({ $0.properties.numericType != nil }) { return "<mn>\(esc(s))</mn>" }
      switch atom {
      case .ord where s.unicodeScalars.first.map({ $0.properties.isAlphabetic }) == true:
        return variant == .italic ? "<mi>\(esc(s))</mi>" : "<mi mathvariant=\"normal\">\(esc(mapped))</mi>"
      case .ord: return "<mi>\(esc(mapped))</mi>"
      default: return "<mo>\(esc(s))</mo>"
      }
    case .text(let s, let isOp):
      return isOp ? "<mi>\(esc(s))</mi><mo>&#x2061;</mo>" : "<mtext>\(esc(s))</mtext>"
    case .row(let items):
      return "<mrow>\(items.map(render).joined())</mrow>"
    case .scripts(let base, let sub, let sup, let limits):
      let b = render(base)
      switch (sub, sup) {
      case (let s?, let p?): return limits ? "<munderover>\(b)\(render(s))\(render(p))</munderover>" : "<msubsup>\(b)\(render(s))\(render(p))</msubsup>"
      case (let s?, nil): return limits ? "<munder>\(b)\(render(s))</munder>" : "<msub>\(b)\(render(s))</msub>"
      case (nil, let p?): return limits ? "<mover>\(b)\(render(p))</mover>" : "<msup>\(b)\(render(p))</msup>"
      default: return b
      }
    case .fraction(let n, let d, let rule):
      return "<mfrac\(rule ? "" : " linethickness=\"0\"")>\(render(n))\(render(d))</mfrac>"
    case .root(let body, let index):
      if let index { return "<mroot>\(render(body))\(render(index))</mroot>" }
      return "<msqrt>\(render(body))</msqrt>"
    case .fenced(let l, let body, let r):
      var s = "<mrow>"
      if let l { s += "<mo stretchy=\"true\">\(esc(l))</mo>" }
      s += render(body)
      if let r { s += "<mo stretchy=\"true\">\(esc(r))</mo>" }
      return s + "</mrow>"
    case .accent(let mark, let body, _):
      return "<mover accent=\"true\">\(render(body))<mo>\(esc(mark))</mo></mover>"
    case .overline(let body): return "<mover accent=\"true\">\(render(body))<mo>&#x203E;</mo></mover>"
    case .underline(let body): return "<munder accentunder=\"true\">\(render(body))<mo>&#x332;</mo></munder>"
    case .space(let em): return "<mspace width=\"\(String(format: "%.2f", em))em\"/>"
    case .table(let rows, let env):
      if env.hasPrefix("bigdelim:"), let first = rows.first?.first { return render(first) }
      let align = ["aligned", "align", "split"].contains(env) ? " columnalign=\"right left\"" : env == "cases" ? " columnalign=\"left\"" : ""
      let body = rows.map { "<mtr>" + $0.map { "<mtd>\(render($0))</mtd>" }.joined() + "</mtr>" }.joined()
      return "<mtable\(align)>\(body)</mtable>"
    case .style(let level, let inner):
      let attrs = switch level {
      case .display: " displaystyle=\"true\""
      case .text: " displaystyle=\"false\""
      case .script: " displaystyle=\"false\" scriptlevel=\"1\""
      case .scriptScript: " displaystyle=\"false\" scriptlevel=\"2\""
      }
      return "<mstyle\(attrs)>\(render(inner))</mstyle>"
    case .boxed(let inner): return "<menclose notation=\"box\">\(render(inner))</menclose>"
    case .phantom(let inner, _, _): return "<mphantom>\(render(inner))</mphantom>"
    case .error(let message): return "<merror><mtext>\(esc(message))</mtext></merror>"
    }
  }
}
