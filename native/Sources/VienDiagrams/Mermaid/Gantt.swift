import CoreGraphics
import Foundation

public struct GanttDiagram: Sendable {
  public struct Task: Sendable {
    var name: String
    var id: String?
    var section: Int
    var start: Date
    var end: Date
    var done = false
    var active = false
    var crit = false
    var milestone = false
  }
  var title: String?
  var sections: [String] = []
  var tasks: [Task] = []
  var axisFormat: String?
}

enum GanttParser {
  static func parse(_ lines: [(Int, String)]) throws -> GanttDiagram {
    var d = GanttDiagram()
    var formatter = dateFormatter("YYYY-MM-DD")
    var unixSeconds = false, unixMillis = false
    var byID: [String: GanttDiagram.Task] = [:]
    for (n, raw) in lines.dropFirst() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      let lower = line.lowercased()
      if lower.hasPrefix("title ") { d.title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }
      if lower.hasPrefix("dateformat ") {
        let f = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
        unixSeconds = f == "X"
        unixMillis = f == "x"
        formatter = dateFormatter(f)
        continue
      }
      if lower.hasPrefix("axisformat ") { d.axisFormat = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces); continue }
      if lower.hasPrefix("section ") { d.sections.append(String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)); continue }
      if lower.hasPrefix("excludes ") || lower.hasPrefix("todaymarker ") || lower.hasPrefix("tickinterval ") || lower.hasPrefix("weekday ") || lower.hasPrefix("inclusiveenddates") || lower.hasPrefix("topaxis") || lower.hasPrefix("displaymode") { continue }
      guard let colon = line.firstIndex(of: ":") else { throw DiagramSyntaxError(line: n, message: "expected “task name : dates”") }
      let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
      var items = line[line.index(after: colon)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
      var task = GanttDiagram.Task(name: name, section: max(0, d.sections.count - 1), start: Date(), end: Date())
      while let first = items.first, ["done", "active", "crit", "milestone"].contains(first.lowercased()) {
        switch first.lowercased() {
        case "done": task.done = true
        case "active": task.active = true
        case "crit": task.crit = true
        default: task.milestone = true
        }
        items.removeFirst()
      }
      if items.count >= 3 { task.id = items.removeFirst() }
      func date(_ s: String) -> Date? {
        if unixSeconds, let v = Double(s) { return Date(timeIntervalSince1970: v) }
        if unixMillis, let v = Double(s) { return Date(timeIntervalSince1970: v / 1000) }
        return formatter.date(from: s)
      }
      func duration(_ s: String) -> TimeInterval? {
        let digits = s.prefix(while: { $0.isNumber || $0 == "." })
        guard let v = Double(digits) else { return nil }
        switch s.dropFirst(digits.count).lowercased() {
        case "", "d": return v * 86400
        case "w": return v * 7 * 86400
        case "h": return v * 3600
        case "m": return v * 60
        case "s": return v
        case "ms": return v / 1000
        default: return nil
        }
      }
      let previousEnd = d.tasks.last?.end ?? Date()
      var start: Date
      var endItem: String
      if items.count >= 2 {
        let s = items[0]
        if s.lowercased().hasPrefix("after ") {
          let ids = s.dropFirst(6).split(separator: " ").map(String.init)
          start = ids.compactMap { byID[$0]?.end }.max() ?? previousEnd
        } else if let dt = date(s) {
          start = dt
        } else {
          throw DiagramSyntaxError(line: n, message: "cannot read date “\(s)”")
        }
        endItem = items[1]
      } else if items.count == 1 {
        start = previousEnd
        endItem = items[0]
      } else {
        throw DiagramSyntaxError(line: n, message: "task needs a date or duration")
      }
      if endItem.lowercased().hasPrefix("until ") {
        let ids = endItem.dropFirst(6).split(separator: " ").map(String.init)
        task.end = ids.compactMap { byID[$0]?.start }.min() ?? start
      } else if let dt = date(endItem) {
        task.end = dt
      } else if let dur = duration(endItem) {
        task.end = start.addingTimeInterval(dur)
      } else {
        throw DiagramSyntaxError(line: n, message: "cannot read date or duration “\(endItem)”")
      }
      task.start = start
      if task.end < task.start { task.end = task.start }
      if let id = task.id { byID[id] = task }
      d.tasks.append(task)
    }
    if d.sections.isEmpty { d.sections = [""] }
    return d
  }

  /// Mermaid (moment.js) date format → DateFormatter pattern.
  static func dateFormatter(_ mermaid: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    var pattern = mermaid
    for (from, to) in [("YYYY", "yyyy"), ("YY", "yy"), ("DD", "dd"), ("D", "d"), ("HH", "HH"), ("mm", "mm"), ("ss", "ss"), ("SSS", "SSS"), ("A", "a")] {
      pattern = pattern.replacingOccurrences(of: from, with: to)
    }
    f.dateFormat = pattern
    return f
  }

  /// strftime-style axis format → DateFormatter pattern.
  static func axisFormatter(_ strftime: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    var pattern = ""
    var it = strftime.makeIterator()
    while let c = it.next() {
      if c != "%" { pattern += c.isLetter ? "'\(c)'" : String(c); continue }
      guard let k = it.next() else { break }
      switch k {
      case "Y": pattern += "yyyy"
      case "y": pattern += "yy"
      case "m": pattern += "MM"
      case "d": pattern += "dd"
      case "e": pattern += "d"
      case "b", "h": pattern += "MMM"
      case "B": pattern += "MMMM"
      case "a": pattern += "EEE"
      case "A": pattern += "EEEE"
      case "H": pattern += "HH"
      case "I": pattern += "hh"
      case "M": pattern += "mm"
      case "S": pattern += "ss"
      case "p": pattern += "a"
      case "j": pattern += "DDD"
      case "W", "U": pattern += "ww"
      default: pattern += String(k)
      }
    }
    f.dateFormat = pattern
    return f
  }
}

