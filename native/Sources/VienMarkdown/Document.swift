/// `MarkdownDocument` is a value: the source bytes plus the block tree parsed from them.
///
/// Edits go through `replace(_:with:)`, which reparses only the top-level blocks around the edit.
/// Blocks after the edit are kept as they are and carry a pending offset shift that is applied
/// lazily when they are read, so a keystroke in a 10 MB document costs microseconds, not a walk
/// over every node.

public struct MarkdownDocument: Sendable {
  public private(set) var bytes: [Byte]
  public private(set) var lines: LineTable
  public let options: ParserOptions
  public private(set) var references: [String: LinkReference] = [:]
  /// Footnote definition labels present in the document.
  public private(set) var footnotes: Set<String> = []

  fileprivate struct Entry: Sendable, Equatable {
    var block: Block
    var hasDefinitions: Bool

    init(_ block: Block) {
      self.block = block
      hasDefinitions = Entry.containsDefinitions(block)
    }

    func resolved(shift: Int) -> Block {
      guard shift != 0 else { return block }
      var b = block
      b.shift(by: shift)
      return b
    }

    static func containsDefinitions(_ block: Block) -> Bool {
      switch block.kind {
      case .linkReferenceDefinition, .footnoteDefinition: return true
      default: return block.children.contains(where: containsDefinitions)
      }
    }
  }

  private var entries: [Entry]
  /// Pending offset shift per top-level block (kept apart from `entries` so a keystroke touches little memory).
  private var shifts: [Int]

  private func start(_ i: Int) -> Int { entries[i].block.range.lowerBound + shifts[i] }
  private func resolved(_ i: Int) -> Block { entries[i].resolved(shift: shifts[i]) }

  public init(text: String, options: ParserOptions = .default) {
    self.init(bytes: Array(text.utf8), options: options)
  }

  public init(bytes: [Byte], options: ParserOptions = .default) {
    self.bytes = bytes
    self.options = options
    lines = LineTable(bytes: bytes)
    var parser = BlockParser(bytes: bytes, table: lines, options: options)
    entries = parser.parse(fromLine: 0).blocks.map(Entry.init)
    shifts = Array(repeating: 0, count: entries.count)
    collectDefinitions()
  }

  private mutating func collectDefinitions() {
    var refs: [String: LinkReference] = [:]
    var notes: Set<String> = []
    func walk(_ blocks: [Block]) {
      for b in blocks {
        switch b.kind {
        case .linkReferenceDefinition(let label, let ref): if refs[label] == nil { refs[label] = ref }
        case .footnoteDefinition(let label, _): notes.insert(label)
        default: break
        }
        if !b.children.isEmpty { walk(b.children) }
      }
    }
    for e in entries where e.hasDefinitions { walk([e.block]) }
    references = refs
    footnotes = notes
  }

  public var text: String { String(decoding: bytes, as: UTF8.self) }

  // MARK: - Blocks

  /// Top-level blocks with pending shifts applied on access.
  public struct BlockList: RandomAccessCollection, Sendable {
    fileprivate let entries: [Entry]
    fileprivate let shifts: [Int]
    public var startIndex: Int { 0 }
    public var endIndex: Int { entries.count }
    public subscript(i: Int) -> Block { entries[i].resolved(shift: shifts[i]) }
  }

  public var blocks: BlockList { BlockList(entries: entries, shifts: shifts) }

  /// Applies all pending offset shifts in place (call from idle time to keep reads cheap).
  public mutating func normalize() {
    for i in entries.indices where shifts[i] != 0 {
      entries[i].block.shift(by: shifts[i])
      shifts[i] = 0
    }
  }

  // MARK: - Queries

  /// Raw content text of a leaf block (lines joined with LF, prefixes stripped).
  public func text(of block: Block) -> String {
    var out = [Byte]()
    for (i, l) in block.lines.enumerated() {
      if i > 0 { out.append(ASCII.newline) }
      if l.virtualSpaces > 0 { out.append(contentsOf: repeatElement(ASCII.space, count: l.virtualSpaces)) }
      out.append(contentsOf: bytes[l.range])
    }
    return String(decoding: out, as: UTF8.self)
  }

