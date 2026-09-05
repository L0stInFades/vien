/// Block-level AST. Every node carries exact source byte ranges so the editor can style, hide or
/// transform syntax without ever normalising the user's text.

/// One source line of leaf content after container prefixes have been stripped.
public struct ContentLine: Sendable, Equatable {
  public var range: Range<Int>
  /// Spaces owed by a partially consumed tab (CommonMark tab-stop rules); they exist only virtually.
  public var virtualSpaces: Int

  public init(range: Range<Int>, virtualSpaces: Int = 0) {
    self.range = range
    self.virtualSpaces = virtualSpaces
  }
}

public struct ListInfo: Sendable, Equatable {
  public var ordered: Bool
  public var start: Int
  /// `-`, `+`, `*` for bullets; `.` or `)` for ordered lists.
  public var marker: Byte
  public var tight: Bool
}

public struct TaskInfo: Sendable, Equatable {
  /// Range of `[ ]` / `[x]`.
  public var range: Range<Int>
  public var checked: Bool
}

public struct ListItemInfo: Sendable, Equatable {
  /// The bullet or `1.` marker bytes.
  public var marker: Range<Int>
  /// Column where item content starts (marker width + padding).
  public var contentIndent: Int
  public var task: TaskInfo?
}

public struct FenceInfo: Sendable, Equatable {
  public var fence: Byte
  public var length: Int
  public var indent: Int
  /// Whole opening line and optional closing line.
  public var open: Range<Int>
  public var close: Range<Int>?
  /// Raw info string range (trimmed) on the opening line, if any.
  public var info: Range<Int>?
}

public enum TableAlignment: Sendable, Equatable { case none, left, center, right }

public struct TableInfo: Sendable, Equatable {
  public var alignments: [TableAlignment]
  /// The `| --- | --- |` delimiter line.
  public var delimiter: Range<Int>
}

public struct LinkReference: Sendable, Equatable, Hashable {
  public var destination: String
  public var title: String?
}

public enum FrontMatterKind: Sendable, Equatable { case yaml, toml, json }

public enum BlockKind: Sendable, Equatable {
  case paragraph
  /// ATX: `marker` is the leading `#` run, `trailing` the optional closing run. Setext: `underline` is the `===`/`---` line.
  case heading(level: Int, marker: Range<Int>?, trailing: Range<Int>?, underline: Range<Int>?)
  case thematicBreak
  /// `prefixes` holds the `>` byte of every line of the quote, in order.
  case blockQuote(prefixes: [Range<Int>])
  case list(ListInfo)
  case listItem(ListItemInfo)
  case fencedCode(FenceInfo)
  case indentedCode
  case htmlBlock
  case linkReferenceDefinition(label: String, reference: LinkReference)
  case table(TableInfo)
  case tableRow(isHeader: Bool)
  case tableCell(TableAlignment)
  /// `$$` display math; `close` is nil when the block runs to the end of the document.
  case mathBlock(open: Range<Int>, close: Range<Int>?)
  case frontMatter(FrontMatterKind, open: Range<Int>, close: Range<Int>?)
  /// `[^label]:` definitions; content follows list-item indentation rules.
  case footnoteDefinition(label: String, marker: Range<Int>)
}

public struct Block: Sendable, Equatable {
  public var kind: BlockKind
  /// From the first byte of the first line to the end of the last content line (terminator excluded).
  public var range: Range<Int>
  public var children: [Block]
  /// Leaf content (paragraph text, code lines, HTML lines, math, front matter, table-cell text).
  public var lines: [ContentLine]

  public init(kind: BlockKind, range: Range<Int>, children: [Block] = [], lines: [ContentLine] = []) {
    self.kind = kind
    self.range = range
    self.children = children
    self.lines = lines
  }

  public var isContainer: Bool {
    switch kind {
    case .blockQuote, .list, .listItem, .table, .tableRow, .footnoteDefinition: return true
    default: return false
    }
  }

  public var isCode: Bool {
    switch kind {
    case .fencedCode, .indentedCode: return true
    default: return false
    }
  }

  /// Info string of a fenced code block (first word is the language), nil otherwise.
  public func fenceInfo(in bytes: [Byte]) -> String? {
    guard case .fencedCode(let f) = kind, let r = f.info else { return nil }
    return Text.unescapeAndDecode(bytes, r)
  }

  public func language(in bytes: [Byte]) -> String? {
    guard let info = fenceInfo(in: bytes) else { return nil }
    return info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
  }

  /// Shifts every source range in the subtree by `delta` (used when splicing reused blocks after an edit).
  mutating func shift(by delta: Int) {
    guard delta != 0 else { return }
    range = (range.lowerBound + delta)..<(range.upperBound + delta)
    for i in lines.indices {
      let r = lines[i].range
      lines[i].range = (r.lowerBound + delta)..<(r.upperBound + delta)
    }
    func s(_ r: Range<Int>) -> Range<Int> { (r.lowerBound + delta)..<(r.upperBound + delta) }
    func s(_ r: Range<Int>?) -> Range<Int>? { r.map(s) }
    switch kind {
    case .heading(let level, let marker, let trailing, let underline):
      kind = .heading(level: level, marker: s(marker), trailing: s(trailing), underline: s(underline))
    case .blockQuote(let prefixes):
      kind = .blockQuote(prefixes: prefixes.map(s))
    case .listItem(var info):
      info.marker = s(info.marker)
      if var t = info.task { t.range = s(t.range); info.task = t }
      kind = .listItem(info)
    case .fencedCode(var f):
      f.open = s(f.open); f.close = s(f.close); f.info = s(f.info)
      kind = .fencedCode(f)
    case .table(var t):
      t.delimiter = s(t.delimiter)
      kind = .table(t)
    case .mathBlock(let open, let close):
      kind = .mathBlock(open: s(open), close: s(close))
    case .frontMatter(let k, let open, let close):
      kind = .frontMatter(k, open: s(open), close: s(close))
    case .footnoteDefinition(let label, let marker):
      kind = .footnoteDefinition(label: label, marker: s(marker))
    case .paragraph, .thematicBreak, .list, .indentedCode, .htmlBlock, .linkReferenceDefinition, .tableRow,
      .tableCell:
      break
    }
    for i in children.indices { children[i].shift(by: delta) }
  }
}

/// Parser feature switches. Defaults mirror what the Electron app enabled for everyday writing.
public struct ParserOptions: Sendable, Equatable {
  public var math = true
  public var footnotes = true
  public var frontMatter = true
  public var tables = true
  public var strikethrough = true
  public var taskLists = true
  public var autolinks = true
  public var emoji = true
  public var superSubScript = false
  public var html = true

  public init() {}
  public static let `default` = ParserOptions()
}