struct GanttRenderer {
  let diagram: GanttDiagram
  let theme: DiagramTheme
  private let margin: Double = 16
  private let rowHeight: Double = 26
  private let sectionHeight: Double = 22
  private let chartWidth: Double = 560
  private let axisHeight: Double = 26
  private var labelWidth: Double = 100
  private var span: (Date, Date)
  private var rows: [(y: Double, task: GanttDiagram.Task?, section: String?)] = []
  private var contentHeight: Double = 0

  init(diagram: GanttDiagram, theme: DiagramTheme) {
    self.diagram = diagram
    self.theme = theme
    let style = theme.style(theme.fontSize - 1)
    for t in diagram.tasks { labelWidth = max(labelWidth, TextMetrics.measure(t.name, style: style).width + 24) }
    labelWidth = min(labelWidth, 260)
    let starts = diagram.tasks.map(\.start), ends = diagram.tasks.map(\.end)
    var lo = starts.min() ?? Date(), hi = ends.max() ?? Date()
    if hi.timeIntervalSince(lo) < 3600 { hi = lo.addingTimeInterval(86400) }
    let pad = hi.timeIntervalSince(lo) * 0.04
    lo = lo.addingTimeInterval(-pad)
    hi = hi.addingTimeInterval(pad)
    span = (lo, hi)
    var y = margin + (diagram.title == nil ? 0 : 30)
    for (s, name) in diagram.sections.enumerated() {
      let tasks = diagram.tasks.filter { $0.section == s }
      if !name.isEmpty { rows.append((y, nil, name)); y += sectionHeight }
      for t in tasks { rows.append((y, t, nil)); y += rowHeight }
      y += 6
    }
    contentHeight = y
  }

  var size: CGSize { CGSize(width: margin * 2 + labelWidth + chartWidth, height: contentHeight + axisHeight + margin) }

  private func x(_ date: Date) -> Double {
    let total = span.1.timeIntervalSince(span.0)
    return margin + labelWidth + (total > 0 ? date.timeIntervalSince(span.0) / total : 0) * chartWidth
  }

