/// Hand-written scanners for the grammar fragments CommonMark specifies with regular expressions:
/// raw HTML, link destinations/titles/labels, reference definitions, tables and autolinks.

enum HTMLScanner {
  private static let blockTags: [StaticString] = [
    "address", "article", "aside", "base", "basefont", "blockquote", "body", "caption", "center", "col", "colgroup",
    "dd", "details", "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "frame",
    "frameset", "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hr", "html", "iframe", "legend", "li", "link",
    "main", "menu", "menuitem", "nav", "noframes", "ol", "optgroup", "option", "p", "param", "search", "section",
    "summary", "table", "tbody", "td", "tfoot", "th", "thead", "title", "tr", "track", "ul",
  ]

  /// Returns the HTML block type (1...7) that starts at `i`, or nil.
  static func blockStart(_ b: [Byte], from i: Int, to end: Int, allowType7: Bool) -> Int? {
    guard i < end, b[i] == ASCII.lt else { return nil }
    let j = i + 1
    // Type 1: <script, <pre, <style, <textarea followed by space, tab, `>` or EOL.
    for tag in ["script", "pre", "style", "textarea"] as [StaticString] {
      if b.hasPrefixIgnoringCase(tag, at: j) {
        let k = j + tag.utf8CodeUnitCount
        if k >= end || b[k].isSpaceOrTab || b[k] == ASCII.gt { return 1 }
      }
    }
    if b.hasPrefix("<!--", at: i) { return 2 }
    if b.hasPrefix("<?", at: i) { return 3 }
    if b.hasPrefix("<![CDATA[", at: i) { return 5 }
    if j < end, b[j] == ASCII.bang, j + 1 < end, b[j + 1].isLetter { return 4 }
    // Type 6: block-level tag names.
    var k = j
    if k < end, b[k] == ASCII.slash { k += 1 }
    let nameStart = k
    while k < end, b[k].isAlphanumeric { k += 1 }
    if k > nameStart {
      let name = String(decoding: b[nameStart..<k], as: UTF8.self).lowercased()
      if blockTags.contains(where: { $0.description == name }) {
        if k >= end || b[k].isSpaceOrTab || b[k] == ASCII.gt || (b[k] == ASCII.slash && k + 1 < end && b[k + 1] == ASCII.gt) {
          return 6
        }
      }
    }
    // Type 7: a complete open or closing tag alone on the line (any tag but the type-1 names).
    guard allowType7 else { return nil }
    var tagEnd: Int? = nil
    if j < end, b[j] == ASCII.slash {
      tagEnd = scanClosingTag(b, from: i, to: end)
    } else {
      tagEnd = scanOpenTag(b, from: i, to: end, allowNewlines: false)
      if let e = tagEnd {
        let name = String(decoding: b[(i + 1)..<min(e, i + 9)], as: UTF8.self).lowercased()
        for tag in ["script", "pre", "style", "textarea"] where name.hasPrefix(tag) {
          let after = name.dropFirst(tag.count).first
          if after == nil || after == " " || after == "/" || after == ">" || after == "\t" { return nil }
        }
      }
    }
    guard var e = tagEnd else { return nil }
    while e < end, b[e].isSpaceOrTab { e += 1 }
    return e >= end ? 7 : nil
  }

  /// Whether the line `from..<to` satisfies the end condition of HTML block `type` (1...5).
  static func blockEnds(type: Int, _ b: [Byte], from: Int, to end: Int) -> Bool {
    var i = from
    while i < end {
      switch type {
      case 1:
        if b[i] == ASCII.lt, i + 1 < end, b[i + 1] == ASCII.slash {
          for tag in ["script>", "pre>", "style>", "textarea>"] as [StaticString] where b.hasPrefixIgnoringCase(tag, at: i + 2) {
            return true
          }
        }
      case 2: if b.hasPrefix("-->", at: i) { return true }
      case 3: if b.hasPrefix("?>", at: i) { return true }
      case 4: if b[i] == ASCII.gt { return true }
      case 5: if b.hasPrefix("]]>", at: i) { return true }
      default: return false
      }
      i += 1
    }
    return false
  }

