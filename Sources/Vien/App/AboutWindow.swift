import AppKit
import QuartzCore

/// About Vien: a pointed pen writes the wordmark in front of you, the ink dries, the version settles
/// in beneath it. Nothing else on the page. Drag on it to write with the same pen; click the word to
/// have it written again (never quite the same hand twice); hold ⌥ for the build; ⌘C copies it.
final class AboutWindowController: NSWindowController, NSWindowDelegate {
  private let page = InkView(frame: NSRect(x: 0, y: 0, width: 440, height: 320))
  private let caption = NSTextField(labelWithString: "")

  init() {
    let window = NSWindow(contentRect: page.frame, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "About Vien"
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
    super.init(window: window)
    window.delegate = self
    window.contentView = page
    caption.alignment = .center
    caption.font = .systemFont(ofSize: 11)
    caption.textColor = .secondaryLabelColor
    caption.alphaValue = 0
    caption.frame = NSRect(x: 0, y: 72, width: page.frame.width, height: 16)
    caption.autoresizingMask = [.width]
    page.addSubview(caption)
    page.onSettled = { [weak self] in self?.reveal() }
    page.onModifiers = { [weak self] option in self?.caption.stringValue = option ? Self.build : Self.version }
    page.onCopy = { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(Self.build, forType: .string) }
    window.center()
  }

  required init?(coder: NSCoder) { fatalError() }

  static var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "Version \(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
  }

  static var build: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let commit = (info["VienCommit"] as? String).map { " · \($0)" } ?? ""
    return "\(info["NSHumanReadableCopyright"] ?? "")\(commit)"
  }

  override func showWindow(_ sender: Any?) {
    caption.stringValue = NSEvent.modifierFlags.contains(.option) ? Self.build : Self.version
    caption.alphaValue = 0
    super.showWindow(sender)
    window?.makeFirstResponder(page)
    page.write()
  }

  private func reveal() {
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.9
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      caption.animator().alphaValue = 1
    }
  }

  func windowWillClose(_ notification: Notification) { page.stop() }
}

/// The page: the wordmark being written, plus whatever the reader writes on it.
final class InkView: NSView {
  var onSettled: (() -> Void)?
  var onModifiers: ((Bool) -> Void)?
  var onCopy: (() -> Void)?

  private var writing = Handwriting.vien()
  private var clock: TimeInterval = 0
  private var lastTick: TimeInterval = 0
  private var link: CADisplayLink?
  private var settled = false
  private var doodles: [Pen.Trail] = []
  private var doodle: Pen.Trail?
  /// The reader's pen, as it moves: positions and times, before the spline smooths them.
  private var pen: [(CGPoint, TimeInterval)] = []
  private var seed: UInt64 = 0
  /// Dry ink, baked into a bitmap as the pen advances: a frame blits it and paints only what is
  /// still wet, so the cost never grows with the amount of ink on the page.
  private var paper: CGContext?
  private var baked: [CGFloat] = []
  private var bakedDoodles = 0
  private var frameTimes: (total: TimeInterval, peak: TimeInterval, count: Int) = (0, 0, 0)

  override var acceptsFirstResponder: Bool { true }
  override var isFlipped: Bool { false }

  /// Points per x-height, and where the wordmark's origin sits in the view.
  private var scale: CGFloat { 42 }
  private var origin: CGPoint {
    let box = Handwriting.letters
    return CGPoint(x: bounds.midX - box.midX * scale, y: bounds.height * 0.60 - box.midY * scale)
  }

  func write() {
    writing = Handwriting.vien(seed: seed)
    clock = 0
    settled = false
    paper = nil
    run()
  }

