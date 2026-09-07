import AppKit
import Foundation

/// A rendered diagram: a Retina bitmap sized in points plus the SVG for exports.
public struct RenderedDiagram: Sendable {
  public let image: CGImage
  public let size: CGSize
  public let svg: String
}

/// Public entry point: Mermaid source in, native bitmap and SVG out. Pure Swift, synchronous, and
/// fast enough to run on the main actor for every diagram on screen.
public enum DiagramRenderer {
  public static func render(_ source: String, dark: Bool, maxWidth: Double, scale: CGFloat = 2) throws -> RenderedDiagram {
    let theme = dark ? DiagramTheme.dark : DiagramTheme.light
    let diagram = try Mermaid.parse(source)
    var size: CGSize
    var draw: (inout any Canvas) -> Void
    switch diagram {
    case .graph(let g):
      // A long chain laid out across the page has to be shrunk to fit the column, and shrunk text
      // cannot be read; the same chain laid out down the page keeps its size. Try the author's
      // direction and the quarter turn of it, and keep whichever survives the fit better.
      var r = GraphRenderer(diagram: g, theme: theme)
      if maxWidth > 0, r.size.width > maxWidth {
        var turned = g
        turned.direction = g.direction.turned
        let alternative = GraphRenderer(diagram: turned, theme: theme)
        if min(1, maxWidth / alternative.size.width) > min(1, maxWidth / r.size.width) { r = alternative }
      }
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .sequence(let s):
      let r = SequenceRenderer(diagram: s, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .pie(let p):
      let r = PieRenderer(diagram: p, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .gantt(let g):
      let r = GanttRenderer(diagram: g, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .timeline(let t):
      let r = TimelineRenderer(diagram: t, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .journey(let j):
      let r = JourneyRenderer(diagram: j, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .quadrant(let q):
      let r = QuadrantRenderer(diagram: q, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .xychart(let x):
      let r = XYChartRenderer(diagram: x, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .gitGraph(let g):
      let r = GitGraphRenderer(diagram: g, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .mindmap(let m):
      let r = MindmapRenderer(diagram: m, theme: theme)
      size = r.size
      draw = { c in r.draw(on: &c) }
    case .unsupported(let kind):
      throw DiagramSyntaxError(line: 1, message: "“\(kind)” diagrams are not supported yet")
    }
    size = CGSize(width: max(24, size.width.rounded(.up)), height: max(24, size.height.rounded(.up)))
    // Bitmap: drawn at the natural size; the editor scales anything still too wide down to fit.
    guard let cg = CGCanvas.makeImage(size: size, scale: scale, background: nil, draw: { canvas in
      var any: any Canvas = canvas
      draw(&any)
      canvas = any as! CGCanvas
    }) else { throw DiagramSyntaxError(line: 1, message: "could not allocate a bitmap") }
    var svgCanvas: any Canvas = SVGCanvas(size: size)
    draw(&svgCanvas)
    return RenderedDiagram(image: cg, size: size, svg: (svgCanvas as! SVGCanvas).svg)
  }

  /// Parses without rendering (used to report syntax errors early).
  public static func validate(_ source: String) -> String? {
    do { _ = try Mermaid.parse(source); return nil } catch { return "\(error)" }
  }
}
