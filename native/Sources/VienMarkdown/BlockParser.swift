/// Phase-one block structure parser: a faithful port of the CommonMark reference algorithm
/// (container matching → block starts → lazy continuation), extended with GFM tables/task lists
/// and the Vien extensions (math blocks, front matter, footnote definitions).
///
/// The parser is line-driven and can start at any document line and stop as soon as a caller-
/// supplied resync point is reached with no open blocks, which is what makes incremental reparsing
/// of long documents cheap.

final class BlockNode {
  var kind: BlockKind
  var open = true
  let startLine: Int
  var startOffset: Int
  var endOffset: Int
  var lines: [ContentLine] = []
  var children: [BlockNode] = []
  unowned(unsafe) var parent: BlockNode?

  // Parse-time bookkeeping.
  var lastLineBlank = false
  var lastLineChecked = false
  var htmlBlockType = 0
  var listMarkerOffset = 0
  var listPadding = 0
  var isDocument = false

  init(kind: BlockKind, startLine: Int, startOffset: Int) {
    self.kind = kind
    self.startLine = startLine
    self.startOffset = startOffset
    self.endOffset = startOffset
  }

  var lastChild: BlockNode? { children.last }
  var firstChild: BlockNode? { children.first }

  var isParagraph: Bool {
    if isDocument { return false }
    if case .paragraph = kind { return true }
    return false
  }

  var acceptsLines: Bool {
    if isDocument { return false }
    switch kind {
    case .paragraph, .fencedCode, .indentedCode, .htmlBlock, .mathBlock, .frontMatter, .table: return true
    default: return false
    }
  }

  var isLeafAcceptingLines: Bool {
    if isDocument { return false }
    switch kind {
    case .fencedCode, .indentedCode, .htmlBlock, .mathBlock, .frontMatter: return true
    default: return false
    }
  }

  func canContain(_ child: BlockKind) -> Bool {
    switch kind {
    case .list:
      if case .listItem = child { return true }
      return false
    case .blockQuote, .listItem, .footnoteDefinition:
      if case .listItem = child { return false }
      return true
    default:
      return isDocument && { if case .listItem = child { return false }; return true }()
    }
  }

  func freeze() -> Block {
    Block(kind: kind, range: startOffset..<max(startOffset, endOffset), children: children.map { $0.freeze() }, lines: lines)
  }
}

struct BlockParser {
  let bytes: [Byte]
  let table: LineTable
  let options: ParserOptions

  // Line state.
  private var currentLine = -1
  private var lineStart = 0
  private var lineEnd = 0
  private var offset = 0
  private var column = 0
  private var nextNonspace = 0
  private var nextNonspaceColumn = 0
  private var indent = 0
  private var indented = false
  private var blank = false
  private var partiallyConsumedTab = false
  /// Set by block starts whose opening line carries no content (fences, `$$`, front matter, table delimiter).
  private var lineConsumed = false

  // Tree state.
  private let doc: BlockNode
  private var tip: BlockNode
  private var oldtip: BlockNode
  private var lastMatchedContainer: BlockNode
  private var allClosed = true

  init(bytes: [Byte], table: LineTable, options: ParserOptions) {
    self.bytes = bytes
    self.table = table
    self.options = options
    doc = BlockNode(kind: .paragraph, startLine: 0, startOffset: 0)
    doc.isDocument = true
    tip = doc
    oldtip = doc
    lastMatchedContainer = doc
  }

  /// Parses lines `fromLine ..< table.count`. `resync(line)` is consulted before each line after the
  /// first; when it returns true and nothing is open, parsing stops and the parsed blocks are returned
  /// together with the index of the first unparsed line.
  mutating func parse(fromLine: Int, resync: (Int) -> Bool = { _ in false }) -> (blocks: [Block], stoppedAt: Int) {
    var line = fromLine
    let total = table.count
    while line < total {
      // A trailing empty "line" after the final terminator is not a real line.
      if line == total - 1, table.starts[line] == bytes.count, total > 1 { break }
      if line > fromLine, tip === doc, resync(line) { break }
      incorporateLine(line)
      line += 1
    }
    while tip !== doc { finalize(tip) }
    doc.endOffset = bytes.count
    return (doc.children.map { $0.freeze() }, line)
  }

  // MARK: - Line scanning primitives

  @inline(__always) private func peek(_ i: Int) -> Byte? { i < lineEnd ? bytes[i] : nil }