  /// Keeps the clock going while ink is being laid down or is still drying.
  private func run() {
    lastTick = CACurrentMediaTime()
    if link == nil {
      link = displayLink(target: self, selector: #selector(tick))
      link?.add(to: .main, forMode: .common)
    }
    needsDisplay = true
  }

  func stop() {
    link?.invalidate()
    link = nil
    if traceEnabled, frameTimes.count > 0 {
      trace(String(format: "about: %d frames, draw %.2f ms average, %.2f ms peak", frameTimes.count, frameTimes.total / Double(frameTimes.count) * 1000, frameTimes.peak * 1000))
      frameTimes = (0, 0, 0)
    }
  }

  override func viewDidChangeEffectiveAppearance() { paper = nil; needsDisplay = true }
  override func viewDidChangeBackingProperties() { paper = nil; needsDisplay = true }

  @objc private func tick() {
    let now = CACurrentMediaTime()
    clock += now - lastTick
    lastTick = now
    for i in writing.strokes.indices { writing.strokes[i].advance(to: clock, now: now) }
    if !settled, clock >= writing.duration {
      settled = true
      onSettled?()
    }
    let drying = writing.strokes.contains { $0.trail.wet(at: now) } || doodles.contains { $0.wet(at: now) } || doodle != nil
    if settled, !drying { stop() }
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let started = CACurrentMediaTime()
    let now = started
    // Ink is opaque: the label colour laid on the page colour, so overlapping strokes stay one tone.
    let page = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? .white
    let label = NSColor.labelColor.usingColorSpace(.sRGB) ?? .black
    let ink = (page.blended(withFraction: label.alphaComponent, of: label.withAlphaComponent(1)) ?? label).cgColor
    let wetInk = NSColor.textColor.cgColor
    if paper == nil { paper = makePaper(); baked = Array(repeating: 0, count: writing.strokes.count); bakedDoodles = 0 }
    if let paper {
      paper.setFillColor(ink)
      for (i, stroke) in writing.strokes.enumerated() where stroke.trail.written > baked[i] {
        paper.addPath(stroke.trail.discs(from: baked[i], to: stroke.trail.written))
        paper.fillPath()
        baked[i] = stroke.trail.written
      }
      while bakedDoodles < doodles.count {
        paper.addPath(doodles[bakedDoodles].discs(from: 0, to: doodles[bakedDoodles].length))
        paper.fillPath()
        bakedDoodles += 1
      }
      if let image = paper.makeImage() { ctx.draw(image, in: bounds) }
    }
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    for stroke in writing.strokes { stroke.trail.drawWet(in: ctx, wetInk: wetInk, now: now) }
    for trail in doodles { trail.drawWet(in: ctx, wetInk: wetInk, now: now) }
    if let doodle {
      ctx.setFillColor(ink)
      ctx.addPath(doodle.discs(from: 0, to: doodle.length))
      ctx.fillPath()
      doodle.drawWet(in: ctx, wetInk: wetInk, now: now)
    }
    ctx.restoreGState()
    let took = CACurrentMediaTime() - started
    frameTimes = (frameTimes.total + took, max(frameTimes.peak, took), frameTimes.count + 1)
  }

  /// A bitmap the size of the view, in the wordmark's coordinates.
  private func makePaper() -> CGContext? {
    let s = window?.backingScaleFactor ?? 2
    guard let ctx = CGContext(data: nil, width: Int(bounds.width * s), height: Int(bounds.height * s), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.scaleBy(x: scale, y: scale)
    return ctx
  }

  // MARK: - The reader's pen

  /// View point → the pen's own coordinates (x-heights, y up).
  private func penPoint(_ event: NSEvent) -> CGPoint {
    let p = convert(event.locationInWindow, from: nil)
    return CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    pen = [(penPoint(event), CACurrentMediaTime())]
    run()
  }

  override func mouseDragged(with event: NSEvent) {
    let p = penPoint(event), now = CACurrentMediaTime()
    guard let last = pen.last, hypot(p.x - last.0.x, p.y - last.0.y) > 0.01 else { return }
    pen.append((p, now))
    doodle = Self.stroke(pen, lifted: false)
    needsDisplay = true
  }

  override func mouseUp(with event: NSEvent) {
    defer { doodle = nil; pen = [] }
    guard let first = pen.first else { return }
    let end = penPoint(event)
    if pen.count < 3 || hypot(end.x - first.0.x, end.y - first.0.y) < 0.05 {
      // A click, not a stroke: on the word, it is written again in a slightly different hand.
      if writing.bounds.insetBy(dx: -0.2, dy: -0.2).contains(end) { seed &+= 1; write() }
      return
    }
    doodles.append(Self.stroke(pen, lifted: true))
  }

  /// A pen stroke from raw pen positions: width from direction and speed, a taper where it lifts.
  private static func stroke(_ raw: [(CGPoint, TimeInterval)], lifted: Bool) -> Pen.Trail {
    var total: CGFloat = 0
    var run: [CGFloat] = [0]
    for i in 1..<raw.count { total += hypot(raw[i].0.x - raw[i - 1].0.x, raw[i].0.y - raw[i - 1].0.y); run.append(total) }
    let waypoints = raw.indices.map { i -> (CGPoint, CGFloat, TimeInterval) in
      var width = Pen.hair
      if i > 0 {
        let speed = (run[i] - run[i - 1]) / max(0.001, raw[i].1 - raw[i - 1].1)
        width = Pen.Trail.width(raw[i - 1].0, raw[i].0, speed: min(speed, 8))
      }
      let toEnd = (total - run[i]) / Pen.taper
      if lifted, toEnd < 1 { width *= max(0.15, toEnd * toEnd * (3 - 2 * toEnd)) }
      return (raw[i].0, width, raw[i].1)
    }
    var trail = Pen.trail(through: waypoints)
    trail.written = trail.length
    return trail
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:  // Escape: clear your ink, or close
      if doodles.isEmpty { window?.close() } else { doodles.removeAll(); needsDisplay = true }
    default: super.keyDown(with: event)
    }
  }

  override func flagsChanged(with event: NSEvent) { onModifiers?(event.modifierFlags.contains(.option)) }

  @objc func copy(_ sender: Any?) { onCopy?() }
}

/// A pointed pen: hairlines wherever it rises or travels, weight wherever it comes down along the
/// slant, a taper at every lift. Measured in x-heights of the wordmark.
enum Pen {
  static let hair: CGFloat = 0.035, thick: CGFloat = 0.30, taper: CGFloat = 0.12
  /// The pen presses on the way down and lifts to a hairline everywhere else.
  static let down = CGPoint(x: 0, y: -1)
  static let dry: TimeInterval = 0.9

