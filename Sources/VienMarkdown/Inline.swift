/// Inline AST (phase two). Produced lazily per leaf block; every node maps back to source bytes.

public enum InlineKind: Sendable, Equatable {
  /// Literal text after escape and entity decoding.
  case text(String)
  case softBreak
  case hardBreak
  /// Code span content (normalised) and the backtick run length.
  case code(String, fence: Int)
  case emphasis(delimiter: Byte)
  case strong(delimiter: Byte)
  case strikethrough(length: Int)
  case link(destination: String, title: String?)
  case image(destination: String, title: String?)
  /// `<url>` / `<email>`; the visible text is the raw source between the angle brackets.
  case autolink(url: String, text: String)
  /// GFM bare `www.` / `http(s)://` / email autolink; the visible text is the raw source.
  case extendedAutolink(url: String, text: String)
  case html(String)
  case math(String)
  case footnoteReference(String)
  case emoji(String, shortcode: String)
  case superscript
  case `subscript`
}

public struct Inline: Sendable, Equatable {
  public var kind: InlineKind
  /// Source byte range covering the whole construct, markers included.
  public var range: Range<Int>
  public var children: [Inline]

  public init(kind: InlineKind, range: Range<Int>, children: [Inline] = []) {
    self.kind = kind
    self.range = range
    self.children = children
  }

  /// Source ranges of the syntax markers (delimiters, brackets, backticks…) so an editor can dim them.
  public var markers: [Range<Int>] {
    let lo = range.lowerBound, hi = range.upperBound
    switch kind {
    case .emphasis: return [lo..<(lo + 1), (hi - 1)..<hi]
    case .strong: return [lo..<(lo + 2), (hi - 2)..<hi]
    case .strikethrough(let n): return [lo..<(lo + n), (hi - n)..<hi]
    case .code(_, let n): return [lo..<(lo + n), (hi - n)..<hi]
    case .math: return [lo..<(lo + 1), (hi - 1)..<hi]
    case .superscript, .subscript: return [lo..<(lo + 1), (hi - 1)..<hi]
    case .autolink: return [lo..<(lo + 1), (hi - 1)..<hi]
    case .link:
      let contentEnd = children.last?.range.upperBound ?? (lo + 1)
      return [lo..<(lo + 1), contentEnd..<hi]
    case .image:
      let contentEnd = children.last?.range.upperBound ?? (lo + 2)
      return [lo..<(lo + 2), contentEnd..<hi]
    case .footnoteReference, .emoji: return [range]
    default: return []
    }
  }

  /// Concatenated plain text of the subtree (alt text, heading titles, search).
  public var plainText: String {
    var out = ""
    appendPlainText(to: &out)
    return out
  }

  func appendPlainText(to out: inout String) {
    switch kind {
    case .text(let s): out += s
    case .softBreak, .hardBreak: out += "\n"
    case .code(let s, _): out += s
    case .autolink(_, let t), .extendedAutolink(_, let t): out += t
    case .html(let s): out += s
    case .math(let s): out += s
    case .footnoteReference(let s): out += "[^\(s)]"
    case .emoji(let e, _): out += e
    default: break
    }
    for c in children { c.appendPlainText(to: &out) }
  }
}