  private mutating func findNextNonspace() {
    var i = offset
    var cols = column
    while i < lineEnd {
      let c = bytes[i]
      if c == ASCII.space { i += 1; cols += 1 }
      else if c == ASCII.tab { i += 1; cols += 4 - (cols % 4) }
      else { break }
    }
    blank = i >= lineEnd
    nextNonspace = i
    nextNonspaceColumn = cols
    indent = nextNonspaceColumn - column
    indented = indent >= 4
  }

  private mutating func advanceNextNonspace() {
    offset = nextNonspace
    column = nextNonspaceColumn
    partiallyConsumedTab = false
  }

  private mutating func advanceOffset(_ n: Int, columns: Bool) {
    var count = n
    while count > 0, offset < lineEnd {
      let c = bytes[offset]
      if c == ASCII.tab {
        let charsToTab = 4 - (column % 4)
        if columns {
          partiallyConsumedTab = charsToTab > count
          let advance = min(charsToTab, count)
          column += advance
          offset += partiallyConsumedTab ? 0 : 1
          count -= advance
        } else {
          partiallyConsumedTab = false
          column += charsToTab
          offset += 1
          count -= 1
        }
      } else {
        partiallyConsumedTab = false
        offset += 1
        column += 1
        count -= 1
      }
    }
  }

  private mutating func addLine() {
    var virtual = 0
    var start = offset
    if partiallyConsumedTab {
      start += 1  // skip over the tab
      virtual = 4 - (column % 4)
    }
    tip.lines.append(ContentLine(range: start..<lineEnd, virtualSpaces: virtual))
    tip.endOffset = lineEnd
  }

  private mutating func addChild(_ kind: BlockKind, at off: Int) -> BlockNode {
    while !tip.canContain(kind) { finalize(tip) }
    let node = BlockNode(kind: kind, startLine: currentLine, startOffset: lineStart + off)
    node.parent = tip
    tip.children.append(node)
    tip = node
    return node
  }

  private mutating func closeUnmatchedBlocks() {
    guard !allClosed else { return }
    while oldtip !== lastMatchedContainer, let parent = oldtip.parent {
      finalize(oldtip)
      oldtip = parent
    }
    allClosed = true
  }

  /// Closes `node`. End offsets come from the node's own content so trailing blank lines never
  /// leak into a block's range.
  private mutating func finalize(_ node: BlockNode) {
    let parent = node.parent
    node.open = false
    switch node.kind {
    case .paragraph: finalizeParagraph(node)
    case .list: finalizeList(node)
    case .indentedCode: finalizeIndentedCode(node)
    case .listItem(let info):
      node.endOffset = max(node.children.last?.endOffset ?? 0, info.marker.upperBound, info.task?.range.upperBound ?? 0)
    case .footnoteDefinition(_, let marker):
      node.endOffset = max(node.children.last?.endOffset ?? 0, marker.upperBound)
    case .blockQuote(let prefixes):
      node.endOffset = max(node.children.last?.endOffset ?? 0, prefixes.last?.upperBound ?? node.startOffset)
    default: break
    }
    if let parent { parent.endOffset = max(parent.endOffset, node.endOffset) }
    tip = parent ?? doc
  }

  // MARK: - Main loop