  /// A densely sampled pen path: where it went, how wide, how far, and when the ink arrived.
  /// The ink itself is the union of discs along the path (the medial-axis transform of the glyphs).
  struct Trail {
    var points: [CGPoint] = []
    var widths: [CGFloat] = []
    var lengths: [CGFloat] = []
    /// Cumulative effort: distance weighted by pressure, so the pen slows where it presses.
    var efforts: [CGFloat] = []
    var inked: [TimeInterval] = []
    var length: CGFloat { lengths.last ?? 0 }
    /// How much of the trail has been written (arc length).
    var written: CGFloat = 0

    /// Width from the direction of travel: the nib opens on the way down the slant, closes with speed.
    static func width(_ from: CGPoint, _ to: CGPoint, speed: CGFloat = 0) -> CGFloat {
      let dx = to.x - from.x, dy = to.y - from.y
      let n = hypot(dx, dy)
      guard n > 0 else { return hair }
      let down = max(0, (dx * Pen.down.x + dy * Pen.down.y) / n)
      let pressure = down * down * (3 - 2 * down)
      return (hair + (thick - hair) * pressure) / (1 + speed * 0.12)
    }

    /// Heavier strokes carry more ink and dry more slowly.
    func dry(_ i: Int) -> TimeInterval { Pen.dry * (0.6 + Double(widths[i] / Pen.thick)) }
    func wet(at now: TimeInterval) -> Bool { inked.last.map { now - $0 < Pen.dry * 1.8 } ?? false }

