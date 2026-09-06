/// One pass over the bytes: comments, strings, numbers and identifiers, plus a few line-start and
/// flavour rules. Every path advances `i`, so the scan always terminates.
public enum Highlighter {
  /// Tokens for `code`, sorted and non-overlapping; ranges index `code`.
  public static func tokens(_ code: [UInt8], language: Language) -> [Token] {
    var scanner = Scanner(code, language)
    scanner.run()
    return scanner.out
  }

  /// Convenience for strings.
  public static func tokens(_ code: String, language: Language) -> [Token] {
    tokens(Array(code.utf8), language: language)
  }
}

private struct Scanner {
  let b: [UInt8]
  let n: Int
  let lang: Language
  let lineComments: [[UInt8]]
  let blockComments: [([UInt8], [UInt8])]
  let strings: [([UInt8], [UInt8], Language.StringRule)]
  /// Per-byte identifier membership (letters, digits, `_`, non-ASCII, the language's extras).
  let identTable: [Bool]
  var i = 0
  var out: [Token] = []
  var lineStart = true
  var depth = 0  // brace depth (CSS)
  var inTag = false  // markup: between `<` and `>`
  var rawUntil: [UInt8]? = nil  // markup: plain text until this closing tag
  var selectorCache: (end: Int, value: Bool)? = nil  // CSS: selectorAhead memo

  init(_ bytes: [UInt8], _ language: Language) {
    b = bytes
    n = bytes.count
    lang = language
    lineComments = language.lineComments.map { Array($0.utf8) }
    blockComments = language.blockComments.map { (Array($0.0.utf8), Array($0.1.utf8)) }
    strings = language.strings.map { (Array($0.open.utf8), Array($0.close.utf8), $0) }
    var table = [Bool](repeating: false, count: 256)
    for c in 0..<256 {
      let u = UInt8(c)
      table[c] = (u | 0x20) >= 0x61 && (u | 0x20) <= 0x7A || (u >= 0x30 && u <= 0x39) || u == 0x5F || u >= 0x80 || language.identifierExtras.contains(u)
    }
    identTable = table
  }

  // MARK: Helpers