  private mutating func incorporateLine(_ line: Int) {
    currentLine = line
    lineStart = table.starts[line]
    lineEnd = table.ends[line]
    offset = lineStart
    column = 0
    blank = false
    partiallyConsumedTab = false
    oldtip = tip
    lineConsumed = false
    var container = doc
    allClosed = true

    // Match the open containers.
    var matched = true
    while let last = container.lastChild, last.open {
      container = last
      findNextNonspace()
      switch continueBlock(container) {
      case .matched: break
      case .failed:
        container = container.parent!
        matched = false
      case .consumed:
        return
      }
      if !matched { break }
    }

    allClosed = container === oldtip
    lastMatchedContainer = container
    var matchedLeaf = container.isLeafAcceptingLines

    // Try new block starts.
    while !matchedLeaf {
      findNextNonspace()
      if !indented, !maybeSpecial(bytes.byte(at: nextNonspace)) {
        advanceNextNonspace()
        break
      }
      switch tryBlockStarts(&container) {
      case .none:
        advanceNextNonspace()
        matchedLeaf = true  // nothing matched: fall through to text handling
        break
      case .container:
        container = tip
      case .leaf:
        container = tip
        matchedLeaf = true
      }
    }

    // What remains is a text line.
    if lineConsumed {
      closeUnmatchedBlocks()
      var cont: BlockNode? = container
      while let c = cont { c.lastLineBlank = false; cont = c.parent }
    } else if !allClosed, !blank, tip.isParagraph {
      addLine()  // lazy paragraph continuation
    } else {
      closeUnmatchedBlocks()
      if blank, let last = container.lastChild { last.lastLineBlank = true }
      let isFenced: Bool = { if case .fencedCode = container.kind { return true }; return false }()
      let isEmptyNewItem: Bool = {
        if case .listItem = container.kind { return container.firstChild == nil && container.startLine == currentLine }
        return false
      }()
      let isQuote: Bool = { if case .blockQuote = container.kind { return true }; return false }()
      let lastLineBlank = blank && !(isQuote || isFenced || isEmptyNewItem)
      var cont: BlockNode? = container
      while let c = cont { c.lastLineBlank = lastLineBlank; cont = c.parent }

      if container.acceptsLines {
        if case .table = container.kind {
          if !blank { addTableRow(container) }
        } else {
          addLine()
          if case .htmlBlock = container.kind, container.htmlBlockType >= 1, container.htmlBlockType <= 5,
            HTMLScanner.blockEnds(type: container.htmlBlockType, bytes, from: offset, to: lineEnd)
          {
            finalize(container)
          }
        }
      } else if offset < lineEnd, !blank {
        container = addChild(.paragraph, at: offset - lineStart)
        advanceNextNonspace()
        container.startOffset = offset
        addLine()
      }
    }

    // Headings and thematic breaks never continue: close them now so the tree is clean at line ends.
    switch tip.kind {
    case .heading, .thematicBreak, .linkReferenceDefinition: finalize(tip)
    default: break
    }
  }

  @inline(__always) private func maybeSpecial(_ c: Byte?) -> Bool {
    guard let c else { return false }
    switch c {
    case ASCII.hash, ASCII.backtick, ASCII.tilde, ASCII.star, ASCII.plus, ASCII.underscore, ASCII.equals, ASCII.lt,
      ASCII.gt, ASCII.minus, ASCII.dollar, ASCII.lbracket, ASCII.pipe, ASCII.colon, ASCII.semicolon:
      return true
    default:
      return c.isDigit
    }
  }

  // MARK: - Continuation

  private enum Continue { case matched, failed, consumed }
  private enum Start { case none, container, leaf }

  private mutating func continueBlock(_ node: BlockNode) -> Continue {
    switch node.kind {
    case .blockQuote(var prefixes):
      guard !indented, peek(nextNonspace) == ASCII.gt else { return .failed }
      advanceNextNonspace()
      prefixes.append(offset..<(offset + 1))
      node.kind = .blockQuote(prefixes: prefixes)
      advanceOffset(1, columns: false)
      if let c = peek(offset), c.isSpaceOrTab { advanceOffset(1, columns: true) }
      return .matched

    case .listItem:
      if blank {
        if node.firstChild == nil { return .failed }
        advanceNextNonspace()
        return .matched
      }
      if indent >= node.listMarkerOffset + node.listPadding {
        advanceOffset(node.listMarkerOffset + node.listPadding, columns: true)
        return .matched
      }
      return .failed

    case .footnoteDefinition:
      if blank { advanceNextNonspace(); return .matched }
      if indent >= 4 { advanceOffset(4, columns: true); return .matched }
      return .failed

    case .fencedCode(var fence):
      if !indented, peek(nextNonspace) == fence.fence {
        var i = nextNonspace
        while i < lineEnd, bytes[i] == fence.fence { i += 1 }
        if i - nextNonspace >= fence.length {
          var j = i
          while j < lineEnd, bytes[j].isSpaceOrTab { j += 1 }
          if j >= lineEnd {
            fence.close = lineStart..<lineEnd
            node.kind = .fencedCode(fence)
            node.endOffset = lineEnd
            finalize(node)
            return .consumed
          }
        }
      }
      var i = fence.indent
      while i > 0, let c = peek(offset), c.isSpaceOrTab { advanceOffset(1, columns: true); i -= 1 }
      return .matched

    case .indentedCode:
      if indent >= 4 { advanceOffset(4, columns: true); return .matched }
      if blank { advanceNextNonspace(); return .matched }
      return .failed

    case .htmlBlock:
      return blank && (node.htmlBlockType == 6 || node.htmlBlockType == 7) ? .failed : .matched

    case .paragraph:
      return blank ? .failed : .matched

    case .table:
      return blank ? .failed : .matched

    case .mathBlock(let open, _):
      if !indented, isDollarDollarLine(from: nextNonspace) {
        node.kind = .mathBlock(open: open, close: lineStart..<lineEnd)
        node.endOffset = lineEnd
        finalize(node)
        return .consumed
      }
      return .matched

    case .frontMatter(let kind, let open, _):
      if isFrontMatterFence(kind, from: lineStart) {
        node.kind = .frontMatter(kind, open: open, close: lineStart..<lineEnd)
        node.endOffset = lineEnd
        finalize(node)
        return .consumed
      }
      return .matched

    case .heading, .thematicBreak, .linkReferenceDefinition, .tableRow, .tableCell:
      return .failed

    case .list:
      return .matched
    }
  }

