// Draws the app icon: the black calligraphic wordmark "Vien" (Snell Roundhand Black, a copperplate
// script) on a white squircle. Small sizes, where four cursive letters cannot resolve, use a single
// "V" instead. Rendered at exact pixel sizes into an sRGB bitmap (deterministic on any display).
// Built and run by Scripts/make-icon.sh (swiftc, then iconutil).
import AppKit
import CoreText

guard CommandLine.arguments.count > 1 else { fputs("usage: make-icon <output-dir>\n", stderr); exit(2) }
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let faceName = "SnellRoundhand-Black"

/// A string set in the calligraphic face as one merged CGPath, with its ink bounding box.
func text(_ string: String) -> (CGPath, CGRect) {
  let font = CTFontCreateWithName(faceName as CFString, 200, nil)
  assert((CTFontCopyPostScriptName(font) as String) == faceName, "font \(faceName) not installed")
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font as NSFont]))
  let full = CGMutablePath()
  for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
    for i in 0..<n {
      if let g = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
        full.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
      }
    }
  }
  return (full, full.boundingBoxOfPath)
}
let word = text("Vien")
let monogram = text("V")

/// A continuous-curvature squircle (superellipse, exponent 5) inscribed in `rect` — the iOS/macOS
/// tile shape, rounder than a circular-arc rounded rectangle.
func squircle(in rect: CGRect) -> CGPath {
  let path = CGMutablePath()
  let n = 5.0, steps = 180
  let a = rect.width / 2, b = rect.height / 2
  for i in 0...steps {
    let t = Double(i) / Double(steps) * 2 * .pi
    let x = a * copysign(pow(abs(cos(t)), 2 / n), cos(t))
    let y = b * copysign(pow(abs(sin(t)), 2 / n), sin(t))
    let p = CGPoint(x: rect.midX + x, y: rect.midY + y)
    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
  }
  path.closeSubpath()
  return path
}

func render(px: Int) -> CGImage {
  let s = CGFloat(px)
  let space = CGColorSpace(name: CGColorSpace.sRGB)!
  let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.setAllowsAntialiasing(true)
  let inset = s * 0.098
  let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
  let tile = squircle(in: rect)
  // Soft contact shadow so the white tile reads on white backgrounds (Finder, Launchpad).
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.022,
    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
  ctx.addPath(tile); ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fillPath()
  ctx.restoreGState()
  // Hairline edge (a touch darker than before) so it is defined even where the shadow is faint.
  ctx.addPath(tile); ctx.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.78, blue: 0.78, alpha: 1))
  ctx.setLineWidth(max(1, s / 220)); ctx.strokePath()
  // The mark: the full word where it can resolve, a single V at tiny sizes.
  let useWord = px >= 64
  let (glyph, bbox) = useWord ? word : monogram
  let scale = useWord ? min(s * 0.76 / bbox.width, s * 0.60 / bbox.height) : s * 0.58 / bbox.height
  ctx.saveGState()
  // Centre by the ink box, nudged up ~3% (a script's visual mass sits low).
  ctx.translateBy(x: s / 2 - bbox.midX * scale, y: s / 2 - bbox.midY * scale + s * 0.03)
  ctx.scaleBy(x: scale, y: scale)
  ctx.addPath(glyph); ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)); ctx.fillPath()
  ctx.restoreGState()
  return ctx.makeImage()!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
  let image = render(px: points * scale)
  let rep = NSBitmapImageRep(cgImage: image)
  guard let png = rep.representation(using: .png, properties: [:]) else { continue }
  try? png.write(to: outDir.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
}
print("iconset written to \(outDir.path)")
