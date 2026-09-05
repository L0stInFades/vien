/// Phase-two inline parser: a port of the CommonMark reference delimiter-stack algorithm with the
/// GFM (strikethrough, autolinks) and Vien (math, emoji, footnotes, super/subscript) extensions.
///
/// The parser runs on a "virtual" buffer — the block's content lines joined by newlines with
/// container prefixes stripped — and maps every node back to source byte offsets.

/// Content of one leaf block assembled for inline parsing.
struct InlineInput {
  private(set) var buf: [Byte] = []
  private var segments: [Segment] = []

  private struct Segment {
    var vstart: Int
    var vend: Int
    var sstart: Int
    var zeroWidth: Bool
  }

  /// `joiner` is LF for normal blocks and nil for table cells (whose segments abut directly).
  init(bytes: [Byte], lines: [ContentLine], joiner: Byte?) {
    var total = 0
    for l in lines { total += l.range.count + l.virtualSpaces + 1 }
    buf.reserveCapacity(total)
    segments.reserveCapacity(lines.count * 2)
    for (n, line) in lines.enumerated() {
      if n > 0, let j = joiner {
        let prev = segments.last
        segments.append(Segment(vstart: buf.count, vend: buf.count + 1, sstart: prev?.sstart ?? line.range.lowerBound, zeroWidth: true))
        if let prev { segments[segments.count - 1].sstart = prev.sstart + (prev.zeroWidth ? 0 : prev.vend - prev.vstart) }
        buf.append(j)
      }
      if line.virtualSpaces > 0 {
        segments.append(Segment(vstart: buf.count, vend: buf.count + line.virtualSpaces, sstart: max(0, line.range.lowerBound - 1), zeroWidth: true))
        buf.append(contentsOf: repeatElement(ASCII.space, count: line.virtualSpaces))
      }
      segments.append(Segment(vstart: buf.count, vend: buf.count + line.range.count, sstart: line.range.lowerBound, zeroWidth: false))
      buf.append(contentsOf: bytes[line.range])
    }
  }

  /// Virtual offset → source offset.
  func source(_ v: Int) -> Int {
    guard !segments.isEmpty else { return 0 }
    var lo = 0, hi = segments.count - 1
    while lo < hi {
      let mid = (lo + hi + 1) >> 1
      if segments[mid].vstart <= v { lo = mid } else { hi = mid - 1 }
    }
    let s = segments[lo]
    if s.zeroWidth { return s.sstart }
    return s.sstart + min(v - s.vstart, s.vend - s.vstart)
  }

  func sourceRange(_ v: Range<Int>) -> Range<Int> {
    let a = source(v.lowerBound)
    let b = v.upperBound > v.lowerBound ? source(v.upperBound - 1) + 1 : a
    return a..<max(a, b)
  }
}

/// Mutable inline node used while parsing; converted to `Inline` at the end.
private final class INode {
  var kind: InlineKind
  var vrange: Range<Int>
  var literal: [Byte]  // for text nodes
  var parent: INode?
  var prev: INode?
  var next: INode?
  var firstChild: INode?
  var lastChild: INode?

  init(kind: InlineKind, vrange: Range<Int>, literal: [Byte] = []) {
    self.kind = kind
    self.vrange = vrange
    self.literal = literal
  }

  var isText: Bool { if case .text = kind { return true }; return false }

  func append(_ child: INode) {
    child.unlink()
    child.parent = self
    if let last = lastChild {
      last.next = child
      child.prev = last
      lastChild = child
    } else {
      firstChild = child
      lastChild = child
    }
  }

  func insertAfter(_ sibling: INode) {
    sibling.unlink()
    sibling.next = next
    if let n = next { n.prev = sibling }
    sibling.prev = self
    next = sibling
    sibling.parent = parent
    if let p = parent, p.lastChild === self { p.lastChild = sibling }
  }

  func unlink() {
    if let p = prev { p.next = next } else if let par = parent { par.firstChild = next }
    if let n = next { n.prev = prev } else if let par = parent { par.lastChild = prev }
    parent = nil
    next = nil
    prev = nil
  }
}

private final class Delimiter {
  let cc: Byte
  var numdelims: Int
  let origdelims: Int
  let node: INode
  var previous: Delimiter?
  var next: Delimiter?
  let canOpen: Bool
  let canClose: Bool