  // MARK: - Block starts

  private mutating func tryBlockStarts(_ container: inout BlockNode) -> Start {
    if let r = startFrontMatter() { return r }
    if let r = startBlockQuote() { return r }
    if let r = startATXHeading() { return r }
    if let r = startFencedCode() { return r }
    if let r = startHTMLBlock(container) { return r }
    if let r = startTable(container) { return r }
    if let r = startSetextHeading(&container) { return r }
    if let r = startThematicBreak() { return r }
    if let r = startMathBlock() { return r }
    if let r = startFootnoteDefinition(container) { return r }
    if let r = startListItem(container) { return r }
    if let r = startIndentedCode() { return r }
    return .none
  }

  private mutating func startBlockQuote() -> Start? {
    guard !indented, peek(nextNonspace) == ASCII.gt else { return nil }
    advanceNextNonspace()
    let markerOffset = offset
    advanceOffset(1, columns: false)
    if let c = peek(offset), c.isSpaceOrTab { advanceOffset(1, columns: true) }
    closeUnmatchedBlocks()
    let node = addChild(.blockQuote(prefixes: [markerOffset..<(markerOffset + 1)]), at: markerOffset - lineStart)
    node.startOffset = markerOffset
    return .container
  }

  private mutating func startATXHeading() -> Start? {
    guard !indented, peek(nextNonspace) == ASCII.hash else { return nil }
    var i = nextNonspace
    while i < lineEnd, bytes[i] == ASCII.hash { i += 1 }
    let level = i - nextNonspace
    guard level <= 6 else { return nil }
    if i < lineEnd, !bytes[i].isSpaceOrTab { return nil }
    advanceNextNonspace()
    let marker = offset..<(offset + level)
    advanceOffset(level, columns: false)
    closeUnmatchedBlocks()
    // Content: strip leading whitespace, trailing whitespace and an optional closing `#` run.
    var start = offset
    while start < lineEnd, bytes[start].isSpaceOrTab { start += 1 }
    var end = lineEnd
    while end > start, bytes[end - 1].isSpaceOrTab { end -= 1 }
    var trailing: Range<Int>? = nil
    var k = end
    while k > start, bytes[k - 1] == ASCII.hash { k -= 1 }
    if k < end, (k == start || bytes[k - 1].isSpaceOrTab) {
      trailing = k..<end
      end = k
      while end > start, bytes[end - 1].isSpaceOrTab { end -= 1 }
    }
    let node = addChild(.heading(level: level, marker: marker, trailing: trailing, underline: nil), at: marker.lowerBound - lineStart)
    node.startOffset = marker.lowerBound
    node.lines = [ContentLine(range: start..<end)]
    node.endOffset = lineEnd
    offset = lineEnd
    return .leaf
  }

  private mutating func startFencedCode() -> Start? {
    guard !indented, let c = peek(nextNonspace), c == ASCII.backtick || c == ASCII.tilde else { return nil }
    var i = nextNonspace
    while i < lineEnd, bytes[i] == c { i += 1 }
    let length = i - nextNonspace
    guard length >= 3 else { return nil }
    if c == ASCII.backtick {
      var j = i
      while j < lineEnd { if bytes[j] == ASCII.backtick { return nil }; j += 1 }
    }
    closeUnmatchedBlocks()
    var infoStart = i
    while infoStart < lineEnd, bytes[infoStart].isSpaceOrTab { infoStart += 1 }
    var infoEnd = lineEnd
    while infoEnd > infoStart, bytes[infoEnd - 1].isSpaceOrTab { infoEnd -= 1 }
    let info = FenceInfo(
      fence: c, length: length, indent: indent, open: lineStart..<lineEnd, close: nil,
      info: infoStart < infoEnd ? infoStart..<infoEnd : nil)
    let node = addChild(.fencedCode(info), at: nextNonspace - lineStart)
    node.startOffset = nextNonspace
    node.endOffset = lineEnd
    advanceNextNonspace()
    advanceOffset(length, columns: false)
    offset = lineEnd
    lineConsumed = true
    return .leaf
  }