  /// Parses the inline content of a paragraph, heading or table cell.
  public func inlines(of block: Block) -> [Inline] {
    let joiner: Byte? = { if case .tableCell = block.kind { return nil }; return ASCII.newline }()
    let input = InlineInput(bytes: bytes, lines: block.lines, joiner: joiner)
    var parser = InlineParser(input: input, references: references, footnotes: footnotes, options: options)
    return parser.parse()
  }

  /// Index of the top-level block containing `offset` (or the block preceding a gap), if any.
  public func topLevelIndex(containing offset: Int) -> Int? {
    guard !entries.isEmpty else { return nil }
    var lo = 0, hi = entries.count - 1
    while lo < hi {
      let mid = (lo + hi + 1) >> 1
      if start(mid) <= offset { lo = mid } else { hi = mid - 1 }
    }
    return lo
  }

  /// Path of blocks (outermost first) whose ranges contain `offset`.
  public func path(at offset: Int) -> [Block] {
    guard let i = topLevelIndex(containing: offset) else { return [] }
    var path: [Block] = []
    var candidates = [resolved(i)]
    if i + 1 < entries.count, start(i + 1) <= offset { candidates.append(resolved(i + 1)) }
    var level = candidates
    while true {
      guard let b = level.last(where: { $0.range.lowerBound <= offset && offset <= $0.range.upperBound }) else { break }
      path.append(b)
      level = b.children
    }
    return path
  }

  public struct Heading: Sendable, Equatable {
    public var level: Int
    public var text: String
    public var range: Range<Int>
  }

  /// Headings in document order (for outlines and navigation).
  public func headings() -> [Heading] {
    var out: [Heading] = []
    func walk(_ blocks: [Block], shift: Int) {
      for b in blocks {
        if case .heading(let level, _, _, _) = b.kind {
          var t = ""
          var lines = b.lines
          for i in lines.indices { lines[i].range = (lines[i].range.lowerBound + shift)..<(lines[i].range.upperBound + shift) }
          var shifted = b
          shifted.lines = lines
          for i in inlines(of: shifted) { i.appendPlainText(to: &t) }
          out.append(Heading(level: level, text: t, range: (b.range.lowerBound + shift)..<(b.range.upperBound + shift)))
        } else if b.isContainer {
          walk(b.children, shift: shift)
        }
      }
    }
    for (i, e) in entries.enumerated() { walk([e.block], shift: shifts[i]) }
    return out
  }

  public struct WordCount: Sendable, Equatable {
    public var words = 0
    public var characters = 0
    public var paragraphs = 0
    public var all = 0
  }

  /// Word statistics: whitespace-separated tokens that contain a letter or digit count as words
  /// (so `#`, `-`, `|` and fences do not), and CJK ideographs count as one word each.
  public func wordCount() -> WordCount {
    var wc = WordCount()
    var inToken = false
    var tokenHasContent = false
    var inParagraph = false
    var newlines = 0
    func endToken() {
      if inToken, tokenHasContent { wc.words += 1 }
      inToken = false
      tokenHasContent = false
    }
    for scalar in text.unicodeScalars {
      wc.all += 1
      if scalar == "\n" || scalar == "\r" {
        newlines += 1
        if newlines >= 2 { inParagraph = false }
        endToken()
        continue
      }
      if scalar.properties.isWhitespace { endToken(); continue }
      newlines = 0
      if !inParagraph { inParagraph = true; wc.paragraphs += 1 }
      wc.characters += 1
      let isCJK = (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) || (scalar.value >= 0x3040 && scalar.value <= 0x30FF) || (scalar.value >= 0xAC00 && scalar.value <= 0xD7AF)
      if isCJK {
        endToken()
        wc.words += 1
      } else {
        inToken = true
        if scalar.properties.isAlphabetic || scalar.properties.numericType != nil { tokenHasContent = true }
      }
    }
    endToken()
    return wc
  }

  // MARK: - Incremental editing