  init(cc: Byte, numdelims: Int, node: INode, previous: Delimiter?, canOpen: Bool, canClose: Bool) {
    self.cc = cc
    self.numdelims = numdelims
    self.origdelims = numdelims
    self.node = node
    self.previous = previous
    self.canOpen = canOpen
    self.canClose = canClose
  }
}

private final class Bracket {
  let node: INode
  let previous: Bracket?
  let previousDelimiter: Delimiter?
  let index: Int
  let image: Bool
  var active = true
  var bracketAfter = false

  init(node: INode, previous: Bracket?, previousDelimiter: Delimiter?, index: Int, image: Bool) {
    self.node = node
    self.previous = previous
    self.previousDelimiter = previousDelimiter
    self.index = index
    self.image = image
  }
}

struct InlineParser {
  private let input: InlineInput
  private let buf: [Byte]
  private let start: Int
  private let end: Int
  private let references: [String: LinkReference]
  private let footnotes: Set<String>
  private let options: ParserOptions
  private var pos: Int
  private var delimiters: Delimiter? = nil
  private var brackets: Bracket? = nil

  init(input: InlineInput, references: [String: LinkReference], footnotes: Set<String>, options: ParserOptions) {
    self.input = input
    buf = input.buf
    // Trim leading/trailing whitespace of the whole content.
    var s = 0, e = buf.count
    while s < e, buf[s].isASCIIWhitespace { s += 1 }
    while e > s, buf[e - 1].isASCIIWhitespace { e -= 1 }
    start = s
    end = e
    pos = s
    self.references = references
    self.footnotes = footnotes
    self.options = options
  }

  mutating func parse() -> [Inline] {
    let root = INode(kind: .text(""), vrange: start..<end)
    while pos < end { parseInline(into: root) }
    processEmphasis(stackBottom: nil)
    if options.autolinks { mergePlainText(root); linkifyText(root) }
    return convert(root)
  }

  // MARK: - Dispatch

  @inline(__always) private func peek() -> Byte? { pos < end ? buf[pos] : nil }

  private mutating func parseInline(into block: INode) {
    guard let c = peek() else { return }
    switch c {
    case ASCII.newline: parseNewline(block)
    case ASCII.backslash: parseBackslash(block)
    case ASCII.backtick: parseBackticks(block)
    case ASCII.star, ASCII.underscore: handleDelim(c, block)
    case ASCII.tilde where options.strikethrough || options.superSubScript: handleDelim(c, block)
    case ASCII.lbracket: parseOpenBracket(block)
    case ASCII.bang: parseBang(block)
    case ASCII.rbracket: parseCloseBracket(block)
    case ASCII.lt:
      if !parseAutolink(block) && !parseHTMLTag(block) { appendText(block, pos..<(pos + 1)); pos += 1 }
    case ASCII.amp: parseEntity(block)
    case ASCII.dollar where options.math:
      if !parseMath(block) { appendText(block, pos..<(pos + 1)); pos += 1 }
    case ASCII.colon where options.emoji:
      if !parseEmoji(block) { appendText(block, pos..<(pos + 1)); pos += 1 }
    case ASCII.caret where options.superSubScript:
      if !parseSuperscript(block) { appendText(block, pos..<(pos + 1)); pos += 1 }
    default: parseString(block)
    }
  }

  private func text(_ vrange: Range<Int>, literal: [Byte]) -> INode {
    INode(kind: .text(""), vrange: vrange, literal: literal)
  }

  private func appendText(_ block: INode, _ vrange: Range<Int>) {
    block.append(text(vrange, literal: Array(buf[vrange])))
  }

  private mutating func parseString(_ block: INode) {
    let s = pos
    var p = pos
    while p < end, !isSpecial(buf[p]) { p += 1 }
    if p == s { p += 1 }
    pos = p
    appendText(block, s..<p)
  }

  @inline(__always) private func isSpecial(_ c: Byte) -> Bool {
    switch c {
    case ASCII.newline, ASCII.backtick, ASCII.lbracket, ASCII.rbracket, ASCII.backslash, ASCII.bang, ASCII.lt, ASCII.amp,
      ASCII.star, ASCII.underscore:
      return true
    case ASCII.tilde: return options.strikethrough || options.superSubScript
    case ASCII.dollar: return options.math
    case ASCII.colon: return options.emoji
    case ASCII.caret: return options.superSubScript
    default: return false
    }
  }