  private mutating func startHTMLBlock(_ container: BlockNode) -> Start? {
    guard options.html, !indented, peek(nextNonspace) == ASCII.lt else { return nil }
    let maybeLazy = !allClosed && !blank && tip.isParagraph
    guard let type = HTMLScanner.blockStart(bytes, from: nextNonspace, to: lineEnd, allowType7: !container.isParagraph && !maybeLazy) else {
      return nil
    }
    closeUnmatchedBlocks()
    let node = addChild(.htmlBlock, at: offset - lineStart)
    node.startOffset = offset
    node.htmlBlockType = type
    return .leaf
  }

  private mutating func startSetextHeading(_ container: inout BlockNode) -> Start? {
    guard !indented, container.isParagraph, let c = peek(nextNonspace),
      c == ASCII.equals || c == ASCII.minus
    else { return nil }
    var i = nextNonspace
    while i < lineEnd, bytes[i] == c { i += 1 }
    var j = i
    while j < lineEnd, bytes[j].isSpaceOrTab { j += 1 }
    guard j >= lineEnd else { return nil }
    closeUnmatchedBlocks()
    // Reference definitions at the start of the paragraph are resolved first.
    let defs = extractReferenceDefinitions(container)
    guard !container.lines.isEmpty else {
      // The paragraph was only definitions; the underline is ordinary text for the next paragraph.
      let parent = container.parent ?? doc
      replaceParagraph(container, with: defs)
      tip = parent
      lastMatchedContainer = parent
      container = parent
      return nil
    }
    let heading = BlockNode(
      kind: .heading(level: c == ASCII.equals ? 1 : 2, marker: nil, trailing: nil, underline: nextNonspace..<lineEnd),
      startLine: container.startLine, startOffset: container.startOffset)
    heading.lines = container.lines
    heading.endOffset = lineEnd
    heading.open = false
    replaceParagraph(container, with: defs + [heading])
    tip = heading
    lastMatchedContainer = heading
    offset = lineEnd
    return .leaf
  }

  private mutating func startThematicBreak() -> Start? {
    guard !indented, let c = peek(nextNonspace), c == ASCII.minus || c == ASCII.star || c == ASCII.underscore else {
      return nil
    }
    var i = nextNonspace
    var count = 0
    while i < lineEnd {
      let b = bytes[i]
      if b == c { count += 1 } else if !b.isSpaceOrTab { return nil }
      i += 1
    }
    guard count >= 3 else { return nil }
    closeUnmatchedBlocks()
    let node = addChild(.thematicBreak, at: nextNonspace - lineStart)
    node.startOffset = nextNonspace
    node.endOffset = lineEnd
    offset = lineEnd
    return .leaf
  }

  private mutating func startMathBlock() -> Start? {
    guard options.math, !indented, peek(nextNonspace) == ASCII.dollar, peek(nextNonspace + 1) == ASCII.dollar else {
      return nil
    }
    // `$$ ... $$` on a single line is a complete display block.
    var end = lineEnd
    while end > nextNonspace + 2, bytes[end - 1].isSpaceOrTab { end -= 1 }
    if end - nextNonspace > 4, bytes[end - 1] == ASCII.dollar, bytes[end - 2] == ASCII.dollar {
      closeUnmatchedBlocks()
      let node = addChild(.mathBlock(open: nextNonspace..<(nextNonspace + 2), close: (end - 2)..<end), at: nextNonspace - lineStart)
      node.startOffset = nextNonspace
      node.lines = [ContentLine(range: (nextNonspace + 2)..<(end - 2))]
      node.endOffset = lineEnd
      offset = lineEnd
      finalize(node)
      lineConsumed = true
      return .leaf
    }
    guard isDollarDollarLine(from: nextNonspace) else { return nil }
    closeUnmatchedBlocks()
    let node = addChild(.mathBlock(open: nextNonspace..<(nextNonspace + 2), close: nil), at: nextNonspace - lineStart)
    node.startOffset = nextNonspace
    node.endOffset = lineEnd
    offset = lineEnd
    lineConsumed = true
    return .leaf
  }