  /// Scans an open tag `<name attr...>` starting at `i`; returns the index after `>`.
  static func scanOpenTag(_ b: [Byte], from i: Int, to end: Int, allowNewlines: Bool) -> Int? {
    guard i + 1 < end, b[i] == ASCII.lt, b[i + 1].isLetter else { return nil }
    var k = i + 2
    while k < end, b[k].isAlphanumeric || b[k] == ASCII.minus { k += 1 }
    // Attributes.
    while true {
      let wsStart = k
      k = skipWhitespace(b, k, end, allowNewlines: allowNewlines)
      if k < end, b[k] == ASCII.slash || b[k] == ASCII.gt { break }
      guard k > wsStart, k < end, b[k].isLetter || b[k] == ASCII.underscore || b[k] == ASCII.colon else { return nil }
      k += 1
      while k < end, b[k].isAlphanumeric || b[k] == ASCII.underscore || b[k] == ASCII.dot || b[k] == ASCII.colon || b[k] == ASCII.minus {
        k += 1
      }
      // Optional value.
      let beforeEq = k
      var m = skipWhitespace(b, k, end, allowNewlines: allowNewlines)
      if m < end, b[m] == ASCII.equals {
        m = skipWhitespace(b, m + 1, end, allowNewlines: allowNewlines)
        guard m < end else { return nil }
        let q = b[m]
        if q == ASCII.quote || q == ASCII.apostrophe {
          m += 1
          while m < end, b[m] != q { if !allowNewlines, b[m] == ASCII.newline { return nil }; m += 1 }
          guard m < end else { return nil }
          k = m + 1
        } else {
          let vs = m
          while m < end, !b[m].isASCIIWhitespace, b[m] != ASCII.quote, b[m] != ASCII.apostrophe, b[m] != ASCII.equals,
            b[m] != ASCII.lt, b[m] != ASCII.gt, b[m] != ASCII.backtick
          { m += 1 }
          guard m > vs else { return nil }
          k = m
        }
      } else {
        k = beforeEq
      }
    }
    if k < end, b[k] == ASCII.slash { k += 1 }
    guard k < end, b[k] == ASCII.gt else { return nil }
    return k + 1
  }

  static func scanClosingTag(_ b: [Byte], from i: Int, to end: Int) -> Int? {
    guard i + 2 < end, b[i] == ASCII.lt, b[i + 1] == ASCII.slash, b[i + 2].isLetter else { return nil }
    var k = i + 3
    while k < end, b[k].isAlphanumeric || b[k] == ASCII.minus { k += 1 }
    k = skipWhitespace(b, k, end, allowNewlines: true)
    guard k < end, b[k] == ASCII.gt else { return nil }
    return k + 1
  }

  /// Any inline raw HTML construct (§6.6): tags, comments, processing instructions, declarations, CDATA.
  static func scanInline(_ b: [Byte], from i: Int, to end: Int) -> Int? {
    guard i + 1 < end, b[i] == ASCII.lt else { return nil }
    let c = b[i + 1]
    if c.isLetter { return scanOpenTag(b, from: i, to: end, allowNewlines: true) }
    if c == ASCII.slash { return scanClosingTag(b, from: i, to: end) }
    if c == ASCII.question {
      var k = i + 2
      while k + 1 < end { if b[k] == ASCII.question, b[k + 1] == ASCII.gt { return k + 2 }; k += 1 }
      return nil
    }
    if c == ASCII.bang {
      if b.hasPrefix("<!--", at: i) {
        if b.hasPrefix("<!-->", at: i) { return i + 5 }
        if b.hasPrefix("<!--->", at: i) { return i + 6 }
        var k = i + 4
        while k + 2 < end { if b[k] == ASCII.minus, b[k + 1] == ASCII.minus, b[k + 2] == ASCII.gt { return k + 3 }; k += 1 }
        return nil
      }
      if b.hasPrefix("<![CDATA[", at: i) {
        var k = i + 9
        while k + 2 < end { if b[k] == ASCII.rbracket, b[k + 1] == ASCII.rbracket, b[k + 2] == ASCII.gt { return k + 3 }; k += 1 }
        return nil
      }
      if i + 2 < end, b[i + 2].isLetter {
        var k = i + 3
        while k < end { if b[k] == ASCII.gt { return k + 1 }; k += 1 }
      }
    }
    return nil
  }

  private static func skipWhitespace(_ b: [Byte], _ start: Int, _ end: Int, allowNewlines: Bool) -> Int {
    var k = start
    while k < end {
      let c = b[k]
      if c.isSpaceOrTab || (allowNewlines && (c == ASCII.newline || c == ASCII.cr)) { k += 1 } else { break }
    }
    return k
  }
}