  private mutating func parseNewline(_ block: INode) {
    let nl = pos
    pos += 1
    var hard = false
    if let last = block.lastChild, last.isText, last.literal.last == ASCII.space {
      hard = last.literal.count >= 2 && last.literal[last.literal.count - 2] == ASCII.space
      var trimmed = 0
      while last.literal.last == ASCII.space { last.literal.removeLast(); trimmed += 1 }
      last.vrange = last.vrange.lowerBound..<(last.vrange.upperBound - trimmed)
      if last.literal.isEmpty { last.unlink() }
    }
    block.append(INode(kind: hard ? .hardBreak : .softBreak, vrange: nl..<pos))
    while pos < end, buf[pos] == ASCII.space { pos += 1 }
  }

  private mutating func parseBackslash(_ block: INode) {
    let s = pos
    pos += 1
    if pos < end, buf[pos] == ASCII.newline {
      pos += 1
      block.append(INode(kind: .hardBreak, vrange: s..<pos))
      while pos < end, buf[pos] == ASCII.space { pos += 1 }
    } else if pos < end, buf[pos].isASCIIPunctuation {
      block.append(text(s..<(pos + 1), literal: [buf[pos]]))
      pos += 1
    } else {
      block.append(text(s..<pos, literal: [ASCII.backslash]))
    }
  }

  private mutating func parseBackticks(_ block: INode) {
    let s = pos
    var p = pos
    while p < end, buf[p] == ASCII.backtick { p += 1 }
    let n = p - s
    var q = p
    while q < end {
      if buf[q] == ASCII.backtick {
        var r = q
        while r < end, buf[r] == ASCII.backtick { r += 1 }
        if r - q == n {
          // Found the closer: normalise content.
          var content = Array(buf[p..<q])
          for i in content.indices where content[i] == ASCII.newline { content[i] = ASCII.space }
          if content.count >= 2, content.first == ASCII.space, content.last == ASCII.space, content.contains(where: { $0 != ASCII.space }) {
            content.removeFirst()
            content.removeLast()
          }
          pos = r
          block.append(INode(kind: .code(String(decoding: content, as: UTF8.self), fence: n), vrange: s..<r))
          return
        }
        q = r
      } else {
        q += 1
      }
    }
    pos = p
    appendText(block, s..<p)
  }

  // MARK: - Emphasis

  private struct DelimRun {
    var count: Int
    var canOpen: Bool
    var canClose: Bool
  }

  private func scanDelims(_ cc: Byte) -> DelimRun? {
    let s = pos
    var p = pos
    while p < end, buf[p] == cc { p += 1 }
    let count = p - s
    guard count > 0 else { return nil }
    let before = buf.scalar(before: s) ?? "\n"
    let after = p < end ? (buf.scalar(at: p)?.0 ?? "\n") : "\n"
    let afterWS = after.isMarkdownWhitespace, afterPunct = after.isMarkdownPunctuation
    let beforeWS = before.isMarkdownWhitespace, beforePunct = before.isMarkdownPunctuation
    let leftFlanking = !afterWS && (!afterPunct || beforeWS || beforePunct)
    let rightFlanking = !beforeWS && (!beforePunct || afterWS || afterPunct)
    var canOpen: Bool, canClose: Bool
    if cc == ASCII.underscore {
      canOpen = leftFlanking && (!rightFlanking || beforePunct)
      canClose = rightFlanking && (!leftFlanking || afterPunct)
    } else {
      canOpen = leftFlanking
      canClose = rightFlanking
    }
    if cc == ASCII.tilde, count > 2 { canOpen = false; canClose = false }
    return DelimRun(count: count, canOpen: canOpen, canClose: canClose)
  }

  private mutating func handleDelim(_ cc: Byte, _ block: INode) {
    guard let run = scanDelims(cc) else { return }
    let s = pos
    pos += run.count
    let node = text(s..<pos, literal: Array(buf[s..<pos]))
    block.append(node)
    if run.canOpen || run.canClose {
      let d = Delimiter(cc: cc, numdelims: run.count, node: node, previous: delimiters, canOpen: run.canOpen, canClose: run.canClose)
      delimiters?.next = d
      delimiters = d
    }
  }

  private mutating func removeDelimiter(_ d: Delimiter) {
    d.previous?.next = d.next
    if let n = d.next { n.previous = d.previous } else { delimiters = d.previous }
  }

  private func removeDelimitersBetween(_ bottom: Delimiter, _ top: Delimiter) {
    if bottom.next !== top {
      bottom.next = top
      top.previous = bottom
    }
  }

