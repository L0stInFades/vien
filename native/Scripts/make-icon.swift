// Draws the app icon: a white squircle tile with the black calligraphic wordmark "Vien"
// (Snell Roundhand Bold, a copperplate script), centred by the word's ink bounds. Rendered at
// every size the .icns needs. Built and run by Scripts/make-icon.sh (swiftc, then iconutil).
import AppKit
import CoreText

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// The "Vien" wordmark as one CGPath (glyphs laid out and merged), plus its ink bounding box.
let (wordPath, wordBounds): (CGPath, CGRect) = {
  let font = CTFontCreateWithName("SnellRoundhand-Bold" as CFString, 200, nil)
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Vien", attributes: [.font: font as NSFont]))
  let full = CGMutablePath()
  for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let n = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: n), positions = [CGPoint](repeating: .zero, count: n)
    CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
    let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
    for i in 0..<n where CTFontCreatePathForGlyph(runFont, glyphs[i], nil) != nil {
      full.addPath(CTFontCreatePathForGlyph(runFont, glyphs[i], nil)!, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
    }
  }
  return (full, full.boundingBoxOfPath)
}()

/// Apple's icon tile: a rounded rectangle, ~9% inset, 22.37% corner radius.
func tile(_ rect: CGRect) -> CGPath {
  CGPath(roundedRect: rect, cornerWidth: rect.width * 0.2237, cornerHeight: rect.height * 0.2237, transform: nil)
}

func draw(size px: Int) -> NSImage {
  let s = CGFloat(px)
  let image = NSImage(size: NSSize(width: s, height: s))
  image.lockFocus()
  let ctx = NSGraphicsContext.current!.cgContext
  ctx.interpolationQuality = .high
  let inset = s * 0.086
  let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
  let path = tile(rect)
  ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
  ctx.addPath(path); ctx.setStrokeColor(NSColor(white: 0.82, alpha: 1).cgColor)
  ctx.setLineWidth(max(1, s / 200)); ctx.strokePath()
  // The wordmark fits within 80% of the tile width (or 46% height), centred by its ink bounds.
  let scale = min(s * 0.80 / wordBounds.width, s * 0.46 / wordBounds.height)
  ctx.saveGState()
  ctx.translateBy(x: s / 2 - wordBounds.midX * scale, y: s / 2 - wordBounds.midY * scale)
  ctx.scaleBy(x: scale, y: scale)
  ctx.addPath(wordPath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
  ctx.restoreGState()
  image.unlockFocus()
  return image
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
  let image = draw(size: points * scale)
  guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
  try! png.write(to: outDir.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
}
print("iconset written to \(outDir.path)")