  func draw<C: Canvas>(on canvas: inout C) {
    let x0 = margin + labelWidth
    if let t = diagram.title { canvas.text(t, at: CGPoint(x: 0, y: margin), width: size.width, align: .center, style: theme.style(theme.fontSize + 2, weight: .semibold)) }
    // Axis ticks and grid.
    let total = span.1.timeIntervalSince(span.0)
    let days = total / 86400
    let unit: (component: Calendar.Component, step: Int, format: String) =
      days <= 3 ? (.hour, 6, "HH:mm") : days <= 21 ? (.day, 1, "MM-dd") : days <= 120 ? (.day, 7, "MM-dd") : days <= 800 ? (.month, 1, "MMM yy") : (.year, 1, "yyyy")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let formatter = diagram.axisFormat.map(GanttParser.axisFormatter) ?? GanttParser.axisFormatter("")
    if diagram.axisFormat == nil { formatter.dateFormat = unit.format }
    var tick = cal.dateInterval(of: unit.component, for: span.0)?.start ?? span.0
    let grid = Stroke(color: theme.nodeStroke.withAlpha(0.25), width: 1)
    let axisY = contentHeight
    canvas.line(CGPoint(x: x0, y: axisY), CGPoint(x: x0 + chartWidth, y: axisY), stroke: Stroke(color: theme.edge, width: 1))
    // Collect the ticks first, then label only as many as fit without touching.
    var ticks: [Date] = []
    var guardCount = 0
    while tick <= span.1, guardCount < 400 {
      guardCount += 1
      if tick >= span.0 { ticks.append(tick) }
      tick = cal.date(byAdding: unit.component, value: unit.step, to: tick) ?? span.1.addingTimeInterval(1)
    }
    let tickStyle = theme.style(theme.fontSize - 3, color: theme.secondaryText)
    let tickLabelWidth = (ticks.prefix(8).map { TextMetrics.measure(formatter.string(from: $0), style: tickStyle).width }.max() ?? 40) + 10
    let spacing = ticks.count > 1 ? x(ticks[1]) - x(ticks[0]) : chartWidth
    let every = max(1, Int((tickLabelWidth / max(1, spacing)).rounded(.up)))
    for (i, t) in ticks.enumerated() {
      let tx = x(t)
      canvas.line(CGPoint(x: tx, y: margin + (diagram.title == nil ? 0 : 30)), CGPoint(x: tx, y: axisY), stroke: grid)
      if i % every == 0 {
        canvas.text(formatter.string(from: t), at: CGPoint(x: tx - 40, y: axisY + 6), width: 80, align: .center, style: tickStyle)
      }
    }
    // Rows.
    let labelStyle = theme.style(theme.fontSize - 1)
    for row in rows {
      if let section = row.section {
        canvas.text(section, at: CGPoint(x: margin, y: row.y + 3), width: labelWidth + chartWidth, align: .left, style: theme.style(theme.fontSize - 1, weight: .semibold, color: theme.secondaryText))
        continue
      }
      guard let t = row.task else { continue }
      canvas.text(t.name, at: CGPoint(x: margin, y: row.y + 5), width: labelWidth - 12, align: .left, style: labelStyle)
      let base = theme.palette[t.section % theme.palette.count]
      let fill = t.done ? theme.nodeStroke.withAlpha(0.35) : t.active ? theme.accent : base.withAlpha(0.85)
      let stroke: Stroke? = t.crit ? Stroke(color: DiagramColor(hex: 0xFF3B30), width: 1.5) : nil
      let barY = row.y + 4, barH = rowHeight - 8
      if t.milestone {
        let cx = x(t.start), cy = barY + barH / 2, r = barH / 2
        canvas.polygon([CGPoint(x: cx, y: cy - r), CGPoint(x: cx + r, y: cy), CGPoint(x: cx, y: cy + r), CGPoint(x: cx - r, y: cy)], fill: fill, stroke: stroke)
      } else {
        let a = x(t.start), b = max(x(t.end), a + 3)
        canvas.rect(CGRect(x: a, y: barY, width: b - a, height: barH), radius: 3, fill: fill, stroke: stroke)
      }
    }
  }
}