  private mutating func processEmphasis(stackBottom: Delimiter?) {
    // openersBottom[cc][(canOpen ? 3 : 0) + origdelims % 3]
    var openersBottom: [Byte: [Delimiter?]] = [:]
    func bottom(_ cc: Byte, _ idx: Int) -> Delimiter? { openersBottom[cc]?[idx] ?? stackBottom }
    var closer: Delimiter? = stackBottom == nil ? firstDelimiter() : stackBottom?.next

    while let c = closer {
      guard c.canClose else { closer = c.next; continue }
      let cc = c.cc
      let idx = (c.canOpen ? 3 : 0) + c.origdelims % 3
      var opener = c.previous
      var found = false
      let limit = bottom(cc, idx)
      while let o = opener, o !== stackBottom, o !== limit {
        let oddMatch = (c.canOpen || o.canClose) && c.origdelims % 3 != 0 && (o.origdelims + c.origdelims) % 3 == 0
        if o.cc == cc, o.canOpen, !oddMatch, !(cc == ASCII.tilde && o.origdelims != c.origdelims) {
          found = true
          break
        }
        opener = o.previous
      }
      let oldCloser = c
      if found, let o = opener {
        let use: Int
        if cc == ASCII.tilde { use = c.numdelims } else { use = (c.numdelims >= 2 && o.numdelims >= 2) ? 2 : 1 }
        let oi = o.node, ci = c.node
        o.numdelims -= use
        c.numdelims -= use
        oi.literal.removeLast(use)
        oi.vrange = oi.vrange.lowerBound..<(oi.vrange.upperBound - use)
        ci.literal.removeFirst(use)
        ci.vrange = (ci.vrange.lowerBound + use)..<ci.vrange.upperBound
        let kind: InlineKind
        if cc == ASCII.tilde {
          kind = (options.superSubScript && use == 1) ? .subscript : .strikethrough(length: use)
        } else {
          kind = use == 1 ? .emphasis(delimiter: cc) : .strong(delimiter: cc)
        }
        let emph = INode(kind: kind, vrange: oi.vrange.upperBound..<ci.vrange.lowerBound)
        var tmp = oi.next
        while let t = tmp, t !== ci {
          let n = t.next
          emph.append(t)
          tmp = n
        }
        oi.insertAfter(emph)
        removeDelimitersBetween(o, c)
        if o.numdelims == 0 { oi.unlink(); removeDelimiter(o) }
        if c.numdelims == 0 {
          ci.unlink()
          let next = c.next
          removeDelimiter(c)
          closer = next
        } else {
          closer = c
        }
      } else {
        closer = c.next
      }
      if !found {
        var arr = openersBottom[cc] ?? Array(repeating: stackBottom, count: 6)
        arr[idx] = oldCloser.previous
        openersBottom[cc] = arr
        if !oldCloser.canOpen { removeDelimiter(oldCloser) }
      }
    }
    while let d = delimiters, d !== stackBottom { removeDelimiter(d) }
  }

  private func firstDelimiter() -> Delimiter? {
    var d = delimiters
    while let p = d?.previous { d = p }
    return d
  }

  // MARK: - Links

  private mutating func addBracket(_ node: INode, index: Int, image: Bool) {
    brackets?.bracketAfter = true
    brackets = Bracket(node: node, previous: brackets, previousDelimiter: delimiters, index: index, image: image)
  }

  private mutating func removeBracket() { brackets = brackets?.previous }

  private mutating func parseOpenBracket(_ block: INode) {
    let s = pos
    // Footnote reference `[^label]`.
    if options.footnotes, s + 2 < end, buf[s + 1] == ASCII.caret {
      var k = s + 2
      while k < end, buf[k] != ASCII.rbracket, !buf[k].isASCIIWhitespace, buf[k] != ASCII.lbracket, buf[k] != ASCII.caret { k += 1 }
      if k < end, buf[k] == ASCII.rbracket, k > s + 2 {
        let label = String(decoding: buf[(s + 2)..<k], as: UTF8.self)
        if footnotes.contains(label) {
          pos = k + 1
          block.append(INode(kind: .footnoteReference(label), vrange: s..<pos))
          return
        }
      }
    }
    pos += 1
    let node = text(s..<pos, literal: [ASCII.lbracket])
    block.append(node)
    addBracket(node, index: s, image: false)
  }

  private mutating func parseBang(_ block: INode) {
    let s = pos
    pos += 1
    if pos < end, buf[pos] == ASCII.lbracket {
      pos += 1
      let node = text(s..<pos, literal: [ASCII.bang, ASCII.lbracket])
      block.append(node)
      addBracket(node, index: s + 1, image: true)
    } else {
      block.append(text(s..<pos, literal: [ASCII.bang]))
    }
  }

