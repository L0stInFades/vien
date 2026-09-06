import AppKit
import VienCode
import VienMarkdown

/// Syntax tokens for fenced code blocks, in document byte offsets, cached per document revision.
/// A block is tokenized as one text so comments and strings can span lines; tokens are then split
/// at line boundaries, which is what the per-paragraph styler needs.
final class CodeHighlight {
  private var cache: [Range<Int>: [Token]] = [:]
  private var revision = -1

  /// Tokens of `block` that intersect `lines` (a byte range of one or more source lines).
  func tokens(for block: Block, in document: MarkdownFile, intersecting lines: Range<Int>) -> ArraySlice<Token> {
    let all = tokens(for: block, in: document)
    // Tokens are sorted and disjoint, so the first one ending after `lines` starts is a partition point.
    var lo = 0, hi = all.count
    while lo < hi {
      let mid = (lo + hi) >> 1
      if all[mid].range.upperBound <= lines.lowerBound { lo = mid + 1 } else { hi = mid }
    }
    var end = lo
    while end < all.count, all[end].range.lowerBound < lines.upperBound { end += 1 }
    return all[lo..<end]
  }

  func tokens(for block: Block, in document: MarkdownFile) -> [Token] {
    if revision != document.revision {
      cache.removeAll(keepingCapacity: true)
      revision = document.revision
    }
    if let hit = cache[block.range] { return hit }
    let result = Self.compute(block, in: document.markdown)
    if cache.count > 256 { cache.removeAll(keepingCapacity: true) }
    cache[block.range] = result
    return result
  }

  static func compute(_ block: Block, in doc: MarkdownDocument) -> [Token] {
    guard case .fencedCode = block.kind, let name = block.language(in: doc.bytes), let language = Language.named(name) else { return [] }
    var code: [UInt8] = []
    var lines: [(code: Int, doc: Int, length: Int)] = []
    for line in block.lines {
      lines.append((code.count, line.range.lowerBound, line.range.count))
      code.append(contentsOf: doc.bytes[line.range])
      code.append(0x0A)
    }
    var out: [Token] = []
    var li = 0
    for t in Highlighter.tokens(code, language: language) {
      var pos = t.range.lowerBound
      while pos < t.range.upperBound {
        while li + 1 < lines.count, lines[li + 1].code <= pos { li += 1 }
        let line = lines[li]
        let lineEnd = line.code + line.length
        let hi = min(t.range.upperBound, lineEnd)
        if hi > pos { out.append(Token(kind: t.kind, range: (line.doc + pos - line.code)..<(line.doc + hi - line.code))) }
        pos = max(hi, lineEnd + 1)
      }
    }
    return out
  }
}
