/// Small text utilities: escapes, entities, URL normalisation, label normalisation.
enum Text {
  /// Decodes backslash escapes and entity references in `range` (used for titles, destinations, info strings).
  static func unescapeAndDecode(_ b: [Byte], _ range: Range<Int>) -> String {
    var out = [Byte]()
    out.reserveCapacity(range.count)
    var i = range.lowerBound
    let end = range.upperBound
    while i < end {
      let c = b[i]
      if c == ASCII.backslash, i + 1 < end, b[i + 1].isASCIIPunctuation {
        out.append(b[i + 1]); i += 2
      } else if c == ASCII.amp, let (value, len) = Entity.scan(b, at: i, limit: end) {
        out.append(contentsOf: Array(value.utf8)); i += len
      } else {
        out.append(c); i += 1
      }
    }
    return String(decoding: out, as: UTF8.self)
  }

  static func string(_ b: [Byte], _ range: Range<Int>) -> String {
    String(decoding: b[range], as: UTF8.self)
  }

  /// Link label normalisation (§4.7): case fold, collapse internal whitespace, trim.
  static func normalizeLabel(_ s: String) -> String {
    var out = ""
    var pendingSpace = false
    for ch in s.lowercased().uppercased() {
      if ch.isWhitespace || ch == "\n" {
        pendingSpace = !out.isEmpty
      } else {
        if pendingSpace { out.append(" "); pendingSpace = false }
        out.append(ch)
      }
    }
    return out
  }

  static func escapeHTML(_ s: String, quotes: Bool = true) -> String {
    var out = ""
    out.reserveCapacity(s.utf8.count)
    for ch in s.unicodeScalars {
      switch ch {
      case "&": out += "&amp;"
      case "<": out += "&lt;"
      case ">": out += "&gt;"
      case "\"": out += quotes ? "&quot;" : "\""
      default: out.unicodeScalars.append(ch)
      }
    }
    return out
  }

  /// Percent-encodes a URL the way cmark does: keeps unreserved and reserved characters, encodes the rest,
  /// and leaves already-encoded `%XX` sequences untouched.
  static func encodeURL(_ s: String) -> String {
    var out = ""
    let bytes = Array(s.utf8)
    var i = 0
    while i < bytes.count {
      let c = bytes[i]
      switch c {
      case 0x41...0x5A, 0x61...0x7A, 0x30...0x39,
        0x2D, 0x2E, 0x5F, 0x7E,  // - . _ ~
        0x21, 0x2A, 0x27, 0x28, 0x29,  // ! * ' ( )
        0x3B, 0x2F, 0x3F, 0x3A, 0x40, 0x26, 0x3D, 0x2B, 0x24, 0x2C, 0x23:  // ; / ? : @ & = + $ , #
        out.unicodeScalars.append(Unicode.Scalar(c))
      case 0x25:  // %
        if i + 2 < bytes.count, bytes[i + 1].isHexDigit, bytes[i + 2].isHexDigit {
          out += "%"
        } else {
          out += "%25"
        }
      default:
        out += "%" + hex(c)
      }
      i += 1
    }
    return out
  }

  private static func hex(_ c: Byte) -> String {
    let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    return String([digits[Int(c >> 4)], digits[Int(c & 0xF)]])
  }
}

enum Entity {
  /// Scans an entity reference starting at `i` (which must be `&`). Returns the decoded text and byte length.
  static func scan(_ b: [Byte], at i: Int, limit: Int) -> (String, Int)? {
    guard i + 2 < limit, b[i] == ASCII.amp else { return nil }
    if b[i + 1] == ASCII.hash {
      var j = i + 2
      var value: UInt32 = 0
      var digits = 0
      if j < limit, b[j] | 0x20 == 0x78 {  // x / X
        j += 1
        while j < limit, b[j].isHexDigit, digits < 6 {
          let d = b[j]
          let v: UInt32 = d.isDigit ? UInt32(d - 0x30) : UInt32((d | 0x20) - 0x61 + 10)
          value = value * 16 + v
          digits += 1; j += 1
        }
      } else {
        while j < limit, b[j].isDigit, digits < 7 {
          value = value * 10 + UInt32(b[j] - 0x30)
          digits += 1; j += 1
        }
      }
      guard digits > 0, j < limit, b[j] == ASCII.semicolon else { return nil }
      let scalar: Unicode.Scalar
      if value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) {
        scalar = Unicode.Scalar(0xFFFD)!
      } else {
        scalar = Unicode.Scalar(value) ?? Unicode.Scalar(0xFFFD)!
      }
      return (String(Character(scalar)), j + 1 - i)
    }
    var j = i + 1
    var count = 0
    while j < limit, b[j].isAlphanumeric, count < 32 { j += 1; count += 1 }
    guard count > 0, j < limit, b[j] == ASCII.semicolon else { return nil }
    let name = String(decoding: b[(i + 1)..<j], as: UTF8.self)
    guard let value = EntityTable.map[Substring(name)] else { return nil }
    return (value, j + 1 - i)
  }
}