  private mutating func parseCloseBracket(_ block: INode) {
    pos += 1
    let startpos = pos
    guard let opener = brackets else {
      block.append(text((pos - 1)..<pos, literal: [ASCII.rbracket]))
      return
    }
    guard opener.active else {
      block.append(text((pos - 1)..<pos, literal: [ASCII.rbracket]))
      removeBracket()
      return
    }
    let isImage = opener.image
    let savepos = pos
    var matched = false
    var dest = ""
    var title: String? = nil

    if pos < end, buf[pos] == ASCII.lparen {
      pos += 1
      pos = LinkScanner.spnl(buf, pos, end)
      if let (afterDest, d) = LinkScanner.destination(buf, from: pos, to: end) {
        pos = afterDest
        let beforeTitle = pos
        pos = LinkScanner.spnl(buf, pos, end)
        var ok = true
        if pos > beforeTitle, let (afterTitle, t) = LinkScanner.title(buf, from: pos, to: end) {
          title = t
          pos = afterTitle
          pos = LinkScanner.spnl(buf, pos, end)
        }
        if pos < end, buf[pos] == ASCII.rparen {
          pos += 1
          dest = d
          matched = true
        } else {
          ok = false
        }
        if !ok { pos = savepos; title = nil }
      } else {
        pos = savepos
      }
    }
    if !matched {
      let beforeLabel = pos
      let n = LinkScanner.label(buf, from: pos, to: end)
      var reflabel: String? = nil
      if n > 0 { pos = beforeLabel + n }
      if n > 2 {
        reflabel = String(decoding: buf[(beforeLabel + 1)..<(beforeLabel + n - 1)], as: UTF8.self)
      } else if !opener.bracketAfter {
        reflabel = String(decoding: buf[(opener.index + 1)..<(startpos - 1)], as: UTF8.self)
      }
      if n == 0 { pos = savepos }
      if let label = reflabel, let ref = references[Text.normalizeLabel(label)] {
        dest = ref.destination
        title = ref.title
        matched = true
      }
    }

    if matched {
      let node = INode(kind: isImage ? .image(destination: dest, title: title) : .link(destination: dest, title: title),
        vrange: opener.node.vrange.lowerBound..<pos)
      var tmp = opener.node.next
      while let t = tmp {
        let n = t.next
        node.append(t)
        tmp = n
      }
      block.append(node)
      processEmphasis(stackBottom: opener.previousDelimiter)
      removeBracket()
      opener.node.unlink()
      if !isImage {
        var o = brackets
        while let b = o {
          if !b.image { b.active = false }
          o = b.previous
        }
      }
    } else {
      removeBracket()
      pos = startpos
      block.append(text((startpos - 1)..<startpos, literal: [ASCII.rbracket]))
    }
  }

  // MARK: - Autolinks, HTML, entities, extensions

  private mutating func parseAutolink(_ block: INode) -> Bool {
    guard let (e, url, isEmail) = AutolinkScanner.angle(buf, from: pos, to: end) else { return false }
    let s = pos
    pos = e
    block.append(INode(kind: .autolink(url: isEmail ? "mailto:" + url : url, text: url), vrange: s..<e))
    return true
  }

  private mutating func parseHTMLTag(_ block: INode) -> Bool {
    guard options.html, let e = HTMLScanner.scanInline(buf, from: pos, to: end) else { return false }
    let s = pos
    pos = e
    block.append(INode(kind: .html(String(decoding: buf[s..<e], as: UTF8.self)), vrange: s..<e))
    return true
  }

  private mutating func parseEntity(_ block: INode) {
    let s = pos
    if let (value, len) = Entity.scan(buf, at: pos, limit: end) {
      pos += len
      block.append(text(s..<pos, literal: Array(value.utf8)))
    } else {
      pos += 1
      block.append(text(s..<pos, literal: [ASCII.amp]))
    }
  }

  /// `$...$` with Pandoc's rules: no space after the opener, none before the closer, no digit after it.
  private mutating func parseMath(_ block: INode) -> Bool {
    let s = pos
    guard s + 2 < end, buf[s + 1] != ASCII.dollar, !buf[s + 1].isASCIIWhitespace else { return false }
    var k = s + 1
    while k < end {
      let c = buf[k]
      if c == ASCII.backslash { k += 2; continue }
      if c == ASCII.newline { return false }
      if c == ASCII.dollar {
        if buf[k - 1].isASCIIWhitespace { return false }
        if k + 1 < end, buf[k + 1].isDigit { return false }
        pos = k + 1
        block.append(INode(kind: .math(String(decoding: buf[(s + 1)..<k], as: UTF8.self)), vrange: s..<pos))
        return true
      }
      k += 1
    }
    return false
  }

