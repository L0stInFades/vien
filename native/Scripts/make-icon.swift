// Draws the app icon (macOS squircle, ink-blue gradient, white V) at every size the .icns needs.
// Built and run by Scripts/make-icon.sh (swiftc, then iconutil).
import AppKit

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

/// Apple's icon shape: a rounded rectangle with continuous corners, 22.37% radius, inset 9.4%.
func squircle(in rect: CGRect) -> NSBezierPath {
  let r = rect.width * 0.2237
  let p = NSBezierPath()
  let k: CGFloat = 0.55  // control-point pull for a smoother (continuous-looking) corner
  let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
  p.move(to: CGPoint(x: x0 + r, y: y0))
  p.line(to: CGPoint(x: x1 - r, y: y0))
  p.curve(to: CGPoint(x: x1, y: y0 + r), controlPoint1: CGPoint(x: x1 - r * (1 - k), y: y0), controlPoint2: CGPoint(x: x1, y: y0 + r * (1 - k)))
  p.line(to: CGPoint(x: x1, y: y1 - r))
  p.curve(to: CGPoint(x: x1 - r, y: y1), controlPoint1: CGPoint(x: x1, y: y1 - r * (1 - k)), controlPoint2: CGPoint(x: x1 - r * (1 - k), y: y1))
  p.line(to: CGPoint(x: x0 + r, y: y1))
  p.curve(to: CGPoint(x: x0, y: y1 - r), controlPoint1: CGPoint(x: x0 + r * (1 - k), y: y1), controlPoint2: CGPoint(x: x0, y: y1 - r * (1 - k)))
  p.line(to: CGPoint(x: x0, y: y0 + r))
  p.curve(to: CGPoint(x: x0 + r, y: y0), controlPoint1: CGPoint(x: x0, y: y0 + r * (1 - k)), controlPoint2: CGPoint(x: x0 + r * (1 - k), y: y0))
  p.close()
  return p
}

func draw(size: Int) -> NSImage {
  let s = CGFloat(size)
  let image = NSImage(size: NSSize(width: s, height: s))
  image.lockFocus()
  let inset = s * 0.094
  let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
  // Shadow under the tile.
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
  shadow.shadowBlurRadius = s * 0.02
  shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
  NSGraphicsContext.saveGraphicsState()
  shadow.set()
  NSColor(srgbRed: 0.13, green: 0.30, blue: 0.78, alpha: 1).setFill()
  squircle(in: rect).fill()
  NSGraphicsContext.restoreGraphicsState()
  // Gradient tile.
  let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.27, green: 0.55, blue: 1.0, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.28, blue: 0.80, alpha: 1),
  ])!
  gradient.draw(in: squircle(in: rect), angle: -90)
  // Soft highlight across the top.
  let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
  NSGraphicsContext.saveGraphicsState()
  squircle(in: rect).addClip()
  highlight.draw(in: CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: 90)
  NSGraphicsContext.restoreGraphicsState()
  // The V: two thick strokes meeting at the bottom, round caps, like a pen stroke.
  let v = NSBezierPath()
  let top = rect.minY + rect.height * 0.72
  let bottom = rect.minY + rect.height * 0.27
  let left = rect.minX + rect.width * 0.29
  let right = rect.minX + rect.width * 0.71
  v.move(to: CGPoint(x: left, y: top))
  v.line(to: CGPoint(x: rect.midX, y: bottom))
  v.line(to: CGPoint(x: right, y: top))
  v.lineWidth = rect.width * 0.13
  v.lineCapStyle = .round
  v.lineJoinStyle = .round
  NSGraphicsContext.saveGraphicsState()
  let vShadow = NSShadow()
  vShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
  vShadow.shadowBlurRadius = s * 0.015
  vShadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
  vShadow.set()
  NSColor.white.setStroke()
  v.stroke()
  NSGraphicsContext.restoreGraphicsState()
  image.unlockFocus()
  return image
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
  let pixels = points * scale
  let image = draw(size: pixels)
  guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
  let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
  try! png.write(to: dir.appendingPathComponent(name))
}
print("iconset written to \(dir.path)")