/// Link destination / title / label scanners shared by inline links and reference definitions.
enum LinkScanner {
  /// Returns (end index, decoded destination) or nil.
  static func destination(_ b: [Byte], from i: Int, to end: Int) -> (Int, String)? {
    guard i <= end else { return nil }
    if i < end, b[i] == ASCII.lt {
      var k = i + 1
      while k < end {
        let c = b[k]
        if c == ASCII.backslash, k + 1 < end, b[k + 1].isASCIIPunctuation { k += 2; continue }
        if c == ASCII.newline || c == ASCII.cr || c == ASCII.lt { return nil }
        if c == ASCII.gt { return (k + 1, Text.unescapeAndDecode(b, (i + 1)..<k)) }
        k += 1
      }
      return nil
    }
    var k = i
    var depth = 0
    while k < end {
      let c = b[k]
      if c == ASCII.backslash, k + 1 < end, b[k + 1].isASCIIPunctuation { k += 2; continue }
      if c == ASCII.lparen { depth += 1; if depth > 32 { return nil } }
      else if c == ASCII.rparen { if depth == 0 { break }; depth -= 1 }
      else if c <= 0x20 || c == 0x7F { break }
      k += 1
    }
    if depth != 0 { return nil }
    if k == i, !(k < end && b[k] == ASCII.rparen) { return nil }
    return (k, Text.unescapeAndDecode(b, i..<k))
  }

  /// Returns (end index, decoded title) or nil.
  static func title(_ b: [Byte], from i: Int, to end: Int) -> (Int, String)? {
    guard i < end else { return nil }
    let open = b[i]
    let close: Byte
    switch open {
    case ASCII.quote: close = ASCII.quote
    case ASCII.apostrophe: close = ASCII.apostrophe
    case ASCII.lparen: close = ASCII.rparen
    default: return nil
    }
    var k = i + 1
    while k < end {
      let c = b[k]
      if c == ASCII.backslash, k + 1 < end, b[k + 1].isASCIIPunctuation { k += 2; continue }
      if c == close { return (k + 1, Text.unescapeAndDecode(b, (i + 1)..<k)) }
      if open == ASCII.lparen, c == ASCII.lparen { return nil }
      // A blank line ends the title.
      if c == ASCII.newline, k + 1 < end, b[k + 1] == ASCII.newline { return nil }
      k += 1
    }
    return nil
  }

  /// Scans `[label]` at `i`; returns the total length including brackets, or 0.
  static func label(_ b: [Byte], from i: Int, to end: Int) -> Int {
    guard i < end, b[i] == ASCII.lbracket else { return 0 }
    var k = i + 1
    var length = 0
    while k < end {
      let c = b[k]
      if c == ASCII.backslash, k + 1 < end, b[k + 1].isASCIIPunctuation { k += 2; length += 2 }
      else if c == ASCII.lbracket { return 0 }
      else if c == ASCII.rbracket { return length <= 999 ? k + 1 - i : 0 }
      else { k += 1; length += 1 }
      if length > 999 { return 0 }
    }
    return 0
  }

  /// Skips spaces/tabs, at most one line ending, then spaces/tabs.
  static func spnl(_ b: [Byte], _ i: Int, _ end: Int) -> Int {
    var k = i
    while k < end, b[k].isSpaceOrTab { k += 1 }
    if k < end, b[k] == ASCII.newline || b[k] == ASCII.cr {
      k += 1
      if k < end, b[k - 1] == ASCII.cr, b[k] == ASCII.newline { k += 1 }
      while k < end, b[k].isSpaceOrTab { k += 1 }
    }
    return k
  }
}

/// Link reference definitions at the start of a paragraph (§4.7).
enum ReferenceScanner {
  struct Result {
    var label: String
    var reference: LinkReference
    var linesConsumed: Int
  }