  private mutating func parseEmoji(_ block: INode) -> Bool {
    let s = pos
    var k = s + 1
    while k < end, buf[k].isAlphanumeric || buf[k] == ASCII.underscore || buf[k] == ASCII.plus || buf[k] == ASCII.minus { k += 1 }
    guard k > s + 1, k < end, buf[k] == ASCII.colon else { return false }
    let code = String(decoding: buf[(s + 1)..<k], as: UTF8.self)
    guard let emoji = EmojiTable.map[Substring(code)] else { return false }
    pos = k + 1
    block.append(INode(kind: .emoji(emoji, shortcode: code), vrange: s..<pos))
    return true
  }

  private mutating func parseSuperscript(_ block: INode) -> Bool {
    let s = pos
    var k = s + 1
    while k < end, buf[k] != ASCII.caret {
      if buf[k].isASCIIWhitespace { return false }
      k += 1
    }
    guard k < end, k > s + 1 else { return false }
    let node = INode(kind: .superscript, vrange: s..<(k + 1))
    node.append(text((s + 1)..<k, literal: Array(buf[(s + 1)..<k])))
    block.append(node)
    pos = k + 1
    return true
  }

  /// Joins adjacent text nodes whose literal equals their source so URL scanning sees whole words.
  private func mergePlainText(_ root: INode) {
    var node = root.firstChild
    while let n = node {
      if n.isText, n.vrange.count == n.literal.count {
        while let m = n.next, m.isText, m.vrange.count == m.literal.count, m.vrange.lowerBound == n.vrange.upperBound {
          n.literal.append(contentsOf: m.literal)
          n.vrange = n.vrange.lowerBound..<m.vrange.upperBound
          m.unlink()
        }
      } else if n.firstChild != nil {
        mergePlainText(n)
      }
      node = n.next
    }
  }

  /// GFM extended autolinks: split plain-text nodes around bare URLs and emails.
  private func linkifyText(_ root: INode) {
    var node = root.firstChild
    while let n = node {
      let next = n.next
      if n.isText, n.vrange.count == n.literal.count, n.vrange.count > 3 {
        let found = AutolinkScanner.extended(buf, in: n.vrange)
        if !found.isEmpty {
          var cursor = n.vrange.lowerBound
          var last: INode = n
          var pieces: [INode] = []
          for f in found {
            if f.range.lowerBound > cursor {
              pieces.append(text(cursor..<f.range.lowerBound, literal: Array(buf[cursor..<f.range.lowerBound])))
            }
            let raw = String(decoding: buf[f.range], as: UTF8.self)
            pieces.append(INode(kind: .extendedAutolink(url: f.url, text: raw), vrange: f.range))
            cursor = f.range.upperBound
          }
          if cursor < n.vrange.upperBound {
            pieces.append(text(cursor..<n.vrange.upperBound, literal: Array(buf[cursor..<n.vrange.upperBound])))
          }
          for p in pieces { last.insertAfter(p); last = p }
          n.unlink()
        }
      } else if !n.isText, n.firstChild != nil {
        switch n.kind {
        case .link, .image, .autolink, .extendedAutolink: break
        default: linkifyText(n)
        }
      }
      node = next
    }
  }

  // MARK: - Conversion

  private func convert(_ parent: INode) -> [Inline] {
    var out: [Inline] = []
    var node = parent.firstChild
    while let n = node {
      if n.isText {
        // Merge adjacent text nodes.
        var literal = n.literal
        var vend = n.vrange.upperBound
        var m = n.next
        while let t = m, t.isText {
          literal.append(contentsOf: t.literal)
          vend = t.vrange.upperBound
          m = t.next
        }
        if !literal.isEmpty {
          out.append(Inline(kind: .text(String(decoding: literal, as: UTF8.self)), range: input.sourceRange(n.vrange.lowerBound..<vend)))
        }
        node = m
        continue
      }
      let children = convert(n)
      out.append(Inline(kind: n.kind, range: input.sourceRange(n.vrange), children: children))
      node = n.next
    }
    return out
  }
}