    /// The ink between two arc lengths, ending with the disc under the pen. Overlays on ink that is
    /// already there can skip samples (`stride`); the union stays the same.
    func discs(from a: CGFloat, to b: CGFloat, stride: Int = 1) -> CGPath {
      let path = CGMutablePath()
      var lo = 0, hi = lengths.count - 1
      while lo < hi { let mid = (lo + hi) / 2; if lengths[mid] < a { lo = mid + 1 } else { hi = mid } }
      var i = lo
      while i < points.count, lengths[i] <= b {
        path.addEllipse(in: CGRect(x: points[i].x - widths[i] / 2, y: points[i].y - widths[i] / 2, width: widths[i], height: widths[i]))
        i += stride
      }
      i = min(i, points.count)
      if i > 0, i < points.count {  // the pen between two samples
        let t = (b - lengths[i - 1]) / max(lengths[i] - lengths[i - 1], 1e-6)
        let p = CGPoint(x: points[i - 1].x + (points[i].x - points[i - 1].x) * t, y: points[i - 1].y + (points[i].y - points[i - 1].y) * t)
        let w = widths[i - 1] + (widths[i] - widths[i - 1]) * t
        path.addEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
      }
      return path
    }

    /// The ink still wet, drawn fresh over the dry ink beneath it; it fades in six steps, so the
    /// whole tail needs a handful of fills.
    func drawWet(in ctx: CGContext, wetInk: CGColor, now: TimeInterval) {
      guard written > 0, wet(at: now) else { return }
      func step(_ i: Int) -> Int { let age = now - inked[i]; return age.isFinite ? min(6, max(0, Int(age / dry(i) * 6))) : 6 }
      var start = points.count - 1
      while start > 0, step(start) < 6 { start -= 1 }
      while start < points.count - 1 {
        let level = step(start + 1)
        var end = start + 1
        while end < points.count - 1, step(end + 1) == level { end += 1 }
        let alpha = (1 - CGFloat(level) / 6) * 0.9
        if alpha > 0 {
          ctx.setFillColor(wetInk.copy(alpha: alpha) ?? wetInk)
          ctx.addPath(discs(from: lengths[start], to: min(written, lengths[end]), stride: 2))
          ctx.fillPath()
        }
        start = end
      }
    }
  }

  /// A centripetal Catmull-Rom spline through waypoints (position, width, ink time), sampled finely.
  static func trail(through waypoints: [(CGPoint, CGFloat, TimeInterval)]) -> Trail {
    var t = Trail()
    guard waypoints.count > 1 else { return t }
    let w = [waypoints[0]] + waypoints + [waypoints[waypoints.count - 1]]
    var samples: [(CGPoint, CGFloat, TimeInterval)] = []
    for i in 1..<(w.count - 2) {
      let (p0, p1, p2, p3) = (w[i - 1].0, w[i].0, w[i + 1].0, w[i + 2].0)
      func knot(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGFloat { t + max(1e-4, pow(hypot(b.x - a.x, b.y - a.y), 0.5)) }
      let t0: CGFloat = 0, t1 = knot(p0, p1, t0), t2 = knot(p1, p2, t1), t3 = knot(p2, p3, t2)
      let steps = max(6, Int(hypot(p2.x - p1.x, p2.y - p1.y) * 80))
      for s in 0..<steps {
        let f = CGFloat(s) / CGFloat(steps), u = t1 + (t2 - t1) * f
        func lerp(_ a: CGPoint, _ b: CGPoint, _ ta: CGFloat, _ tb: CGFloat) -> CGPoint {
          let k = (u - ta) / (tb - ta)
          return CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
        }
        let a1 = lerp(p0, p1, t0, t1), a2 = lerp(p1, p2, t1, t2), a3 = lerp(p2, p3, t2, t3)
        let b1 = lerp(a1, a2, t0, t2), b2 = lerp(a2, a3, t1, t3)
        samples.append((lerp(b1, b2, t1, t2), w[i].1 + (w[i + 1].1 - w[i].1) * f, w[i].2 + (w[i + 1].2 - w[i].2) * f))
      }
    }
    samples.append(waypoints[waypoints.count - 1])
    for (i, (p, width, time)) in samples.enumerated() {
      let step = i == 0 ? 0 : hypot(p.x - samples[i - 1].0.x, p.y - samples[i - 1].0.y)
      t.lengths.append(t.length + step)
      t.efforts.append((t.efforts.last ?? 0) + step * (1 + 2.5 * width / thick))
      t.points.append(p)
      t.widths.append(width)
      t.inked.append(time)
    }
    return t
  }
}

/// The wordmark as pen strokes with a schedule: V, a lift, "ien" in one breath, a lift, the dot.
struct Handwriting {
  struct Stroke {
    var trail: Pen.Trail
    let start: TimeInterval
    let duration: TimeInterval