  private func isDollarDollarLine(from i: Int) -> Bool {
    guard i + 1 < lineEnd, bytes[i] == ASCII.dollar, bytes[i + 1] == ASCII.dollar else { return false }
    var j = i + 2
    while j < lineEnd, bytes[j].isSpaceOrTab { j += 1 }
    return j >= lineEnd
  }

  private mutating func startFrontMatter() -> Start? {
    guard options.frontMatter, currentLine == 0, doc.children.isEmpty, offset == lineStart else { return nil }
    let kind: FrontMatterKind
    if isFrontMatterFence(.yaml, from: lineStart) { kind = .yaml }
    else if isFrontMatterFence(.toml, from: lineStart) { kind = .toml }
    else if isFrontMatterFence(.json, from: lineStart) { kind = .json }
    else { return nil }
    // Only open the block when a closing fence exists (otherwise `---` is a thematic break).
    var line = 1
    var found = false
    while line < table.count {
      if isFrontMatterFence(kind, lineStart: table.starts[line], lineEnd: table.ends[line]) { found = true; break }
      line += 1
    }
    guard found else { return nil }
    let node = addChild(.frontMatter(kind, open: lineStart..<lineEnd, close: nil), at: 0)
    node.endOffset = lineEnd
    offset = lineEnd
    lineConsumed = true
    return .leaf
  }

  private func isFrontMatterFence(_ kind: FrontMatterKind, from i: Int) -> Bool {
    isFrontMatterFence(kind, lineStart: i, lineEnd: lineEnd)
  }

  private func isFrontMatterFence(_ kind: FrontMatterKind, lineStart s: Int, lineEnd e: Int) -> Bool {
    let c: Byte = switch kind { case .yaml: ASCII.minus; case .toml: ASCII.plus; case .json: ASCII.semicolon }
    guard e - s >= 3, bytes[s] == c, bytes[s + 1] == c, bytes[s + 2] == c else { return false }
    var j = s + 3
    while j < e, bytes[j].isSpaceOrTab { j += 1 }
    return j >= e
  }

  private mutating func startFootnoteDefinition(_ container: BlockNode) -> Start? {
    guard options.footnotes, !indented, peek(nextNonspace) == ASCII.lbracket, peek(nextNonspace + 1) == ASCII.caret
    else { return nil }
    if container.isParagraph { return nil }
    var i = nextNonspace + 2
    let labelStart = i
    while i < lineEnd, bytes[i] != ASCII.rbracket {
      let c = bytes[i]
      if c.isASCIIWhitespace || c == ASCII.lbracket || c == ASCII.caret { return nil }
      i += 1
    }
    guard i > labelStart, i + 1 < lineEnd, bytes[i + 1] == ASCII.colon else { return nil }
    let label = Text.string(bytes, labelStart..<i)
    closeUnmatchedBlocks()
    advanceNextNonspace()
    let markerStart = offset
    advanceOffset(i + 2 - nextNonspace, columns: false)
    if let c = peek(offset), c.isSpaceOrTab { advanceOffset(1, columns: true) }
    let node = addChild(.footnoteDefinition(label: label, marker: markerStart..<(i + 2)), at: markerStart - lineStart)
    node.startOffset = markerStart
    return .container
  }

  private mutating func startListItem(_ container: BlockNode) -> Start? {
    guard !indented || { if case .list = container.kind { return true }; return false }() else { return nil }
    guard let marker = parseListMarker(container) else { return nil }
    closeUnmatchedBlocks()
    // Add the list if needed.
    var needsList = true
    if case .list(let existing) = tip.kind, existing.ordered == marker.ordered, existing.marker == marker.info.marker {
      needsList = false
    }
    if needsList {
      let list = addChild(.list(marker.info), at: nextNonspace - lineStart)
      list.startOffset = marker.markerRange.lowerBound
    }
    let item = addChild(.listItem(ListItemInfo(marker: marker.markerRange, contentIndent: marker.padding, task: marker.task)),
      at: marker.markerRange.lowerBound - lineStart)
    item.startOffset = marker.markerRange.lowerBound
    item.listMarkerOffset = marker.markerOffset
    item.listPadding = marker.padding
    return .container
  }

  private struct ListMarker {
    var info: ListInfo
    var ordered: Bool
    var markerRange: Range<Int>
    var markerOffset: Int
    var padding: Int
    var task: TaskInfo?
  }

