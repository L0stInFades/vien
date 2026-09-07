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
        entry.error = "image not found: " + urls.map { $0.lastPathComponent }.joined(separator: ", ")
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
nonisolated final class OverlayFragment: MarkdownFragment {
  let overlay: Overlay
  private let initialWidth: CGFloat
  let dark: Bool
  private let padding: CGFloat = 10
  private let placeholderHeight: CGFloat = 56

  init(textElement: NSTextElement, range: NSTextRange?, overlay: Overlay, contentWidth: CGFloat, dark: Bool, decor: Decor, palette: Palette) {
    self.overlay = overlay
    self.initialWidth = contentWidth
    self.dark = dark
    super.init(textElement: textElement, range: range, decor: decor, palette: palette)
  }

  /// Where a picture goes, in the coordinates `draw(at:in:)` is given: the text column, the same
  /// measure as the prose, so its edges line up with the paragraphs around it.
  /// `super`, not `self`: this fragment's frame is measured from the picture, which needs the box.
  private var box: (x: CGFloat, width: CGFloat) {
    (-super.layoutFragmentFrame.minX, max(120, textLayoutManager?.textContainer?.size.width ?? initialWidth))
  }

  var contentWidth: CGFloat { box.width }

  /// The size the picture is drawn at: its own, or shrunk to the width it has.
  private func drawn(_ natural: CGSize) -> CGSize {
    guard natural.width > box.width, natural.width > 0 else { return natural }
    return CGSize(width: box.width, height: (natural.height * box.width / natural.width).rounded())
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
      if e.image != nil { return drawn(e.size).height + padding * 2 }
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
    let left = min(b.minX, box.x), right = max(b.maxX, box.x + box.width)
    b.origin.x = left
    b.size.width = right - left
    return b
  }

  override func draw(at point: CGPoint, in ctx: CGContext) {
    super.draw(at: point, in: ctx)
    let top = point.y + baseHeight + padding
    let entry = lookup()
    ctx.saveGState()
    if let entry, let image = entry.image {
      let size = drawn(entry.size)
      let rect = CGRect(x: point.x + box.x + ((box.width - size.width) / 2).rounded(), y: top, width: size.width, height: size.height)
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
      (label as NSString).draw(at: CGPoint(x: point.x + box.x, y: top), withAttributes: attrs)
      NSGraphicsContext.restoreGraphicsState()
    }
    ctx.restoreGState()
  }
}