  @inline(__always) func at(_ k: Int) -> UInt8 { k >= 0 && k < n ? b[k] : 0 }
  @inline(__always) func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }
  @inline(__always) func isLetter(_ c: UInt8) -> Bool { (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7A }
  @inline(__always) func isUpper(_ c: UInt8) -> Bool { c >= 0x41 && c <= 0x5A }
  @inline(__always) func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0D }
  @inline(__always) func isIdentStart(_ c: UInt8) -> Bool { isLetter(c) || c == 0x5F || c >= 0x80 }
  @inline(__always) func isIdent(_ c: UInt8) -> Bool { identTable[Int(c)] }

  func match(_ pattern: [UInt8], at k: Int) -> Bool {
    guard k + pattern.count <= n else { return false }
    for j in 0..<pattern.count where b[k + j] != pattern[j] { return false }
    return true
  }

  /// `pattern` is lowercase; ASCII letters in the input match either case.
  func matchIgnoringCase(_ pattern: [UInt8], at k: Int) -> Bool {
    guard k + pattern.count <= n else { return false }
    for j in 0..<pattern.count {
      let x = b[k + j]
      if (x >= 0x41 && x <= 0x5A ? x | 0x20 : x) != pattern[j] { return false }
    }
    return true
  }

  func lineEnd(from k: Int) -> Int {
    var e = k
    while e < n, b[e] != 0x0A { e += 1 }
    return e
  }

  func nextNonSpace(from k: Int) -> Int {
    var e = k
    while e < n, isSpace(b[e]) { e += 1 }
    return e
  }

  mutating func emit(_ kind: TokenKind, _ lo: Int, _ hi: Int) {
    if hi > lo { out.append(Token(kind: kind, range: lo..<hi)) }
  }

  func word(_ lo: Int, _ hi: Int) -> String { String(decoding: b[lo..<hi], as: UTF8.self) }

  // MARK: Main loop

  mutating func run() {
    while i < n {
      let c = b[i]
      if c == 0x0A { i += 1; lineStart = true; continue }
      if lineStart {
        // Rules that must see the line's first byte, blank or not.
        if lang.flavor == .diff { lineStart = false; _ = lineStartRule(c); continue }
        if lang.flavor == .makefile, c == 0x09 { lineStart = false; i += 1; continue }  // recipe line
      }
      if isSpace(c) { i += 1; continue }
      let atLineStart = lineStart
      lineStart = false
      if let raw = rawUntil {
        // Plain text (script/style bodies) until the closing tag.
        if matchIgnoringCase(raw, at: i) { rawUntil = nil } else { i += 1; continue }
      }
      if atLineStart, lineStartRule(c) { continue }
      if comment(c) { continue }
      switch lang.flavor {
      case .markup: if markup(c) { continue }
      case .css: if cssPrefix(c) { continue }
      case .yaml: if yamlInline(c) { continue }
      case .markdown: if markdownInline(c) { continue }
      default: break
      }
      if string(c) { continue }
      if number(c) { continue }
      if identifier(c) { continue }
      if c == 0x7B { depth += 1 } else if c == 0x7D { depth = max(0, depth - 1) }
      i += 1
    }
  }

  // MARK: Line-start rules

  mutating func lineStartRule(_ c: UInt8) -> Bool {
    let end = lineEnd(from: i)
    switch lang.flavor {
    case .diff:
      let kind: TokenKind? =
        match(Array("+++ ".utf8), at: i) || match(Array("--- ".utf8), at: i) || match(Array("@@".utf8), at: i)
          || match(Array("diff ".utf8), at: i) || match(Array("index ".utf8), at: i) || match(Array("Only in ".utf8), at: i)
        ? .meta : c == 0x2B ? .inserted : c == 0x2D ? .deleted : nil
      if let kind { emit(kind, i, end) }
      i = end
      return true
    case .markdown:
      if c == 0x23 {  // heading
        var k = i
        while k < end, b[k] == 0x23, k - i < 6 { k += 1 }
        if k < end, b[k] == 0x20 { emit(.heading, i, end); i = end; return true }
      }
      if c == 0x3E { emit(.comment, i, end); i = end; return true }  // block quote
      if match(Array("```".utf8), at: i) || match(Array("~~~".utf8), at: i) { emit(.meta, i, end); i = end; return true }
      if (c == 0x2D || c == 0x2A || c == 0x2B), at(i + 1) == 0x20 { emit(.keyword, i, i + 1); i += 1; return true }
      if isDigit(c) {
        var k = i
        while k < end, isDigit(b[k]) { k += 1 }
        if k < end, b[k] == 0x2E || b[k] == 0x29, at(k + 1) == 0x20 { emit(.keyword, i, k + 1); i = k + 1; return true }
      }
      return false
    case .yaml:
      var k = i
      while k < end, b[k] == 0x2D, at(k + 1) == 0x20 || at(k + 1) == 0x0A {  // list items
        emit(.keyword, k, k + 1)
        k = nextNonSpace(from: k + 1)
      }
      if k == i, match(Array("---".utf8), at: i) || match(Array("...".utf8), at: i) { emit(.meta, i, end); i = end; return true }
      if k < end, b[k] != 0x22, b[k] != 0x27, b[k] != 0x23, b[k] != 0x26, b[k] != 0x2A, b[k] != 0x21 {
        var e = k
        while e < end, b[e] != 0x23 {
          if b[e] == 0x3A, at(e + 1) == 0x20 || at(e + 1) == 0x0A || e + 1 == n { break }
          e += 1
        }
        if e < end, b[e] == 0x3A {
          var keyEnd = e
          while keyEnd > k, isSpace(b[keyEnd - 1]) { keyEnd -= 1 }
          emit(.property, k, keyEnd)
          i = e + 1
          return true
        }
      }
      let consumed = k > i
      i = k
      return consumed
    case .toml:
      if c == 0x5B {  // [table] / [[array]]
        var e = i
        while e < end, b[e] != 0x23 { e += 1 }
        while e > i, isSpace(b[e - 1]) { e -= 1 }
        emit(.meta, i, e)
        i = e
        return true
      }
      if c != 0x23, c != 0x3B {
        var e = i
        while e < end, b[e] != 0x3D, b[e] != 0x23, b[e] != 0x3B { e += 1 }
        if e < end, b[e] == 0x3D {
          var keyEnd = e
          while keyEnd > i, isSpace(b[keyEnd - 1]) { keyEnd -= 1 }
          emit(.property, i, keyEnd)
          i = e + 1
          return true
        }
      }
      return false
    case .makefile:
      if c == 0x09 { return false }  // recipe line
      var e = i
      while e < end, b[e] != 0x3A, b[e] != 0x3D, b[e] != 0x23, !(b[e] == 0x3F && at(e + 1) == 0x3D), !(b[e] == 0x2B && at(e + 1) == 0x3D) { e += 1 }
      guard e < end, e > i else { return false }
      var nameEnd = e
      while nameEnd > i, isSpace(b[nameEnd - 1]) { nameEnd -= 1 }
      if b[e] == 0x3A, at(e + 1) != 0x3D { emit(.function, i, nameEnd); i = e + 1; return true }
      if b[e] == 0x3D || b[e] == 0x3A || b[e] == 0x3F || b[e] == 0x2B { emit(.property, i, nameEnd); i = e; return true }
      return false
    case .shell:
      if c == 0x23, at(i + 1) == 0x21 { emit(.meta, i, end); i = end; return true }  // shebang
      return false
    default:
      if lang.preprocessor, c == 0x23 {
        var k = i + 1
        while k < end, isSpace(b[k]) { k += 1 }
        while k < end, isLetter(b[k]) { k += 1 }
        emit(.meta, i, k)
        i = k
        return true
      }
      return false
    }
  }

  // MARK: Comments

  mutating func comment(_ c: UInt8) -> Bool {
    for (open, close) in blockComments where open[0] == c && match(open, at: i) {
      let start = i
      var k = i + open.count
      var level = 1
      while k < n {
        if lang.nestedComments, match(open, at: k) { level += 1; k += open.count; continue }
        if match(close, at: k) {
          level -= 1
          k += close.count
          if level == 0 { break }
          continue
        }
        k += 1
      }
      emit(.comment, start, min(k, n))
      i = min(k, n)
      return true
    }
    for open in lineComments where open[0] == c && match(open, at: i) {
      if c == 0x23, at(i - 1) == 0x24 { return false }  // `$#`
      let end = lineEnd(from: i)
      emit(.comment, i, end)
      i = end
      return true
    }
    return false
  }

  // MARK: Strings

  mutating func string(_ c: UInt8) -> Bool {
    if lang.flavor == .markup, !inTag { return false }
    if lang.hashRawStrings, c == 0x23 {
      var hashes = 0
      while at(i + hashes) == 0x23 { hashes += 1 }
      if at(i + hashes) == 0x22 { scanRaw(from: i, quoteAt: i + hashes, hashes: hashes); return true }
    }
    for (open, close, rule) in strings where open[0] == c && match(open, at: i) {
      scanString(from: i, openAt: i, open: open, close: close, rule: rule)
      return true
    }
    if lang.charLiterals, c == 0x27 {
      // Exactly one character or escape between the quotes; Rust lifetimes (`'a`) stay plain.
      var k = i + 1
      if at(k) == 0x5C {
        k += 2
        if at(k - 1) == 0x75, at(k) == 0x7B { while k < n, b[k] != 0x7D, b[k] != 0x0A { k += 1 }; k += 1 }
      } else if at(k) >= 0x80 {
        k += 1
        while k < n, b[k] & 0xC0 == 0x80 { k += 1 }
      } else {
        k += 1
      }
      if at(k) == 0x27 { emit(.string, i, k + 1); i = k + 1; return true }
    }
    return false
  }

  /// A string token from `start` (a prefix like `f` or `r`, or the quote itself) whose opening
  /// delimiter is at `openAt`.
  mutating func scanString(from start: Int, openAt: Int, open: [UInt8], close: [UInt8], rule: Language.StringRule) {
    var k = openAt + open.count
    while k < n {
      let c = b[k]
      if rule.escapes, c == 0x5C { k += 2; continue }
      if c == 0x0A, !rule.multiline { break }
      if match(close, at: k) { k += close.count; break }
      k += 1
    }
    k = min(k, n)
    var kind = TokenKind.string
    if lang.flavor == .json, at(nextNonSpace(from: k)) == 0x3A { kind = .property }
    emit(kind, start, k)
    i = k
  }

  mutating func scanRaw(from start: Int, quoteAt: Int, hashes: Int) {
    var k = quoteAt + 1
    while k < n {
      if b[k] == 0x22 {
        var h = 0
        while h < hashes, at(k + 1 + h) == 0x23 { h += 1 }
        if h == hashes { k += 1 + hashes; break }
      }
      k += 1
    }
    emit(.string, start, min(k, n))
    i = min(k, n)
  }

  // MARK: Numbers

  mutating func number(_ c: UInt8) -> Bool {
    guard isDigit(c) || (c == 0x2E && isDigit(at(i + 1)) && at(i - 1) != 0x2E && !isIdent(at(i - 1))) else { return false }
    var k = i
    if c == 0x30, (at(k + 1) | 0x20) == 0x78 || (at(k + 1) | 0x20) == 0x62 || (at(k + 1) | 0x20) == 0x6F {
      k += 2
      while k < n, isDigit(b[k]) || (isLetter(b[k]) && (b[k] | 0x20) <= 0x66) || b[k] == 0x5F { k += 1 }
    } else {
      while k < n, isDigit(b[k]) || b[k] == 0x5F { k += 1 }
      if at(k) == 0x2E, isDigit(at(k + 1)) {
        k += 1
        while k < n, isDigit(b[k]) || b[k] == 0x5F { k += 1 }
      }
      if (at(k) | 0x20) == 0x65, isDigit(at(k + 1)) || ((at(k + 1) == 0x2B || at(k + 1) == 0x2D) && isDigit(at(k + 2))) {
        k += 2
        while k < n, isDigit(b[k]) { k += 1 }
      }
    }
    while k < n, isLetter(b[k]) || isDigit(b[k]) || b[k] == 0x25 { k += 1 }  // suffixes and units
    emit(.number, i, k)
    i = k
    return true
  }

  // MARK: Identifiers

  mutating func identifier(_ c: UInt8) -> Bool {
    let start = i
    var prefixKind: TokenKind? = nil
    if c == 0x40, let kind = lang.atPrefix, isIdentStart(at(i + 1)) {
      prefixKind = kind
      i += 1
    } else if c == 0x24, let kind = lang.dollarPrefix {
      if at(i + 1) == 0x7B || (lang.flavor == .makefile && at(i + 1) == 0x28) {
        let close: UInt8 = at(i + 1) == 0x7B ? 0x7D : 0x29
        var k = i + 2
        while k < n, b[k] != close, b[k] != 0x0A { k += 1 }
        emit(kind, start, min(k + 1, n))
        i = min(k + 1, n)
        return true
      }
      if isIdentStart(at(i + 1)) || isDigit(at(i + 1)) || [0x40, 0x3F, 0x23, 0x2A, 0x21, 0x24, 0x2D].contains(at(i + 1)) {
        var k = i + 1
        if isIdentStart(b[k]) { while k < n, isIdent(b[k]) { k += 1 } } else { k += 1 }
        emit(kind, start, k)
        i = k
        return true
      }
      return false
    } else if c == 0x23, lang.hashKeywords, isIdentStart(at(i + 1)) {
      prefixKind = .keyword
      i += 1
    } else if c == 0x40, lang.flavor == .css, isIdentStart(at(i + 1)) {
      prefixKind = .keyword
      i += 1
    } else if !(isIdentStart(c) || (lang.identifierExtras.contains(c) && (isIdentStart(at(i + 1)) || at(i + 1) == c))) {
      return false
    }
    var k = i
    var hash: UInt64 = 0xCBF29CE484222325
    while k < n, isIdent(b[k]) {
      hash = (hash ^ UInt64(b[k])) &* 0x100000001B3
      k += 1
    }
    if k == i { i = start + 1; return true }
    // String prefixes: r"…", f'…', br"…", r#"…"#.
    if k - i <= lang.stringPrefixMaxLength, lang.stringPrefixes.contains(word(i, k)) {
      if lang.hashRawStrings, at(k) == 0x23 {
        var hashes = 0
        while at(k + hashes) == 0x23 { hashes += 1 }
        if at(k + hashes) == 0x22 { scanRaw(from: start, quoteAt: k + hashes, hashes: hashes); return true }
      }
      for (open, close, rule) in strings where match(open, at: k) {
        scanString(from: start, openAt: k, open: open, close: close, rule: rule)
        return true
      }
    }
    let followedByParen = at(k) == 0x28
    var kind: TokenKind? = prefixKind
    if kind == nil {
      if let known = lang.kind(ofWord: b[i..<k], hash: hash) { kind = known }
      else if lang.flavor == .css { kind = cssIdentifier(end: k) }
      else if lang.upperConstants, k - i > 1, b[i..<k].allSatisfy({ isUpper($0) || isDigit($0) || $0 == 0x5F }), b[i..<k].contains(where: isUpper) { kind = .constant }
      else if lang.functionCalls, followedByParen { kind = .function }
      else if lang.capitalizedTypes, isUpper(b[i]) { kind = .type }
    }
    if let kind { emit(kind, start, k) }
    i = k
    return true
  }

  // MARK: CSS

  /// True when a `{` comes before any `;` or `}`: the text up to it is a selector, not a
  /// declaration. Memoised per statement so a block is scanned once, not once per token.
  mutating func selectorAhead(from k: Int) -> Bool {
    if let cache = selectorCache, k < cache.end { return cache.value }
    var e = k
    var value = false
    scan: while e < n {
      switch b[e] {
      case 0x7B: value = true; break scan
      case 0x3B, 0x7D: break scan
      default: e += 1
      }
    }
    selectorCache = (end: e + 1, value: value)
    return value
  }

  mutating func cssPrefix(_ c: UInt8) -> Bool {
    if selectorAhead(from: i) {
      if (c == 0x2E || c == 0x23), isIdentStart(at(i + 1)) || at(i + 1) == 0x2D {
        var k = i + 1
        while k < n, isIdent(b[k]) { k += 1 }
        emit(.attribute, i, k)
        i = k
        return true
      }
      if c == 0x3A {
        var k = i + 1
        if at(k) == 0x3A { k += 1 }
        while k < n, isIdent(b[k]) { k += 1 }
        emit(.keyword, i, k)
        i = k
        return true
      }
    } else {
      if c == 0x23, isLetter(at(i + 1)) || isDigit(at(i + 1)) {
        var k = i + 1
        while k < n, isLetter(b[k]) || isDigit(b[k]) { k += 1 }
        emit(.constant, i, k)
        i = k
        return true
      }
      if c == 0x21, match(Array("!important".utf8), at: i) { emit(.keyword, i, i + 10); i += 10; return true }
    }
    return false
  }

  mutating func cssIdentifier(end k: Int) -> TokenKind? {
    if selectorAhead(from: k) { return .tag }
    if at(nextNonSpace(from: k)) == 0x3A { return .property }
    return at(k) == 0x28 ? .function : nil
  }

  // MARK: Markup

  mutating func markup(_ c: UInt8) -> Bool {
    if inTag {
      if c == 0x3E { emit(.tag, i, i + 1); i += 1; inTag = false; rawUntil = pendingRaw; pendingRaw = nil; return true }
      if c == 0x2F, at(i + 1) == 0x3E { emit(.tag, i, i + 2); i += 2; inTag = false; pendingRaw = nil; return true }
      if isIdentStart(c) || c == 0x3A {
        var k = i
        while k < n, isIdent(b[k]) || b[k] == 0x2D || b[k] == 0x3A || b[k] == 0x2E { k += 1 }
        emit(.attribute, i, k)
        i = k
        return true
      }
      return false
    }
    if c == 0x3C {
      if at(i + 1) == 0x21 || at(i + 1) == 0x3F {  // <!DOCTYPE …>, <?xml …?>
        var k = i
        while k < n, b[k] != 0x3E { k += 1 }
        emit(.meta, i, min(k + 1, n))
        i = min(k + 1, n)
        return true
      }
      var k = i + 1
      if at(k) == 0x2F { k += 1 }
      guard isIdentStart(at(k)) else { i += 1; return true }
      let nameStart = k
      while k < n, isIdent(b[k]) || b[k] == 0x2D || b[k] == 0x3A || b[k] == 0x2E { k += 1 }
      let name = word(nameStart, k).lowercased()
      emit(.tag, i, k)
      i = k
      inTag = true
      // After a <script>/<style> start tag closes, the body is plain until the matching end tag.
      if at(nameStart - 1) != 0x2F, name == "script" || name == "style" { pendingRaw = Array("</\(name)".utf8) }
      return true
    }
    if c == 0x26 {  // &entity;
      var k = i + 1
      while k < n, isLetter(b[k]) || isDigit(b[k]) || b[k] == 0x23 { k += 1 }
      if at(k) == 0x3B { emit(.constant, i, k + 1); i = k + 1; return true }
      i += 1
      return true
    }
    // Plain text between tags.
    var k = i
    while k < n, b[k] != 0x3C, b[k] != 0x26, b[k] != 0x0A { k += 1 }
    i = max(k, i + 1)
    return true
  }

  /// `</script` or `</style` once the start tag being scanned closes.
  var pendingRaw: [UInt8]? = nil

  // MARK: YAML / Markdown inline

  mutating func yamlInline(_ c: UInt8) -> Bool {
    if c == 0x26 || c == 0x2A || c == 0x21, isIdentStart(at(i + 1)) || at(i + 1) == 0x21 {  // &anchor *alias !!tag
      var k = i + 1
      while k < n, isIdent(b[k]) || b[k] == 0x21 || b[k] == 0x2D { k += 1 }
      emit(.meta, i, k)
      i = k
      return true
    }
    return false
  }

  mutating func markdownInline(_ c: UInt8) -> Bool {
    if c == 0x60 {  // `code`
      var k = i + 1
      while k < n, b[k] != 0x60, b[k] != 0x0A { k += 1 }
      if at(k) == 0x60 { emit(.string, i, k + 1); i = k + 1 } else { i += 1 }
      return true
    }
    if c == 0x5B {  // [text](url)
      var k = i + 1
      while k < n, b[k] != 0x5D, b[k] != 0x0A { k += 1 }
      if at(k) == 0x5D, at(k + 1) == 0x28 {
        var e = k + 2
        while e < n, b[e] != 0x29, b[e] != 0x0A { e += 1 }
        if at(e) == 0x29 { emit(.string, k + 1, e + 1); i = e + 1; return true }
      }
      i += 1
      return true
    }
    return false
  }
}