  private mutating func parseListMarker(_ container: BlockNode) -> ListMarker? {
    guard !indented, let c = peek(nextNonspace) else { return nil }
    let isParagraph = container.isParagraph
    var info: ListInfo
    var markerLength: Int
    if c == ASCII.star || c == ASCII.plus || c == ASCII.minus {
      info = ListInfo(ordered: false, start: 0, marker: c, tight: true)
      markerLength = 1
    } else if c.isDigit {
      var i = nextNonspace
      var value = 0
      var digits = 0
      while i < lineEnd, bytes[i].isDigit, digits < 10 { value = value * 10 + Int(bytes[i] - 0x30); i += 1; digits += 1 }
      guard digits <= 9, let d = peek(i), d == ASCII.dot || d == ASCII.rparen else { return nil }
      if isParagraph, value != 1 { return nil }
      info = ListInfo(ordered: true, start: value, marker: d, tight: true)
      markerLength = i + 1 - nextNonspace
    } else {
      return nil
    }
    // Marker must be followed by whitespace or end of line.
    if let after = peek(nextNonspace + markerLength), !after.isSpaceOrTab { return nil }
    // A list item interrupting a paragraph must not start with a blank line.
    if isParagraph {
      var j = nextNonspace + markerLength
      while j < lineEnd, bytes[j].isSpaceOrTab { j += 1 }
      if j >= lineEnd { return nil }
    }
    let markerOffset = indent
    advanceNextNonspace()
    let markerRange = offset..<(offset + markerLength)
    advanceOffset(markerLength, columns: true)
    let spacesStartCol = column
    let spacesStartOffset = offset
    let savedPartial = partiallyConsumedTab
    repeat {
      advanceOffset(1, columns: true)
    } while column - spacesStartCol < 5 && (peek(offset).map { $0.isSpaceOrTab } ?? false)
    let blankItem = peek(offset) == nil
    let spacesAfterMarker = column - spacesStartCol
    let padding: Int
    if spacesAfterMarker >= 5 || spacesAfterMarker < 1 || blankItem {
      padding = markerLength + 1
      column = spacesStartCol
      offset = spacesStartOffset
      partiallyConsumedTab = savedPartial
      if let sp = peek(offset), sp.isSpaceOrTab { advanceOffset(1, columns: true) }
    } else {
      padding = markerLength + spacesAfterMarker
    }
    var task: TaskInfo? = nil
    if options.taskLists, let b0 = peek(offset), b0 == ASCII.lbracket, let b1 = peek(offset + 1),
      b1 == ASCII.space || b1 == 0x78 || b1 == 0x58, peek(offset + 2) == ASCII.rbracket,
      let b3 = peek(offset + 3), b3.isSpaceOrTab
    {
      task = TaskInfo(range: offset..<(offset + 3), checked: b1 != ASCII.space)
    }
    return ListMarker(info: info, ordered: info.ordered, markerRange: markerRange, markerOffset: markerOffset, padding: padding, task: task)
  }

  private mutating func startIndentedCode() -> Start? {
    guard indented, !blank, !tip.isParagraph else { return nil }
    advanceOffset(4, columns: true)
    closeUnmatchedBlocks()
    let node = addChild(.indentedCode, at: offset - lineStart)
    node.startOffset = offset
    return .leaf
  }

  private mutating func startTable(_ container: BlockNode) -> Start? {
    guard options.tables, !indented, container.isParagraph, container.lines.count == 1 else { return nil }
    guard let alignments = TableScanner.delimiterRow(bytes, from: nextNonspace, to: lineEnd) else { return nil }
    let header = container.lines[0]
    let headerCells = TableScanner.splitCells(bytes, header.range)
    guard headerCells.count == alignments.count else { return nil }
    closeUnmatchedBlocks()
    let table = BlockNode(
      kind: .table(TableInfo(alignments: alignments, delimiter: nextNonspace..<lineEnd)),
      startLine: container.startLine, startOffset: container.startOffset)
    let row = BlockNode(kind: .tableRow(isHeader: true), startLine: container.startLine, startOffset: header.range.lowerBound)
    row.parent = table
    row.endOffset = header.range.upperBound
    for (i, cell) in headerCells.enumerated() {
      let c = BlockNode(kind: .tableCell(alignments[i]), startLine: container.startLine, startOffset: cell.first?.lowerBound ?? header.range.lowerBound)
      c.lines = cell.map { ContentLine(range: $0) }
      c.endOffset = cell.last?.upperBound ?? c.startOffset
      c.parent = row
      row.children.append(c)
    }
    table.children = [row]
    table.endOffset = lineEnd
    row.open = false
    for c in row.children { c.open = false }
    replaceParagraph(container, with: [table])
    tip = table
    lastMatchedContainer = table
    offset = lineEnd
    lineConsumed = true
    return .leaf
  }

