import AppKit
import VienDiagrams
import VienMath

/// Something drawn beneath a paragraph's text.
enum Overlay: Hashable {
  case mermaid(String)
  case math(String)
  case images([URL])
}

/// Cache + async loader for overlay bitmaps. Fragments ask synchronously; missing entries are
/// rendered in the background and the paragraph is invalidated when they arrive.
final class OverlayStore {
  static let shared = OverlayStore()

  struct Entry {
    var image: NSImage?
    var size: CGSize
    var error: String?
  }

  private var entries: [Key: Entry] = [:]
  private var inFlight: Set<Key> = []
  /// Who to tell when a key resolves.
  private var listeners: [Key: [(EditorTextView, NSRange)]] = [:]

  struct Key: Hashable {
    let overlay: Overlay
    let width: Int
    let dark: Bool
  }

  func entry(for overlay: Overlay, width: CGFloat, dark: Bool, requester: EditorTextView?, range: NSRange) -> Entry? {
    let key = Key(overlay: overlay, width: Int(width), dark: dark)
    if let e = entries[key] { return e }
    if let requester {
      listeners[key, default: []].append((requester, range))
    }
    if !inFlight.contains(key) {
      inFlight.insert(key)
      Task { await self.load(key) }
    }
    return nil
  }

  private func load(_ key: Key) async {
    var entry = Entry(image: nil, size: .zero, error: nil)
    let width = CGFloat(key.width)
    switch key.overlay {
    case .mermaid(let src):
      do {
        let r = try DiagramRenderer.render(src, dark: key.dark, maxWidth: width)
        entry = Entry(image: NSImage(cgImage: r.image, size: r.size), size: r.size, error: nil)
      } catch {
        entry.error = "\(error)"
      }
    case .math(let src):
      do {
        let r = try MathRenderer.render(src, display: true, fontSize: 18, dark: key.dark)
        entry = Entry(image: NSImage(cgImage: r.image, size: r.size), size: r.size, error: nil)
      } catch {
        entry.error = "\(error)"
      }
    case .images(let urls):
      var images: [NSImage] = []
      for url in urls {
        if let img = await ImageLoader.shared.image(for: url) { images.append(img) }
      }
      if let first = images.first {
        // Stack images vertically, each fitted to the column width.
        var total: CGFloat = 0
        var fitted: [(NSImage, CGSize)] = []
        for img in images {
          let s = img.size
          let scale = s.width > width ? width / s.width : 1
          let fs = CGSize(width: s.width * scale, height: s.height * scale)
          fitted.append((img, fs))
          total += fs.height + 8
        }
        let composite = NSImage(size: CGSize(width: width, height: max(1, total - 8)))
        composite.lockFocus()
        var y = composite.size.height
        for (img, fs) in fitted {
          y -= fs.height
          img.draw(in: CGRect(x: 0, y: y, width: fs.width, height: fs.height))
          y -= 8
        }
        composite.unlockFocus()
        _ = first
        entry = Entry(image: composite, size: composite.size, error: nil)
      } else {
        entry.error = "image not found"
      }
    }
    entries[key] = entry
    inFlight.remove(key)
    let waiting = listeners.removeValue(forKey: key) ?? []
    for (view, range) in waiting { view.invalidateParagraphs(in: range) }
  }

  func clear() { entries.removeAll() }
}

/// Loads local and remote images with a small memory cache.
final class ImageLoader {
  static let shared = ImageLoader()
  private var cache: [URL: NSImage] = [:]

  func image(for url: URL) async -> NSImage? {
    if let hit = cache[url] { return hit }
    var image: NSImage?
    if url.isFileURL {
      image = NSImage(contentsOf: url)
    } else if let (data, _) = try? await URLSession.shared.data(from: url) {
      image = NSImage(data: data)
    }
    if let image { cache[url] = image }
    return image
  }
}

