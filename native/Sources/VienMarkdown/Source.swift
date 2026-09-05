/// Byte-level helpers shared by the block and inline parsers, and the line table.
///
/// The parser works on UTF-8 bytes and byte offsets end to end; nothing here allocates per byte.

public typealias Byte = UInt8

extension Byte {
  @inline(__always) var isSpaceOrTab: Bool { self == 0x20 || self == 0x09 }
  @inline(__always) var isLineEnd: Bool { self == 0x0A || self == 0x0D }
  /// CommonMark "whitespace character": space, tab, LF, FF, CR.
  @inline(__always) var isASCIIWhitespace: Bool { self == 0x20 || (self >= 0x09 && self <= 0x0D) }
  @inline(__always) var isDigit: Bool { self >= 0x30 && self <= 0x39 }
  @inline(__always) var isHexDigit: Bool { isDigit || (self | 0x20 >= 0x61 && self | 0x20 <= 0x66) }
  @inline(__always) var isLetter: Bool { self | 0x20 >= 0x61 && self | 0x20 <= 0x7A }
  @inline(__always) var isAlphanumeric: Bool { isLetter || isDigit }
  @inline(__always) var lowercased: Byte { isLetter ? self | 0x20 : self }
  /// ASCII punctuation per CommonMark §2.1.
  @inline(__always) var isASCIIPunctuation: Bool {
    (self >= 0x21 && self <= 0x2F) || (self >= 0x3A && self <= 0x40) || (self >= 0x5B && self <= 0x60)
      || (self >= 0x7B && self <= 0x7E)
  }
}

enum ASCII {
  static let tab: Byte = 0x09, newline: Byte = 0x0A, cr: Byte = 0x0D, space: Byte = 0x20
  static let bang: Byte = 0x21, quote: Byte = 0x22, hash: Byte = 0x23, dollar: Byte = 0x24
  static let amp: Byte = 0x26, apostrophe: Byte = 0x27, lparen: Byte = 0x28, rparen: Byte = 0x29
  static let star: Byte = 0x2A, plus: Byte = 0x2B, minus: Byte = 0x2D, dot: Byte = 0x2E, slash: Byte = 0x2F
  static let colon: Byte = 0x3A, semicolon: Byte = 0x3B, lt: Byte = 0x3C, equals: Byte = 0x3D, gt: Byte = 0x3E
  static let question: Byte = 0x3F, at: Byte = 0x40, lbracket: Byte = 0x5B, backslash: Byte = 0x5C
  static let rbracket: Byte = 0x5D, caret: Byte = 0x5E, underscore: Byte = 0x5F, backtick: Byte = 0x60
  static let lbrace: Byte = 0x7B, pipe: Byte = 0x7C, rbrace: Byte = 0x7D, tilde: Byte = 0x7E
}

extension Array where Element == Byte {
  @inline(__always) func byte(at i: Int) -> Byte? { i >= 0 && i < count ? self[i] : nil }

  /// Decodes the Unicode scalar starting at `i` (must be a scalar boundary). Returns scalar and byte length.
  func scalar(at i: Int) -> (Unicode.Scalar, Int)? {
    guard i < count else { return nil }
    let b0 = self[i]
    if b0 < 0x80 { return (Unicode.Scalar(b0), 1) }
    let len: Int
    var value: UInt32
    if b0 & 0xE0 == 0xC0 { len = 2; value = UInt32(b0 & 0x1F) }
    else if b0 & 0xF0 == 0xE0 { len = 3; value = UInt32(b0 & 0x0F) }
    else if b0 & 0xF8 == 0xF0 { len = 4; value = UInt32(b0 & 0x07) }
    else { return (Unicode.Scalar(0xFFFD)!, 1) }
    guard i + len <= count else { return (Unicode.Scalar(0xFFFD)!, 1) }
    for k in 1..<len {
      let b = self[i + k]
      guard b & 0xC0 == 0x80 else { return (Unicode.Scalar(0xFFFD)!, 1) }
      value = (value << 6) | UInt32(b & 0x3F)
    }
    return (Unicode.Scalar(value) ?? Unicode.Scalar(0xFFFD)!, len)
  }