  private mutating func addTableRow(_ table: BlockNode) {
    guard case .table(let info) = table.kind else { return }
    let cells = TableScanner.splitCells(bytes, offset..<lineEnd)
    let row = BlockNode(kind: .tableRow(isHeader: false), startLine: currentLine, startOffset: nextNonspace)
    row.parent = table
    row.open = false
    row.endOffset = lineEnd
    for (i, cell) in cells.prefix(info.alignments.count).enumerated() {
      let c = BlockNode(kind: .tableCell(info.alignments[i]), startLine: currentLine, startOffset: cell.first?.lowerBound ?? nextNonspace)
      c.lines = cell.map { ContentLine(range: $0) }
      c.endOffset = cell.last?.upperBound ?? c.startOffset
      c.parent = row
      c.open = false
      row.children.append(c)
    }
    table.children.append(row)
    table.endOffset = lineEnd
  }

  // MARK: - Finalisation

  private func replaceParagraph(_ paragraph: BlockNode, with nodes: [BlockNode]) {
    // The paragraph being replaced is (almost always) the last child: search from the end.
    guard let parent = paragraph.parent, let idx = parent.children.lastIndex(where: { $0 === paragraph }) else { return }
    for n in nodes { n.parent = parent }
    parent.children.replaceSubrange(idx...idx, with: nodes)
    paragraph.open = false
  }

  private mutating func finalizeParagraph(_ node: BlockNode) {
    let defs = extractReferenceDefinitions(node)
    if node.lines.isEmpty {
      replaceParagraph(node, with: defs)
    } else if !defs.isEmpty, let parent = node.parent, let idx = parent.children.lastIndex(where: { $0 === node }) {
      for d in defs { d.parent = parent; d.open = false }
      parent.children.insert(contentsOf: defs, at: idx)
      node.startOffset = node.lines[0].range.lowerBound
    }
  }

  /// Pulls link reference definitions off the front of a paragraph, returning them as nodes.
  private func extractReferenceDefinitions(_ node: BlockNode) -> [BlockNode] {
    var defs: [BlockNode] = []
    while let first = node.lines.first, first.range.lowerBound < first.range.upperBound,
      bytes[first.range.lowerBound] == ASCII.lbracket,
      let def = ReferenceScanner.scan(bytes, lines: node.lines)
    {
      let consumed = Array(node.lines.prefix(def.linesConsumed))
      let d = BlockNode(
        kind: .linkReferenceDefinition(label: def.label, reference: def.reference),
        startLine: node.startLine, startOffset: consumed.first!.range.lowerBound)
      d.lines = consumed
      d.endOffset = consumed.last!.range.upperBound
      d.open = false
      defs.append(d)
      node.lines.removeFirst(def.linesConsumed)
    }
    return defs
  }

  private func finalizeList(_ node: BlockNode) {
    guard case .list(var info) = node.kind else { return }
    var tight = true
    let items = node.children
    outer: for (i, item) in items.enumerated() {
      let hasNext = i + 1 < items.count
      if endsWithBlankLine(item), hasNext { tight = false; break }
      let subs = item.children
      for (j, sub) in subs.enumerated() {
        if endsWithBlankLine(sub), hasNext || j + 1 < subs.count { tight = false; break outer }
      }
    }
    info.tight = tight
    node.kind = .list(info)
    // Trailing blank lines are not part of the list.
    if let last = items.last { node.endOffset = last.endOffset }
  }

  private func endsWithBlankLine(_ start: BlockNode) -> Bool {
    var node: BlockNode? = start
    while let n = node {
      if n.lastLineBlank { return true }
      switch n.kind {
      case .list, .listItem:
        if !n.lastLineChecked { n.lastLineChecked = true; node = n.lastChild } else { n.lastLineChecked = true; return false }
      default:
        n.lastLineChecked = true
        return false
      }
    }
    return false
  }

  private func finalizeIndentedCode(_ node: BlockNode) {
    while let last = node.lines.last, isBlank(last.range) { node.lines.removeLast() }
    if let last = node.lines.last { node.endOffset = last.range.upperBound }
  }

  private func isBlank(_ r: Range<Int>) -> Bool {
    for i in r where !bytes[i].isSpaceOrTab { return false }
    return true
  }
}