    /// Moves the pen to where it should be at `time`: it eases in and out of the stroke and spends
    /// its time in proportion to effort, so heavy strokes are pressed slowly and hairlines fly.
    /// Newly covered samples get `now` as their ink time.
    mutating func advance(to time: TimeInterval, now: TimeInterval) {
      let u = min(1, max(0, (time - start) / duration))
      let eased = u < 0.5 ? 4 * u * u * u : 1 - pow(-2 * u + 2, 3) / 2
      let effort = (trail.efforts.last ?? 0) * CGFloat(eased)
      var lo = 0, hi = trail.efforts.count - 1
      while lo < hi { let mid = (lo + hi + 1) / 2; if trail.efforts[mid] <= effort { lo = mid } else { hi = mid - 1 } }
      var target = trail.lengths[lo]
      if lo + 1 < trail.efforts.count {
        let span = trail.efforts[lo + 1] - trail.efforts[lo]
        if span > 0 { target += (trail.lengths[lo + 1] - trail.lengths[lo]) * (effort - trail.efforts[lo]) / span }
      }
      guard target > trail.written else { return }
      for i in trail.points.indices where trail.lengths[i] > trail.written && trail.lengths[i] <= target { trail.inked[i] = now }
      trail.written = target
    }
  }

  var strokes: [Stroke]
  var duration: TimeInterval { strokes.map { $0.start + $0.duration }.max().map { $0 + 0.25 } ?? 0 }

  /// The box of the ink, in x-heights.
  var bounds: CGRect {
    var box = CGRect.null
    for s in strokes { for p in s.trail.points { box = box.union(CGRect(origin: p, size: .zero)) } }
    return box.insetBy(dx: -Pen.thick / 2, dy: -Pen.thick / 2)
  }

  /// The letters themselves, which is what the eye centres: the closing flourish of the n hangs
  /// outside it, into the margin, as a flourish should.
  static let letters = CGRect(x: 0.20, y: -0.06, width: 4.86, height: 2.02)