  static func scan(_ bytes: [Byte], lines: [ContentLine]) -> Result? {
    // Build the virtual paragraph text (lines joined with LF) and remember line boundaries.
    var buf: [Byte] = []
    var lineEnds: [Int] = []
    for (n, line) in lines.enumerated() {
      if n > 0 { buf.append(ASCII.newline) }
      if line.virtualSpaces > 0 { buf.append(contentsOf: repeatElement(ASCII.space, count: line.virtualSpaces)) }
      buf.append(contentsOf: bytes[line.range])
      lineEnds.append(buf.count)
    }
    let end = buf.count
    let labelLen = LinkScanner.label(buf, from: 0, to: end)
    guard labelLen > 0 else { return nil }
    var pos = labelLen
    guard pos < end, buf[pos] == ASCII.colon else { return nil }
    pos += 1
    pos = LinkScanner.spnl(buf, pos, end)
    guard let (afterDest, dest) = LinkScanner.destination(buf, from: pos, to: end) else { return nil }
    pos = afterDest
    let beforeTitle = pos
    pos = LinkScanner.spnl(buf, pos, end)
    var title: String? = nil
    if pos != beforeTitle, let (afterTitle, t) = LinkScanner.title(buf, from: pos, to: end) {
      title = t
      pos = afterTitle
    } else {
      pos = beforeTitle
    }
    // Must be at end of line.
    func atLineEnd(_ p: Int) -> Int? {
      var k = p
      while k < end, buf[k].isSpaceOrTab { k += 1 }
      if k >= end { return k }
      if buf[k] == ASCII.newline { return k }
      return nil
    }
    var lineEnd = atLineEnd(pos)
    if lineEnd == nil, title != nil {
      title = nil
      pos = beforeTitle
      lineEnd = atLineEnd(pos)
    }
    guard let stop = lineEnd else { return nil }
    let raw = String(decoding: buf[1..<(labelLen - 1)], as: UTF8.self)
    let label = Text.normalizeLabel(raw)
    guard !label.isEmpty else { return nil }
    let consumed = lineEnds.firstIndex(where: { $0 >= stop }).map { $0 + 1 } ?? lines.count
    return Result(label: label, reference: LinkReference(destination: dest, title: title), linesConsumed: consumed)
  }
}

enum TableScanner {
  /// Parses a GFM delimiter row; returns the alignments or nil.
  static func delimiterRow(_ b: [Byte], from i: Int, to end: Int) -> [TableAlignment]? {
    var k = i
    var alignments: [TableAlignment] = []
    var sawPipe = false
    while k < end, b[k].isSpaceOrTab { k += 1 }
    if k < end, b[k] == ASCII.pipe { k += 1; sawPipe = true }
    while true {
      while k < end, b[k].isSpaceOrTab { k += 1 }
      if k >= end { break }
      var left = false, right = false
      if b[k] == ASCII.colon { left = true; k += 1 }
      var dashes = 0
      while k < end, b[k] == ASCII.minus { dashes += 1; k += 1 }
      guard dashes > 0 else { return nil }
      if k < end, b[k] == ASCII.colon { right = true; k += 1 }
      alignments.append(left && right ? .center : left ? .left : right ? .right : .none)
      while k < end, b[k].isSpaceOrTab { k += 1 }
      if k < end {
        guard b[k] == ASCII.pipe else { return nil }
        sawPipe = true
        k += 1
      }
    }
    guard !alignments.isEmpty, sawPipe else { return nil }
    return alignments
  }

  /// Splits a row into cells. Each cell is a list of source segments (split around escaped pipes).
  static func splitCells(_ b: [Byte], _ range: Range<Int>) -> [[Range<Int>]] {
    var start = range.lowerBound
    var end = range.upperBound
    while start < end, b[start].isSpaceOrTab { start += 1 }
    while end > start, b[end - 1].isSpaceOrTab { end -= 1 }
    if start < end, b[start] == ASCII.pipe { start += 1 }
    if end > start, b[end - 1] == ASCII.pipe, !(end - 2 >= start && b[end - 2] == ASCII.backslash) { end -= 1 }
    var cells: [[Range<Int>]] = []
    var segments: [Range<Int>] = []
    var segStart = start
    var k = start
    while k < end {
      let c = b[k]
      if c == ASCII.backslash, k + 1 < end, b[k + 1] == ASCII.pipe {
        segments.append(segStart..<k)
        segStart = k + 1
        k += 2
        continue
      }
      if c == ASCII.pipe {
        segments.append(segStart..<k)
        cells.append(trim(b, segments))
        segments = []
        k += 1
        segStart = k
        continue
      }
      k += 1
    }
    segments.append(segStart..<end)
    cells.append(trim(b, segments))
    return cells
  }