/// Draws a rendered diagram / formula / image below the paragraph's text and reserves the space.
nonisolated final class OverlayFragment: NSTextLayoutFragment {
  let overlay: Overlay
  let contentWidth: CGFloat
  let dark: Bool
  let palette: Palette
  private let padding: CGFloat = 10
  private let placeholderHeight: CGFloat = 56

  init(textElement: NSTextElement, range: NSTextRange?, overlay: Overlay, contentWidth: CGFloat, dark: Bool, palette: Palette) {
    self.overlay = overlay
    self.contentWidth = max(120, contentWidth - 24)
    self.dark = dark
    self.palette = palette
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) { fatalError() }

  private func lookup() -> OverlayStore.Entry? {
    // TextKit lays out and draws NSTextView content on the main thread.
    nonisolated(unsafe) let me = self
    return MainActor.assumeIsolated {
      var view: EditorTextView? = nil
      var range = NSRange(location: 0, length: 0)
      if let tlm = me.textLayoutManager, let tv = tlm.textContainer?.textView as? EditorTextView {
        view = tv
        if let cs = tlm.textContentManager as? NSTextContentStorage, let er = me.textElement?.elementRange {
          let loc = cs.offset(from: cs.documentRange.location, to: er.location)
          let len = cs.offset(from: er.location, to: er.endLocation)
          range = NSRange(location: loc, length: len)
        }
      }
      return OverlayStore.shared.entry(for: me.overlay, width: me.contentWidth, dark: me.dark, requester: view, range: range)
    }
  }

  private var extraHeight: CGFloat {
    if let e = lookup() {
      if let _ = e.image { return e.size.height + padding * 2 }
      return 24 + padding  // error line
    }
    return placeholderHeight
  }

  override var layoutFragmentFrame: CGRect {
    var f = super.layoutFragmentFrame
    f.size.height += extraHeight
    return f
  }

  override var renderingSurfaceBounds: CGRect {
    var b = super.renderingSurfaceBounds
    b.size.height += extraHeight
    b.size.width = max(b.size.width, contentWidth + 24)
    return b
  }

  override func draw(at point: CGPoint, in ctx: CGContext) {
    super.draw(at: point, in: ctx)
    let textHeight = super.layoutFragmentFrame.height
    let top = point.y + textHeight + padding
    let entry = lookup()
    ctx.saveGState()
    if let entry, let image = entry.image {
      let s = entry.size
      let scale = s.width > contentWidth ? contentWidth / s.width : 1
      let size = CGSize(width: s.width * scale, height: s.height * scale)
      let x = point.x + max(0, (contentWidth - size.width) / 2) + 12
      let rect = CGRect(x: x, y: top, width: size.width, height: size.height)
      NSGraphicsContext.saveGraphicsState()
      let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
      NSGraphicsContext.current = gc
      image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
      NSGraphicsContext.restoreGraphicsState()
    } else {
      let label = entry?.error.map { "⚠︎ \($0)" } ?? "Rendering…"
      let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12), .foregroundColor: palette.marker,
      ]
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
      (label as NSString).draw(at: CGPoint(x: point.x + 12, y: top), withAttributes: attrs)
      NSGraphicsContext.restoreGraphicsState()
    }
    ctx.restoreGState()
  }
}

/// Draws block decorations: a rule for `---`, a bar for quotes, a background for code blocks.
nonisolated final class DecoratedFragment: NSTextLayoutFragment {
  let decoration: MarkdownParagraph.Decoration
  let palette: Palette

  init(textElement: NSTextElement, range: NSTextRange?, decoration: MarkdownParagraph.Decoration, palette: Palette) {
    self.decoration = decoration
    self.palette = palette
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) { fatalError() }

  override var renderingSurfaceBounds: CGRect {
    var b = super.renderingSurfaceBounds
    let width = textLayoutManager?.textContainer?.size.width ?? b.width
    b.origin.x -= 12
    b.size.width = max(b.width, width) + 24
    return b
  }

  override func draw(at point: CGPoint, in ctx: CGContext) {
    let frame = super.layoutFragmentFrame
    ctx.saveGState()
    switch decoration {
    case .rule:
      ctx.setStrokeColor(palette.rule.cgColor)
      ctx.setLineWidth(1)
      // The fragment frame only spans the marker's glyphs; the rule spans the container.
      let width = textLayoutManager?.textContainer?.size.width ?? frame.width
      // Through the middle of the marker's dashes: a hyphen sits about half an x-height up.
      var y = frame.height / 2
      if let line = textLineFragments.first, line.attributedString.length > 0,
        let font = line.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
      {
        y = line.typographicBounds.minY + line.glyphOrigin.y - font.xHeight / 2  // glyphOrigin is relative to the line's bounds
      }
      y = (point.y + y).rounded() + 0.5
      ctx.move(to: CGPoint(x: point.x, y: y))
      ctx.addLine(to: CGPoint(x: point.x + width, y: y))
      ctx.strokePath()
      // Draw the text faintly so it stays editable but recedes behind the rule.
      ctx.setAlpha(0.35)
      super.draw(at: point, in: ctx)
    case .quote:
      ctx.setFillColor(palette.rule.cgColor)
      ctx.fill(CGRect(x: point.x - 10, y: point.y, width: 3, height: frame.height))
      super.draw(at: point, in: ctx)
    case .codeBlock(let first, let last):
      let bg = palette.codeBackground.cgColor
      let width = textLayoutManager?.textContainer?.size.width ?? frame.width
      var rect = CGRect(x: point.x - 8, y: point.y, width: width + 16, height: frame.height)
      // Paragraph spacing after the last line is not part of the background.
      if last, let style = (textElement as? NSTextParagraph)?.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
        rect.size.height -= style.paragraphSpacing
      }
      let path = CGMutablePath()
      let radius: CGFloat = 6
      if first && last {
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
      } else if first {
        path.addRoundedRect(in: rect.insetBy(dx: 0, dy: 0), cornerWidth: radius, cornerHeight: radius)
        path.addRect(CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2))
      } else if last {
        path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        path.addRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2))
      } else {
        path.addRect(rect)
      }
      ctx.setFillColor(bg)
      ctx.addPath(path)
      ctx.fillPath()
      super.draw(at: point, in: ctx)
    case .none, .table, .hiddenLine:
      super.draw(at: point, in: ctx)
    }
    ctx.restoreGState()
  }
}