  /// The pen's route through the wordmark, traced from the medial axis of the icon's letters
  /// (Snell Roundhand Black) with the stroke width measured at every point: x, y, width in x-heights.
  private static let route: [(String, TimeInterval)] = [
    ("1.705,1.905,0.032 1.545,1.805,0.061 1.490,1.815,0.032 1.300,1.750,0.040 0.895,1.640,0.054 0.740,1.585,0.071 0.565,1.500,0.103 0.480,1.440,0.128 0.410,1.370,0.161 0.340,1.255,0.187 0.315,1.130,0.200 0.335,1.040,0.184 0.365,0.985,0.170 0.400,0.950,0.139 0.465,0.915,0.090 0.550,0.915,0.070 0.615,0.925,0.051 0.685,0.960,0.045 0.745,1.025,0.045 0.785,1.110,0.040 0.795,1.150,0.040 0.795,1.270,0.040 0.780,1.320,0.040", 0.30),
    ("1.705,1.905,0.032 1.670,1.890,0.032 1.545,1.800,0.060 1.535,1.770,0.071 1.425,1.650,0.128 1.315,1.495,0.199 1.245,1.370,0.247 1.140,1.140,0.316 0.985,0.745,0.330 0.920,0.555,0.306 0.845,0.380,0.260 0.770,0.240,0.210 0.765,0.200,0.189 0.610,0.040,0.103 0.520,-0.035,0.063 0.600,0.030,0.094 0.760,0.195,0.192 0.815,0.145,0.061 0.855,0.140,0.028 0.940,0.175,0.032 1.190,0.315,0.032 1.390,0.440,0.041 1.590,0.575,0.054 1.760,0.705,0.072 2.000,0.930,0.127 2.115,1.065,0.161 2.245,1.265,0.215 2.300,1.400,0.240", 0.55),
    ("2.335,1.750,0.350 2.355,1.680,0.320 2.350,1.595,0.290 2.325,1.470,0.262 2.290,1.360,0.240 2.220,1.215,0.206 2.220,1.070,0.022 2.590,0.960,0.030 2.595,0.935,0.080 2.415,0.850,0.233 2.400,0.835,0.260 2.220,0.535,0.313 2.115,0.335,0.318 2.090,0.255,0.310 2.090,0.185,0.273 2.140,0.060,0.184 2.160,0.035,0.140 2.195,0.015,0.092 2.300,0.020,0.050 2.405,0.065,0.036 2.510,0.145,0.032 2.695,0.330,0.032 2.775,0.335,0.155 2.790,0.320,0.180 2.890,0.315,0.340 2.935,0.495,0.298 2.955,0.530,0.279 3.060,0.430,0.045 3.100,0.435,0.036 3.275,0.485,0.051 3.380,0.530,0.081 3.545,0.635,0.158 3.630,0.730,0.228 3.670,0.820,0.250 3.620,0.920,0.140 3.570,0.975,0.060 3.535,0.985,0.040 3.445,0.985,0.030 3.390,0.970,0.040 3.320,0.935,0.071 3.200,0.850,0.139 3.035,0.675,0.246 2.965,0.565,0.285 2.960,0.530,0.269 2.945,0.520,0.291 2.935,0.495,0.298 2.895,0.330,0.330 2.895,0.295,0.330 2.930,0.175,0.291 2.960,0.120,0.269 2.995,0.080,0.212 3.055,0.040,0.150 3.135,0.020,0.108 3.300,0.025,0.060 3.445,0.065,0.041 3.635,0.180,0.041 3.755,0.280,0.042 3.790,0.290,0.071 3.805,0.290,0.092 3.900,0.200,0.286 3.960,0.275,0.316 4.070,0.455,0.273 4.095,0.480,0.238 4.120,0.580,0.282 4.280,0.835,0.255 4.295,0.850,0.230 4.530,0.960,0.030 4.365,0.885,0.160 4.280,0.835,0.255 4.115,0.570,0.283 4.095,0.475,0.234 4.115,0.455,0.184 4.190,0.455,0.045 4.210,0.435,0.010 4.235,0.435,0.050 4.400,0.635,0.045 4.575,0.810,0.042 4.670,0.885,0.042 4.770,0.935,0.060 4.825,0.945,0.082 4.890,0.945,0.117 4.920,0.935,0.140 4.955,0.895,0.209 5.000,0.785,0.293 4.985,0.710,0.309 4.965,0.660,0.318 4.915,0.585,0.322 4.790,0.430,0.338 4.715,0.320,0.336 4.680,0.225,0.320 4.735,0.065,0.177 4.760,0.030,0.130 4.790,0.015,0.098 4.830,0.010,0.076 4.945,0.035,0.045 5.090,0.135,0.041 5.305,0.355,0.036 5.565,0.685,0.032", 1.35),
    ("2.700,1.400,0.380 2.760,1.380,0.380", 0.08),
  ]

  static func vien(seed: UInt64 = 0) -> Handwriting {
    var rng = seed
    // A different hand each time after the first: waypoints drift by a hair, the pace by a breath.
    func next() -> CGFloat { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(Int64(bitPattern: rng >> 11) % 1000) / 1000 - 0.5 }
    func waypoints(_ data: String) -> [(CGPoint, CGFloat, TimeInterval)] {
      data.split(separator: " ").map { (triple: Substring) -> (CGPoint, CGFloat, TimeInterval) in
        let v = triple.split(separator: ",").compactMap { Double(String($0)) }
        let j = seed == 0 ? CGPoint.zero : CGPoint(x: next() * 0.04, y: next() * 0.04)
        return (CGPoint(x: v[0] + j.x, y: v[1] + j.y), v[2], .infinity)
      }
    }
    let pace = seed == 0 ? 1.0 : 0.9 + Double(seed % 5) * 0.05
    var strokes: [Stroke] = []
    var clock: TimeInterval = 0.15
    for (data, duration) in route {
      strokes.append(Stroke(trail: Pen.trail(through: waypoints(data)), start: clock, duration: duration * pace))
      clock += duration * pace + 0.14  // the pen lifts between strokes
    }
    return Handwriting(strokes: strokes)
  }
}