  private static func trim(_ b: [Byte], _ segments: [Range<Int>]) -> [Range<Int>] {
    let original = segments
    var segs = segments
    while let first = segs.first {
      var s = first.lowerBound
      while s < first.upperBound, b[s].isSpaceOrTab { s += 1 }
      if s == first.upperBound { segs.removeFirst(); continue }
      segs[0] = s..<first.upperBound
      break
    }
    while let last = segs.last {
      var e = last.upperBound
      while e > last.lowerBound, b[e - 1].isSpaceOrTab { e -= 1 }
      if e == last.lowerBound { segs.removeLast(); continue }
      segs[segs.count - 1] = last.lowerBound..<e
      break
    }
    // An empty cell keeps a zero-length range where its content would start, so the caret can be
    // put into it (between the pipes) rather than at the row start.
    if segs.isEmpty, let first = original.first {
      // After the single padding space, so typing there gives `| x |`.
      var p = first.lowerBound
      if p < first.upperBound, b[p].isSpaceOrTab { p += 1 }
      return [p..<p]
    }
    return segs
  }
}

enum AutolinkScanner {
  /// `<scheme:...>` or `<email>`; returns (end index, url, isEmail).
  static func angle(_ b: [Byte], from i: Int, to end: Int) -> (Int, String, Bool)? {
    guard i + 1 < end, b[i] == ASCII.lt else { return nil }
    // URI autolink: scheme (2-32 chars) ':' then no spaces, <, >
    var k = i + 1
    if k < end, b[k].isLetter {
      var s = k + 1
      while s < end, b[s].isAlphanumeric || b[s] == ASCII.plus || b[s] == ASCII.dot || b[s] == ASCII.minus { s += 1 }
      let schemeLen = s - k
      if schemeLen >= 2, schemeLen <= 32, s < end, b[s] == ASCII.colon {
        var m = s + 1
        while m < end, b[m] > 0x20, b[m] != ASCII.lt, b[m] != ASCII.gt, b[m] != 0x7F { m += 1 }
        if m < end, b[m] == ASCII.gt { return (m + 1, Text.string(b, k..<m), false) }
      }
    }
    // Email autolink.
    k = i + 1
    let local = k
    while k < end, isEmailLocal(b[k]) { k += 1 }
    guard k > local, k < end, b[k] == ASCII.at else { return nil }
    k += 1
    guard let d = domainEnd(b, from: k, to: end, allowUnderscore: false), d < end, b[d] == ASCII.gt else { return nil }
    return (d + 1, Text.string(b, (i + 1)..<d), true)
  }

  private static func isEmailLocal(_ c: Byte) -> Bool {
    if c.isAlphanumeric { return true }
    switch c {
    case 0x2E, 0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2F, 0x3D, 0x3F, 0x5E, 0x5F, 0x60, 0x7B, 0x7C, 0x7D, 0x7E, 0x2D:
      return true
    default: return false
    }
  }

  /// Email domain: labels of alphanumerics/hyphens (≤63, not starting/ending with `-`), separated by dots.
  private static func domainEnd(_ b: [Byte], from i: Int, to end: Int, allowUnderscore: Bool) -> Int? {
    var k = i
    while true {
      let ls = k
      guard k < end, b[k].isAlphanumeric || (allowUnderscore && b[k] == ASCII.underscore) else { return nil }
      while k < end, b[k].isAlphanumeric || b[k] == ASCII.minus || (allowUnderscore && b[k] == ASCII.underscore) { k += 1 }
      if k - ls > 63 || b[k - 1] == ASCII.minus { return nil }
      if k < end, b[k] == ASCII.dot { k += 1; continue }
      return k
    }
  }

  struct Extended { var range: Range<Int>; var url: String; var isEmail: Bool }