  /// Decodes the Unicode scalar ending right before `i`.
  func scalar(before i: Int) -> Unicode.Scalar? {
    guard i > 0 else { return nil }
    var start = i - 1
    while start > 0 && self[start] & 0xC0 == 0x80 && i - start < 4 { start -= 1 }
    return scalar(at: start)?.0
  }

  @inline(__always) func hasPrefix(_ prefix: StaticString, at i: Int) -> Bool {
    let n = prefix.utf8CodeUnitCount
    guard i + n <= count else { return false }
    return prefix.withUTF8Buffer { buf in
      for k in 0..<n where self[i + k] != buf[k] { return false }
      return true
    }
  }

  @inline(__always) func hasPrefixIgnoringCase(_ prefix: StaticString, at i: Int) -> Bool {
    let n = prefix.utf8CodeUnitCount
    guard i + n <= count else { return false }
    return prefix.withUTF8Buffer { buf in
      for k in 0..<n where self[i + k].lowercased != buf[k].lowercased { return false }
      return true
    }
  }
}

extension Unicode.Scalar {
  /// Unicode whitespace per CommonMark §2.1 (Zs category, tab, LF, FF, CR).
  var isMarkdownWhitespace: Bool {
    switch value {
    case 0x09, 0x0A, 0x0C, 0x0D, 0x20: return true
    default: return properties.generalCategory == .spaceSeparator
    }
  }

  /// Unicode punctuation per CommonMark 0.31 §2.1 (P* and S* categories, plus ASCII punctuation).
  var isMarkdownPunctuation: Bool {
    if value < 0x80 { return Byte(value).isASCIIPunctuation }
    switch properties.generalCategory {
    case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
      .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
      return true
    default: return false
    }
  }
}

/// Maps byte offsets to lines. Line `i` spans `starts[i] ..< ends[i]`; its terminator (LF, CR or CRLF)
/// follows. A document always has at least one line; a trailing terminator yields a final empty line.
public struct LineTable: Sendable, Equatable {
  public private(set) var starts: [Int] = []
  public private(set) var ends: [Int] = []
  /// UTF-16 offset of each line start, for bridging to Foundation text views.
  public private(set) var utf16Starts: [Int] = []

  public init(bytes: [Byte]) {
    starts.reserveCapacity(bytes.count / 40 + 1)
    ends.reserveCapacity(bytes.count / 40 + 1)
    utf16Starts.reserveCapacity(bytes.count / 40 + 1)
    starts.append(0)
    utf16Starts.append(0)
    Self.scan(bytes, from: 0, utf16: 0, until: Int.max, starts: &starts, ends: &ends, utf16Starts: &utf16Starts)
  }

  public var count: Int { starts.count }

  /// Scans `bytes[from...]`, appending line boundaries, until a line start ≥ `until` is reached
  /// (that start is not appended) or the end of the buffer. Returns where scanning stopped.
  @discardableResult
  private static func scan(
    _ bytes: [Byte], from: Int, utf16 start16: Int, until: Int,
    starts: inout [Int], ends: inout [Int], utf16Starts: inout [Int]
  ) -> (Int, Int) {
    var i = from
    var utf16 = start16
    let n = bytes.count
    while i < n {
      let b = bytes[i]
      if b == ASCII.newline || b == ASCII.cr {
        ends.append(i)
        i += 1
        utf16 += 1
        if b == ASCII.cr && i < n && bytes[i] == ASCII.newline { i += 1; utf16 += 1 }
        if i >= until { return (i, utf16) }
        starts.append(i)
        utf16Starts.append(utf16)
      } else if b < 0x80 { i += 1; utf16 += 1 }
      else if b & 0xE0 == 0xC0 { i += 2; utf16 += 1 }
      else if b & 0xF0 == 0xE0 { i += 3; utf16 += 1 }
      else if b & 0xF8 == 0xF0 { i += 4; utf16 += 2 }
      else { i += 1; utf16 += 1 }
    }
    ends.append(n)
    return (n, utf16)
  }

