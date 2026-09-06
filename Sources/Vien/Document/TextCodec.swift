import Foundation

/// Reads and writes document bytes without normalising them: the encoding, byte-order mark and line
/// endings a file arrived with are the ones it is saved with, unless the user changes them.
nonisolated struct TextCodec: Equatable {
  var encoding: String.Encoding = .utf8
  var hasBOM = false

  enum LineEnding: String, CaseIterable { case lf = "\n", crlf = "\r\n", cr = "\r" }

  static func decode(_ data: Data) -> (String, TextCodec)? {
    var codec = TextCodec()
    var body = data
    if data.starts(with: [0xEF, 0xBB, 0xBF]) {
      codec.hasBOM = true
      body = data.dropFirst(3)
    } else if data.starts(with: [0xFF, 0xFE]) {
      codec = TextCodec(encoding: .utf16LittleEndian, hasBOM: true)
      body = data.dropFirst(2)
    } else if data.starts(with: [0xFE, 0xFF]) {
      codec = TextCodec(encoding: .utf16BigEndian, hasBOM: true)
      body = data.dropFirst(2)
    }
    if let s = String(data: body, encoding: codec.encoding) { return (s, codec) }
    // Not valid in the guessed encoding: let Foundation sniff, then fall back to Latin-1 (never fails).
    var converted: NSString? = nil
    let sniffed = NSString.stringEncoding(for: body, encodingOptions: [.suggestedEncodingsKey: [NSUTF8StringEncoding, NSWindowsCP1252StringEncoding, NSISOLatin1StringEncoding]], convertedString: &converted, usedLossyConversion: nil)
    if sniffed != 0, let converted {
      return (converted as String, TextCodec(encoding: String.Encoding(rawValue: sniffed), hasBOM: false))
    }
    return String(data: body, encoding: .isoLatin1).map { ($0, TextCodec(encoding: .isoLatin1, hasBOM: false)) }
  }

  func encode(_ text: String) -> Data? {
    guard var data = text.data(using: encoding, allowLossyConversion: false) else { return nil }
    if hasBOM {
      switch encoding {
      case .utf8: data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
      case .utf16LittleEndian: data.insert(contentsOf: [0xFF, 0xFE], at: 0)
      case .utf16BigEndian: data.insert(contentsOf: [0xFE, 0xFF], at: 0)
      default: break
      }
    }
    return data
  }

  /// Dominant line ending of `text`, nil when it has none.
  static func detectLineEnding(_ text: String) -> LineEnding? {
    var lf = 0, crlf = 0, cr = 0
    var previousCR = false
    for u in text.utf8 {
      if u == 0x0A { if previousCR { crlf += 1 } else { lf += 1 }; previousCR = false }
      else { if previousCR { cr += 1 }; previousCR = u == 0x0D }
    }
    if previousCR { cr += 1 }
    let best = max(lf, crlf, cr)
    if best == 0 { return nil }
    return best == lf ? .lf : best == crlf ? .crlf : .cr
  }

  static func convert(_ text: String, to ending: LineEnding) -> String {
    var out = ""
    out.reserveCapacity(text.utf8.count)
    var scalars = text.unicodeScalars.makeIterator()
    var pending: Unicode.Scalar? = scalars.next()
    while let s = pending {
      pending = scalars.next()
      if s == "\r" {
        if pending == "\n" { pending = scalars.next() }
        out += ending.rawValue
      } else if s == "\n" {
        out += ending.rawValue
      } else {
        out.unicodeScalars.append(s)
      }
    }
    return out
  }
}