  /// GFM extended autolinks inside plain text `range` (www., http(s)://, email).
  static func extended(_ b: [Byte], in range: Range<Int>) -> [Extended] {
    var out: [Extended] = []
    var i = range.lowerBound
    let end = range.upperBound
    while i < end {
      let c = b[i]
      if c == 0x77 || c == 0x68 || c == 0x57 || c == 0x48 {  // w h
        let precededOK = i == 0 || {
          let p = b[i - 1]
          return p.isASCIIWhitespace || p == ASCII.star || p == ASCII.underscore || p == ASCII.tilde || p == ASCII.lparen
        }()
        if precededOK {
          if b.hasPrefixIgnoringCase("www.", at: i), i + 4 < end, let e = validDomain(b, from: i + 4, to: end) {
            let stop = trimTrailing(b, from: pathEnd(b, from: e, to: end), start: i)
            out.append(Extended(range: i..<stop, url: "http://" + Text.string(b, i..<stop), isEmail: false))
            i = stop; continue
          }
          for scheme in ["http://", "https://"] as [StaticString] where b.hasPrefixIgnoringCase(scheme, at: i) {
            let ds = i + scheme.utf8CodeUnitCount
            if let e = validDomain(b, from: ds, to: end) {
              let stop = trimTrailing(b, from: pathEnd(b, from: e, to: end), start: i)
              out.append(Extended(range: i..<stop, url: Text.string(b, i..<stop), isEmail: false))
              i = stop
              break
            }
          }
          if i >= end || b[i] != c { continue }
        }
      }
      if c == ASCII.at, i > range.lowerBound {
        // Email: scan backwards for the local part.
        var s = i
        while s > range.lowerBound, b[s - 1].isAlphanumeric || b[s - 1] == ASCII.dot || b[s - 1] == ASCII.plus
          || b[s - 1] == ASCII.underscore || b[s - 1] == ASCII.minus
        { s -= 1 }
        if s < i, !out.contains(where: { $0.range.upperBound > s }) {
          var k = i + 1
          let ds = k
          var dots = 0
          while k < end, b[k].isAlphanumeric || b[k] == ASCII.minus || b[k] == ASCII.underscore || b[k] == ASCII.dot {
            if b[k] == ASCII.dot { dots += 1 }
            k += 1
          }
          // Trailing dot is not part of the address; last char must not be - or _.
          while k > ds, b[k - 1] == ASCII.dot { k -= 1; dots -= 1 }
          if k > ds, dots >= 1, b[k - 1] != ASCII.minus, b[k - 1] != ASCII.underscore {
            // `mailto:` / `xmpp:` prefixes become part of the link; xmpp may carry a `/resource`.
            var start = s
            var scheme = ""
            if s >= 7, b.hasPrefixIgnoringCase("mailto:", at: s - 7) { start = s - 7; scheme = "mailto:" }
            else if s >= 5, b.hasPrefixIgnoringCase("xmpp:", at: s - 5) { start = s - 5; scheme = "xmpp:" }
            if scheme == "xmpp:", k < end, b[k] == ASCII.slash {
              var r = k + 1
              while r < end, b[r].isAlphanumeric || b[r] == ASCII.at || b[r] == ASCII.dot { r += 1 }
              if r > k + 1 { k = r }
            }
            let text = Text.string(b, start..<k)
            out.append(Extended(range: start..<k, url: scheme.isEmpty ? "mailto:" + text : text, isEmail: true))
            i = k
            continue
          }
        }
      }
      i += 1
    }
    return out
  }

  /// A valid GFM domain: alphanumeric/`_`/`-` segments separated by dots, at least one dot, and no
  /// underscores in the last two segments.
  private static func validDomain(_ b: [Byte], from i: Int, to end: Int) -> Int? {
    var k = i
    var segments: [(Int, Int)] = []
    while true {
      let s = k
      while k < end, b[k].isAlphanumeric || b[k] == ASCII.underscore || b[k] == ASCII.minus { k += 1 }
      if k == s { break }
      segments.append((s, k))
      if k < end, b[k] == ASCII.dot { k += 1; continue }
      break
    }
    // A trailing dot is not part of the domain.
    if k > i, b[k - 1] == ASCII.dot { k -= 1 }
    guard segments.count >= 2 else { return nil }
    for (s, e) in segments.suffix(2) { for j in s..<e where b[j] == ASCII.underscore { return nil } }
    return k
  }

  private static func pathEnd(_ b: [Byte], from i: Int, to end: Int) -> Int {
    var k = i
    while k < end, !b[k].isASCIIWhitespace, b[k] != ASCII.lt { k += 1 }
    return k
  }

  private static func trimTrailing(_ b: [Byte], from e: Int, start: Int) -> Int {
    var k = e
    while k > start {
      let c = b[k - 1]
      if c == ASCII.question || c == ASCII.bang || c == ASCII.dot || c == 0x2C || c == ASCII.colon || c == ASCII.star
        || c == ASCII.underscore || c == ASCII.tilde || c == ASCII.apostrophe || c == ASCII.quote
      {
        k -= 1
      } else if c == ASCII.rparen {
        var open = 0, close = 0
        for j in start..<k { if b[j] == ASCII.lparen { open += 1 } else if b[j] == ASCII.rparen { close += 1 } }
        if close > open { k -= 1 } else { break }
      } else if c == ASCII.semicolon {
        // `&entity;` at the end is excluded together with the semicolon.
        var j = k - 1
        while j > start, b[j - 1].isAlphanumeric { j -= 1 }
        if j > start, b[j - 1] == ASCII.amp { k = j - 1 } else { k -= 1 }
      } else {
        break
      }
    }
    return k
  }
}
