/// Syntax highlighting for fenced code blocks: a single-pass tokenizer driven by small language
/// descriptions. Works on UTF-8 bytes, allocates nothing per byte, and never fails: unknown input
/// is simply left plain.

/// What a token is, for colouring. Plain text is not a token.
public enum TokenKind: UInt8, Sendable, CaseIterable {
  case keyword, type, constant, string, number, comment, function, variable, attribute, tag, property
  case meta, heading, inserted, deleted

  /// CSS class name used by HTML export (`tk-keyword`, …).
  public var cssClass: String { "tk-\(self)" }
}

/// A highlighted span; `range` indexes the code bytes handed to the highlighter.
public struct Token: Sendable, Equatable {
  public var kind: TokenKind
  public var range: Range<Int>

  public init(kind: TokenKind, range: Range<Int>) {
    self.kind = kind
    self.range = range
  }
}