  /// Updates the table for `range` replaced by `replacement`. `bytes` is the new byte array and
  /// `removedUTF16` the UTF-16 length of the removed range (measured before the edit).
  /// Only the touched lines are rescanned; later lines are shifted.
  public mutating func replace(_ range: Range<Int>, with replacement: [Byte], in bytes: [Byte], removedUTF16: Int) {
    let delta = replacement.count - range.count
    let lineA = line(containing: range.lowerBound)
    let lineB = line(containing: range.upperBound)
    let oldNext = lineB + 1 < starts.count ? starts[lineB + 1] : nil  // first untouched line start (old coords)
    let regionEnd = oldNext.map { $0 + delta } ?? Int.max

    var inserted16 = 0
    for b in replacement where b & 0xC0 != 0x80 { inserted16 += b & 0xF8 == 0xF0 ? 2 : 1 }
    let delta16 = inserted16 - removedUTF16

    var region: [Int] = []  // starts of rescanned lines after lineA
    var regionEnds: [Int] = []
    var region16: [Int] = []
    let (stop, _) = Self.scan(bytes, from: starts[lineA], utf16: utf16Starts[lineA], until: regionEnd,
      starts: &region, ends: &regionEnds, utf16Starts: &region16)

    // Old lines after the region are shifted; lines absorbed by the rescan (start < stop) are dropped.
    var m = lineB + 1
    while m < starts.count, starts[m] + delta < stop { m += 1 }
    starts.replaceSubrange((lineA + 1)..<m, with: region)
    utf16Starts.replaceSubrange((lineA + 1)..<m, with: region16)
    ends.replaceSubrange(lineA..<m, with: regionEnds)
    let tail = lineA + 1 + region.count
    if delta != 0 {
      for i in tail..<starts.count { starts[i] += delta; ends[i] += delta }
    }
    if delta16 != 0 {
      for i in tail..<utf16Starts.count { utf16Starts[i] += delta16 }
    }
    assert(starts.count == ends.count && starts.count == utf16Starts.count)
  }

  /// Index of the line containing byte `offset` (offsets at a terminator belong to the line they end).
  public func line(containing offset: Int) -> Int {
    var lo = 0, hi = starts.count - 1
    while lo < hi {
      let mid = (lo + hi + 1) >> 1
      if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
    }
    return lo
  }

  /// Byte offset → UTF-16 offset (walks at most one line).
  public func utf16Offset(forByte offset: Int, in bytes: [Byte]) -> Int {
    let l = line(containing: offset)
    var i = starts[l]
    var u = utf16Starts[l]
    let limit = min(offset, bytes.count)
    while i < limit {
      let b = bytes[i]
      if b < 0x80 { i += 1; u += 1 }
      else if b & 0xE0 == 0xC0 { i += 2; u += 1 }
      else if b & 0xF0 == 0xE0 { i += 3; u += 1 }
      else if b & 0xF8 == 0xF0 { i += 4; u += 2 }
      else { i += 1; u += 1 }
    }
    return u
  }

  /// UTF-16 offset → byte offset (walks at most one line).
  public func byteOffset(forUTF16 offset: Int, in bytes: [Byte]) -> Int {
    var lo = 0, hi = utf16Starts.count - 1
    while lo < hi {
      let mid = (lo + hi + 1) >> 1
      if utf16Starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
    }
    var i = starts[lo]
    var u = utf16Starts[lo]
    while u < offset && i < bytes.count {
      let b = bytes[i]
      if b < 0x80 { i += 1; u += 1 }
      else if b & 0xE0 == 0xC0 { i += 2; u += 1 }
      else if b & 0xF0 == 0xE0 { i += 3; u += 1 }
      else if b & 0xF8 == 0xF0 { i += 4; u += 2 }
      else { i += 1; u += 1 }
    }
    return i
  }
}