  /// Replaces `range` (in bytes) with `replacement`, reparsing only the affected top-level blocks.
  /// Returns the byte range (new coordinates) whose block structure was rebuilt.
  @discardableResult
  public mutating func replace(_ range: Range<Int>, with replacement: [Byte]) -> Range<Int> {
    precondition(range.lowerBound >= 0 && range.upperBound <= bytes.count && range.lowerBound <= range.upperBound)
    let delta = replacement.count - range.count

    guard !entries.isEmpty else {
      bytes.replaceSubrange(range, with: replacement)
      lines = LineTable(bytes: bytes)
      var parser = BlockParser(bytes: bytes, table: lines, options: options)
      entries = parser.parse(fromLine: 0).blocks.map(Entry.init)
      shifts = Array(repeating: 0, count: entries.count)
      collectDefinitions()
      return 0..<bytes.count
    }

    // Restart one top-level block before the one touched by the edit.
    let k = topLevelIndex(containing: range.lowerBound) ?? 0
    let restart = max(0, k - 1)
    let restartOffset = start(restart)
    let removedUTF16 = lines.utf16Offset(forByte: range.upperBound, in: bytes) - lines.utf16Offset(forByte: range.lowerBound, in: bytes)
    let editEndWasLineStart = lines.start(lines.line(containing: range.upperBound)) == range.upperBound

    bytes.replaceSubrange(range, with: replacement)
    lines.replace(range, with: replacement, in: bytes, removedUTF16: removedUTF16)

    // A new line can resume the old parse when it is an old top-level block's line, untouched by the
    // edit, that still starts at the same (shifted) offset. Answered by binary search on demand;
    // entries are still in old coordinates while this runs.
    func candidate(_ line: Int) -> Int? {
      let newLineStart = lines.start(line)
      let oldLineStart = newLineStart - delta
      guard oldLineStart >= range.upperBound else { return nil }
      if oldLineStart == range.upperBound {
        guard editEndWasLineStart else { return nil }
      } else {
        guard newLineStart > 0, bytes[newLineStart - 1].isLineEnd else { return nil }
      }
      var lo = k + 1, hi = entries.count
      while lo < hi {
        let mid = (lo + hi) >> 1
        if start(mid) < oldLineStart { lo = mid + 1 } else { hi = mid }
      }
      guard lo < entries.count else { return nil }
      let blockStart = start(lo)
      guard blockStart - oldLineStart <= 3 else { return nil }
      for i in newLineStart..<(blockStart + delta) where !bytes[i].isSpaceOrTab { return nil }
      return lo
    }

    let startLine = restart == 0 ? 0 : lines.line(containing: restartOffset)
    var parser = BlockParser(bytes: bytes, table: lines, options: options)
    let (fresh, stoppedAt) = parser.parse(fromLine: startLine, resync: { candidate($0) != nil })

    let tailStart = stoppedAt < lines.count ? (candidate(stoppedAt) ?? entries.count) : entries.count
    let freshEntries = fresh.map(Entry.init)
    let removedDefinitions = entries[restart..<tailStart].contains { $0.hasDefinitions }
    entries.replaceSubrange(restart..<tailStart, with: freshEntries)
    shifts.replaceSubrange(restart..<tailStart, with: repeatElement(0, count: freshEntries.count))
    if delta != 0 {
      for i in (restart + freshEntries.count)..<shifts.count { shifts[i] += delta }
    }
    if removedDefinitions || freshEntries.contains(where: { $0.hasDefinitions }) { collectDefinitions() }
    let tailIndex = restart + freshEntries.count
    let affectedEnd = tailIndex < entries.count ? start(tailIndex) : bytes.count
    return min(restartOffset, affectedEnd)..<affectedEnd
  }

  /// Non-mutating form of `replace(_:with:)`.
  public func replacing(_ range: Range<Int>, with replacement: [Byte]) -> MarkdownDocument {
    var copy = self
    copy.replace(range, with: replacement)
    return copy
  }

  /// Convenience for UTF-16 based text views: `range` and `replacement` are in UTF-16 units.
  @discardableResult
  public mutating func replace(utf16Range: Range<Int>, with replacement: String) -> Range<Int> {
    let lo = lines.byteOffset(forUTF16: utf16Range.lowerBound, in: bytes)
    let hi = lines.byteOffset(forUTF16: utf16Range.upperBound, in: bytes)
    return replace(lo..<hi, with: Array(replacement.utf8))
  }

  public func utf16Offset(forByte offset: Int) -> Int { lines.utf16Offset(forByte: offset, in: bytes) }
  public func byteOffset(forUTF16 offset: Int) -> Int { lines.byteOffset(forUTF16: offset, in: bytes) }
}

extension MarkdownDocument.BlockList: Equatable {
  public static func == (a: Self, b: Self) -> Bool { a.elementsEqual(b) }
}
