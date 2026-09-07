// Draws the app icon: the black calligraphic wordmark "Vien" (Snell Roundhand Black, a copperplate
// script) on a white tile. Small sizes, where four cursive letters cannot resolve, use a single "V".
// Rendered at exact pixel sizes into an sRGB bitmap (deterministic on any display).
// Built and run by Scripts/make-icon.sh (swiftc, then iconutil).
//
// The tile follows Apple's macOS icon grid, measured from the system's own icons: on a 1024 canvas
// the body is 824 square, centred, with a continuous-curvature corner of radius 185.4 (SwiftUI's
// `.continuous` style, so the curve is the platform's own, not an approximation), and a soft
// downward shadow that grounds it on a light background. No outline: system icons have none.
import AppKit
import CoreText
import SwiftUI

guard CommandLine.arguments.count > 1 else { fputs("usage: make-icon <output-dir>\n", stderr); exit(2) }
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let faceName = "SnellRoundhand-Black"

/// Apple's icon grid, as fractions of the canvas (1024 in the published template).
enum Grid {
  static let body = 824.0 / 1024                 // the tile's side
  static let corner = 185.4 / 824                // of the tile's side
  /// Two shadows, as the system's icons have: a tight contact shadow where the tile meets the
  /// surface, and a wide ambient one under it. Blur, drop and alpha, all as fractions of the canvas.
  static let shadows = [(blur: 24.0 / 1024, drop: 10.0 / 1024, alpha: 0.32), (blur: 5.0 / 1024, drop: 3.0 / 1024, alpha: 0.30)]
  /// How much of the tile the mark may fill, so it sits inside the icon rather than against its edge.
  static let markWidth = 0.75, markHeight = 0.46
  static let monogramHeight = 0.56
}

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

func render(px: Int) -> CGImage {
  let s = CGFloat(px)
  let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.interpolationQuality = .high
  ctx.setAllowsAntialiasing(true)

  let side = (s * Grid.body).rounded()
  let tile = CGRect(x: ((s - side) / 2).rounded(), y: ((s - side) / 2).rounded(), width: side, height: side)
  let shape = RoundedRectangle(cornerRadius: side * Grid.corner, style: .continuous).path(in: tile).cgPath

  // The tile is paper: white, with the faintest fall-off towards its foot, cast on the surface twice.
  for shadow in Grid.shadows {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * shadow.drop), blur: s * shadow.blur,
      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: shadow.alpha))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
  }
  ctx.saveGState()
  ctx.addPath(shape)
  ctx.clip()
  let paper = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), CGColor(srgbRed: 0.965, green: 0.965, blue: 0.961, alpha: 1)] as CFArray,
    locations: [0, 1])!
  ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
  ctx.restoreGState()

  // The mark: the full word where it can resolve, a single V at tiny sizes.
  let useWord = px >= 64
  let (glyph, bbox) = useWord ? word : monogram
  let scale = useWord
    ? min(side * Grid.markWidth / bbox.width, side * Grid.markHeight / bbox.height)
    : side * Grid.monogramHeight / bbox.height
  ctx.saveGState()
  // Centre by the ink box, nudged up a little: a script's visual mass sits below its middle.
  ctx.translateBy(x: tile.midX - bbox.midX * scale, y: tile.midY - bbox.midY * scale + side * 0.025)
  ctx.scaleBy(x: scale, y: scale)
  ctx.addPath(glyph)
  ctx.setFillColor(CGColor(srgbRed: 0.071, green: 0.071, blue: 0.078, alpha: 1))  // ink, not pure black
  ctx.fillPath()
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
