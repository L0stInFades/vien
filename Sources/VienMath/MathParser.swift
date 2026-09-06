import Foundation

/// TeX math subset → tree. Covers what people write in Markdown: fractions, roots, scripts, sums and
/// integrals, delimiters, accents, matrices/cases/aligned, text, font styles, Greek and symbols.
indirect enum MathNode: Sendable, Equatable {
  enum Atom: Sendable { case ord, op, bin, rel, open, close, punct, inner }
  enum Variant: Sendable { case italic, upright, bold, boldItalic, doubleStruck, script, fraktur, sans, mono }
  enum Style: Sendable { case display, text, script, scriptScript }

  /// One glyph (a letter, digit or symbol) with its spacing class.
  case symbol(String, Atom, Variant)
  /// Upright text (from `\text{}` / `\operatorname{}`), or a named operator like `lim`.
  case text(String, isOperator: Bool)
  case row([MathNode])
  case scripts(base: MathNode, sub: MathNode?, sup: MathNode?, limits: Bool)
  case fraction(num: MathNode, den: MathNode, rule: Bool)
  case root(body: MathNode, index: MathNode?)
  /// `\left … \right`; nil delimiter means `.`
  case fenced(left: String?, body: MathNode, right: String?)
  case accent(String, body: MathNode, wide: Bool)
  case overline(MathNode)
  case underline(MathNode)
  case space(em: Double)
  case table(rows: [[MathNode]], env: String)
  case style(Style, MathNode)
  case boxed(MathNode)
  case phantom(MathNode, keepWidth: Bool, keepHeight: Bool)
  case error(String)
}

public struct MathSyntaxError: Error, CustomStringConvertible, Sendable {
  public let description: String
}

struct MathParser {
  private let chars: [Character]
  private var i = 0

  init(_ source: String) { chars = Array(source) }

  static func parse(_ source: String) throws -> MathNode {
    var p = MathParser(source)
    let node = try p.parseList(until: nil)
    if p.i < p.chars.count { throw MathSyntaxError(description: "unexpected “\(p.chars[p.i])”") }
    return node
  }

  // MARK: - Tokens

  private enum Token: Equatable {
    case command(String)
    case char(Character)
    case open, close, sup, sub, ampersand, newline
    case end
  }

  private mutating func skipSpaces() { while i < chars.count, chars[i].isWhitespace { i += 1 } }

  private mutating func next() -> Token {
    skipSpaces()
    guard i < chars.count else { return .end }
    let c = chars[i]
    i += 1
    switch c {
    case "{": return .open
    case "}": return .close
    case "^": return .sup
    case "_": return .sub
    case "&": return .ampersand
    case "\\":
      guard i < chars.count else { return .command("\\") }
      let n = chars[i]
      if n.isLetter {
        var name = ""
        while i < chars.count, chars[i].isLetter { name.append(chars[i]); i += 1 }
        // `\operatorname*` style star suffix.
        if i < chars.count, chars[i] == "*", name == "operatorname" { i += 1 }
        return .command(name)
      }
      i += 1
      if n == "\\" { return .newline }
      return .command(String(n))
    default: return .char(c)
    }
  }

  private func peekToken() -> Token {
    var copy = self
    return copy.next()
  }

  // MARK: - Lists and groups

  /// Parses nodes until `until` (a closing token) or end; the closing token is consumed.
  private mutating func parseList(until: Token?) throws -> MathNode {
    var items: [MathNode] = []
    while true {
      let save = i
      let t = next()
      if t == .end {
        if let until, until != .end { throw MathSyntaxError(description: "missing “\(until == .close ? "}" : "\\right")”") }
        break
      }
      if let until, t == until { break }
      if t == .close { throw MathSyntaxError(description: "unexpected “}”") }
      if t == .ampersand || t == .newline { i = save; break }
      if case .command(let name) = t, name == "right" || name == "end" { i = save; break }
      i = save
      if let node = try parseAtomWithScripts() { items.append(node) }
    }
    return items.count == 1 ? items[0] : .row(items)
  }

  /// A group `{…}` or a single atom.
  private mutating func parseArgument() throws -> MathNode {
    let t = next()
    switch t {
    case .open: return try parseList(until: .close)
    case .end: throw MathSyntaxError(description: "missing argument")
    default:
      i -= tokenLength(t)
      return try parseAtom() ?? .row([])
    }
  }

  private func tokenLength(_ t: Token) -> Int {
    switch t {
    case .command(let n): return n.count + 1 + (n == "operatorname" && i > 0 && chars[i - 1] == "*" ? 1 : 0)
    case .newline: return 2
    default: return 1
    }
  }

  private mutating func optionalBracketArgument() throws -> MathNode? {
    skipSpaces()
    guard i < chars.count, chars[i] == "[" else { return nil }
    i += 1
    var depth = 0
    var inner: [Character] = []
    while i < chars.count {
      let c = chars[i]
      if c == "[" { depth += 1 } else if c == "]" { if depth == 0 { break }; depth -= 1 }
      inner.append(c)
      i += 1
    }
    i += 1
    return try MathParser.parse(String(inner))
  }

  private mutating func parseBraceText() throws -> String {
    skipSpaces()
    guard i < chars.count, chars[i] == "{" else {
      // Single character argument.
      guard i < chars.count else { return "" }
      let c = chars[i]; i += 1
      return String(c)
    }
    i += 1
    var depth = 0
    var out = ""
    while i < chars.count {
      let c = chars[i]
      if c == "{" { depth += 1 } else if c == "}" { if depth == 0 { i += 1; return out }; depth -= 1 }
      out.append(c)
      i += 1
    }
    throw MathSyntaxError(description: "missing “}”")
  }

  private mutating func parseAtomWithScripts() throws -> MathNode? {
    guard var base = try parseAtom() else { return nil }
    var sub: MathNode? = nil, sup: MathNode? = nil
    var limits = false
    if case .symbol(_, .op, _) = base { limits = true }
    if case .text(_, true) = base { limits = MathParser.limitOperators.contains(textOf(base)) }
    loop: while true {
      let save = i
      let t = next()
      switch t {
      case .sup:
        guard sup == nil else { throw MathSyntaxError(description: "double superscript") }
        sup = try parseArgument()
      case .sub:
        guard sub == nil else { throw MathSyntaxError(description: "double subscript") }
        sub = try parseArgument()
      case .command("limits"): limits = true
      case .command("nolimits"): limits = false
      case .char("'"):
        // Primes become superscripts.
        var count = 1
        while i < chars.count, chars[i] == "'" { count += 1; i += 1 }
        let prime = MathNode.symbol(String(repeating: "′", count: count), .ord, .upright)
        sup = sup.map { .row([prime, $0]) } ?? prime
      default:
        i = save
        break loop
      }
    }
    if sub != nil || sup != nil {
      if case .symbol("∫", _, _) = base { limits = false }
      base = .scripts(base: base, sub: sub, sup: sup, limits: limits)
    }
    return base
  }

  private func textOf(_ n: MathNode) -> String { if case .text(let s, _) = n { return s }; return "" }

  static let limitOperators: Set<String> = ["lim", "max", "min", "sup", "inf", "det", "gcd", "Pr", "limsup", "liminf", "argmax", "argmin"]

  // MARK: - Atoms

  private mutating func parseAtom() throws -> MathNode? {
    let t = next()
    switch t {
    case .end: return nil
    case .open: return try parseList(until: .close)
    case .close: throw MathSyntaxError(description: "unexpected “}”")
    case .sup, .sub: throw MathSyntaxError(description: "missing base for script")
    case .ampersand: throw MathSyntaxError(description: "“&” outside a matrix")
    case .newline: throw MathSyntaxError(description: "“\\\\” outside a matrix")
    case .char(let c): return charNode(c)
    case .command(let name): return try commandNode(name)
    }
  }

  private func charNode(_ c: Character) -> MathNode {
    let s = String(c)
    if c.isNumber { return .symbol(s, .ord, .upright) }
    if c.isLetter { return .symbol(s, .ord, .italic) }
    switch c {
    case "+", "−", "-", "*", "×", "·", "∘": return .symbol(c == "-" ? "−" : c == "*" ? "∗" : s, .bin, .upright)
    case "=", "<", ">", "≤", "≥", "≠", "≈", "→", "←", "↔", "∈", "∼", "≡", "⊂", "⊃", "∝", ":": return .symbol(s, .rel, .upright)
    case "(", "[", "⟨", "⌊", "⌈": return .symbol(s, .open, .upright)
    case ")", "]", "⟩", "⌋", "⌉": return .symbol(s, .close, .upright)
    case ",", ";": return .symbol(s, .punct, .upright)
    case "|": return .symbol("|", .ord, .upright)
    case "/": return .symbol("/", .ord, .upright)
    case "!", "?", ".", "'", "\"", "%", "#", "@", "`", "~": return .symbol(s, .ord, .upright)
    default: return .symbol(s, .ord, .upright)
    }
  }

  private mutating func commandNode(_ name: String) throws -> MathNode {
    switch name {
    case "frac", "dfrac", "tfrac", "cfrac":
      let n = try parseArgument(), d = try parseArgument()
      let f = MathNode.fraction(num: n, den: d, rule: true)
      return name == "dfrac" ? .style(.display, f) : name == "tfrac" ? .style(.text, f) : f
    case "binom", "dbinom", "tbinom":
      let n = try parseArgument(), d = try parseArgument()
      return .fenced(left: "(", body: .fraction(num: n, den: d, rule: false), right: ")")
    case "sqrt":
      let index = try optionalBracketArgument()
      return .root(body: try parseArgument(), index: index)
    case "left":
      let l = try delimiter()
      let body = try parseList(until: .command("right"))
      let r = try delimiter()
      return .fenced(left: l, body: body, right: r)
    case "right": throw MathSyntaxError(description: "“\\right” without “\\left”")
    case "text", "textrm", "textit", "textbf", "textsf", "texttt", "mbox", "hbox":
      let s = try parseBraceText()
      return .text(s, isOperator: false)
    case "operatorname":
      let s = try parseBraceText()
      return .text(s, isOperator: true)
    case "mathrm", "mathbf", "mathit", "mathbb", "mathcal", "mathfrak", "mathsf", "mathtt", "boldsymbol", "bm", "mathscr", "mathnormal", "textnormal":
      let variant: MathNode.Variant = switch name {
      case "mathrm", "textnormal": .upright
      case "mathbf": .bold
      case "mathit", "mathnormal": .italic
      case "mathbb": .doubleStruck
      case "mathcal", "mathscr": .script
      case "mathfrak": .fraktur
      case "mathsf": .sans
      case "mathtt": .mono
      default: .boldItalic
      }
      return restyle(try parseArgument(), variant)
    case "hat", "bar", "vec", "dot", "ddot", "tilde", "breve", "check", "acute", "grave", "mathring", "widehat", "widetilde", "overrightarrow", "overleftarrow", "overline", "underline":
      let body = try parseArgument()
      switch name {
      case "overline": return .overline(body)
      case "underline": return .underline(body)
      default:
        let accents: [String: String] = ["hat": "\u{0302}", "widehat": "\u{0302}", "bar": "\u{0304}", "vec": "\u{20D7}", "overrightarrow": "\u{20D7}", "overleftarrow": "\u{20D6}", "dot": "\u{0307}", "ddot": "\u{0308}", "tilde": "\u{0303}", "widetilde": "\u{0303}", "breve": "\u{0306}", "check": "\u{030C}", "acute": "\u{0301}", "grave": "\u{0300}", "mathring": "\u{030A}"]
        return .accent(accents[name] ?? "\u{0302}", body: body, wide: name.hasPrefix("wide") || name.hasPrefix("over"))
      }
    case "overset":
      let top = try parseArgument(), base = try parseArgument()
      return .scripts(base: base, sub: nil, sup: top, limits: true)
    case "underset":
      let bottom = try parseArgument(), base = try parseArgument()
      return .scripts(base: base, sub: bottom, sup: nil, limits: true)
    case "stackrel":
      let top = try parseArgument(), base = try parseArgument()
      return .scripts(base: base, sub: nil, sup: top, limits: true)
    case "displaystyle": return .style(.display, try parseList(until: .close).thenRestoreBrace(&self))
    case "textstyle": return .style(.text, try parseList(until: .close).thenRestoreBrace(&self))
    case "scriptstyle": return .style(.script, try parseList(until: .close).thenRestoreBrace(&self))
    case "scriptscriptstyle": return .style(.scriptScript, try parseList(until: .close).thenRestoreBrace(&self))
    case "boxed": return .boxed(try parseArgument())
    case "phantom": return .phantom(try parseArgument(), keepWidth: true, keepHeight: true)
    case "hphantom": return .phantom(try parseArgument(), keepWidth: true, keepHeight: false)
    case "vphantom": return .phantom(try parseArgument(), keepWidth: false, keepHeight: true)
    case "color", "textcolor": _ = try parseBraceText(); return try parseArgument()
    case "begin":
      let env = try parseBraceText()
      return try parseEnvironment(env)
    case "end": throw MathSyntaxError(description: "“\\end” without “\\begin”")
    case ",": return .space(em: 3.0 / 18)
    case ":", ">": return .space(em: 4.0 / 18)
    case ";": return .space(em: 5.0 / 18)
    case "!": return .space(em: -3.0 / 18)
    case " ", "space": return .space(em: 0.33)
    case "quad": return .space(em: 1)
    case "qquad": return .space(em: 2)
    case "hspace":
      let s = try parseBraceText()
      let n = Double(s.filter { "0123456789.-".contains($0) }) ?? 0
      return .space(em: s.hasSuffix("em") ? n : n / 10)
    case "not":
      let arg = try parseArgument()
      if case .symbol(let s, let a, let v) = arg { return .symbol(s + "\u{0338}", a, v) }
      return arg
    case "pmod":
      let a = try parseArgument()
      return .row([.space(em: 1), .symbol("(", .open, .upright), .text("mod", isOperator: true), .space(em: 0.33), a, .symbol(")", .close, .upright)])
    case "bmod": return .text("mod", isOperator: true)
    case "big", "Big", "bigg", "Bigg", "bigl", "Bigl", "biggl", "Biggl", "bigr", "Bigr", "biggr", "Biggr", "bigm", "Bigm", "biggm", "Biggm":
      let d = try delimiter() ?? "."
      let size = name.hasPrefix("Bigg") ? 4.0 : name.hasPrefix("bigg") ? 3.0 : name.hasPrefix("Big") ? 2.0 : 1.5
      return .fenced(left: nil, body: .style(.display, .symbol(d, name.hasSuffix("r") ? .close : .open, .upright)), right: nil).sized(size)
    case "\\": return .row([])
    case "{": return .symbol("{", .open, .upright)
    case "}": return .symbol("}", .close, .upright)
    case "|": return .symbol("‖", .ord, .upright)
    case "_": return .symbol("_", .ord, .upright)
    case "&": return .symbol("&", .ord, .upright)
    case "#": return .symbol("#", .ord, .upright)
    case "%": return .symbol("%", .ord, .upright)
    case "$": return .symbol("$", .ord, .upright)
    default:
      if let sym = MathSymbols.table[name] { return .symbol(sym.0, sym.1, .upright) }
      if let g = MathSymbols.greek[name] { return .symbol(g, .ord, name.first!.isUppercase ? .upright : .italic) }
      if MathSymbols.functions.contains(name) { return .text(name, isOperator: true) }
      throw MathSyntaxError(description: "unknown command “\\\(name)”")
    }
  }

  private mutating func delimiter() throws -> String? {
    skipSpaces()
    let t = next()
    switch t {
    case .char("."): return nil
    case .char(let c): return String(c)
    case .command(let n):
      let map: [String: String] = ["{": "{", "}": "}", "|": "‖", "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉", "vert": "|", "Vert": "‖", "lvert": "|", "rvert": "|", "lVert": "‖", "rVert": "‖", "backslash": "\\", "uparrow": "↑", "downarrow": "↓", "updownarrow": "↕"]
      guard let d = map[n] else { throw MathSyntaxError(description: "“\\\(n)” is not a delimiter") }
      return d
    default: throw MathSyntaxError(description: "expected a delimiter")
    }
  }

  private mutating func parseEnvironment(_ env: String) throws -> MathNode {
    var rows: [[MathNode]] = [[]]
    let name = env.replacingOccurrences(of: "*", with: "")
    if name == "array" { _ = try parseBraceText() }  // column spec
    loop: while true {
      let cell = try parseList(until: nil)
      rows[rows.count - 1].append(cell)
      let t = next()
      switch t {
      case .ampersand: continue
      case .newline:
        _ = try optionalBracketArgument()  // \\[2pt]
        rows.append([])
      case .command("end"):
        let e = try parseBraceText()
        guard e.replacingOccurrences(of: "*", with: "") == name else { throw MathSyntaxError(description: "\\begin{\(env)} closed by \\end{\(e)}") }
        break loop
      case .end: throw MathSyntaxError(description: "missing \\end{\(env)}")
      default: throw MathSyntaxError(description: "unexpected token in \(env)")
      }
    }
    if let last = rows.last, last.count == 1, last[0] == .row([]) { rows.removeLast() }
    let table = MathNode.table(rows: rows, env: name)
    switch name {
    case "pmatrix": return .fenced(left: "(", body: table, right: ")")
    case "bmatrix": return .fenced(left: "[", body: table, right: "]")
    case "Bmatrix": return .fenced(left: "{", body: table, right: "}")
    case "vmatrix": return .fenced(left: "|", body: table, right: "|")
    case "Vmatrix": return .fenced(left: "‖", body: table, right: "‖")
    case "cases": return .fenced(left: "{", body: table, right: nil)
    default: return table
    }
  }

  private func restyle(_ node: MathNode, _ v: MathNode.Variant) -> MathNode {
    switch node {
    case .symbol(let s, let a, _): return .symbol(s, a, v)
    case .row(let items): return .row(items.map { restyle($0, v) })
    case .scripts(let b, let sub, let sup, let l): return .scripts(base: restyle(b, v), sub: sub, sup: sup, limits: l)
    default: return node
    }
  }
}

private extension MathNode {
  /// `\displaystyle` applies to the rest of the enclosing group: the list was parsed up to the
  /// group's closing brace, which must be handed back to the caller.
  func thenRestoreBrace(_ p: inout MathParser) -> MathNode {
    p.restoreClosingBrace()
    return self
  }

  func sized(_ scale: Double) -> MathNode {
    if case .fenced(_, let body, _) = self, case .style(_, let inner) = body, case .symbol(let s, let a, let v) = inner {
      return .symbol(s, a, v).bigDelimiter(scale)
    }
    return self
  }

  func bigDelimiter(_ scale: Double) -> MathNode {
    // Represented as a fenced node with a synthetic scale hint in `env`.
    .table(rows: [[self]], env: "bigdelim:\(scale)")
  }
}

extension MathParser {
  fileprivate mutating func restoreClosingBrace() {
    // parseList(until: .close) consumed the `}` (or reached the end); step back over it so the
    // enclosing group closes normally.
    if i > 0, chars[i - 1] == "}" { i -= 1 }
  }
}

enum MathSymbols {
  static let greek: [String: String] = [
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ", "eta": "η",
    "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο",
    "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ",
    "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
    "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ",
    "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
  ]

  static let functions: Set<String> = [
    "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth", "log", "ln", "lg",
    "exp", "lim", "limsup", "liminf", "max", "min", "sup", "inf", "det", "gcd", "deg", "dim", "ker", "hom", "arg", "Pr", "mod",
    "argmax", "argmin",
  ]

  static let table: [String: (String, MathNode.Atom)] = [
    "sum": ("∑", .op), "prod": ("∏", .op), "coprod": ("∐", .op), "int": ("∫", .op), "iint": ("∬", .op), "iiint": ("∭", .op),
    "oint": ("∮", .op), "bigcup": ("⋃", .op), "bigcap": ("⋂", .op), "bigoplus": ("⨁", .op), "bigotimes": ("⨂", .op),
    "bigvee": ("⋁", .op), "bigwedge": ("⋀", .op), "bigsqcup": ("⨆", .op),
    "infty": ("∞", .ord), "partial": ("∂", .ord), "nabla": ("∇", .ord), "hbar": ("ℏ", .ord), "ell": ("ℓ", .ord),
    "Re": ("ℜ", .ord), "Im": ("ℑ", .ord), "aleph": ("ℵ", .ord), "wp": ("℘", .ord), "emptyset": ("∅", .ord),
    "varnothing": ("∅", .ord), "prime": ("′", .ord), "angle": ("∠", .ord), "triangle": ("△", .ord), "square": ("□", .ord),
    "forall": ("∀", .ord), "exists": ("∃", .ord), "nexists": ("∄", .ord), "neg": ("¬", .ord), "lnot": ("¬", .ord),
    "top": ("⊤", .ord), "bot": ("⊥", .ord), "ldots": ("…", .inner), "cdots": ("⋯", .inner), "vdots": ("⋮", .ord),
    "ddots": ("⋱", .inner), "dots": ("…", .inner), "dotsc": ("…", .inner), "dotsb": ("⋯", .inner), "degree": ("°", .ord),
    "dagger": ("†", .bin), "ddagger": ("‡", .bin), "checkmark": ("✓", .ord), "star": ("⋆", .bin),
    "cdot": ("⋅", .bin), "times": ("×", .bin), "div": ("÷", .bin), "pm": ("±", .bin), "mp": ("∓", .bin), "ast": ("∗", .bin),
    "circ": ("∘", .bin), "bullet": ("∙", .bin), "oplus": ("⊕", .bin), "ominus": ("⊖", .bin), "otimes": ("⊗", .bin),
    "odot": ("⊙", .bin), "cup": ("∪", .bin), "cap": ("∩", .bin), "setminus": ("∖", .bin), "wedge": ("∧", .bin),
    "vee": ("∨", .bin), "land": ("∧", .bin), "lor": ("∨", .bin), "sqcup": ("⊔", .bin), "sqcap": ("⊓", .bin),
    "amalg": ("⨿", .bin), "diamond": ("⋄", .bin), "wr": ("≀", .bin), "uplus": ("⊎", .bin),
    "leq": ("≤", .rel), "le": ("≤", .rel), "geq": ("≥", .rel), "ge": ("≥", .rel), "neq": ("≠", .rel), "ne": ("≠", .rel),
    "approx": ("≈", .rel), "equiv": ("≡", .rel), "sim": ("∼", .rel), "simeq": ("≃", .rel), "cong": ("≅", .rel),
    "propto": ("∝", .rel), "ll": ("≪", .rel), "gg": ("≫", .rel), "prec": ("≺", .rel), "succ": ("≻", .rel),
    "preceq": ("⪯", .rel), "succeq": ("⪰", .rel), "subset": ("⊂", .rel), "supset": ("⊃", .rel), "subseteq": ("⊆", .rel),
    "supseteq": ("⊇", .rel), "subsetneq": ("⊊", .rel), "in": ("∈", .rel), "notin": ("∉", .rel), "ni": ("∋", .rel),
    "mid": ("∣", .rel), "nmid": ("∤", .rel), "parallel": ("∥", .rel), "perp": ("⊥", .rel), "models": ("⊨", .rel),
    "vdash": ("⊢", .rel), "dashv": ("⊣", .rel), "asymp": ("≍", .rel), "bowtie": ("⋈", .rel), "doteq": ("≐", .rel),
    "to": ("→", .rel), "rightarrow": ("→", .rel), "leftarrow": ("←", .rel), "leftrightarrow": ("↔", .rel),
    "Rightarrow": ("⇒", .rel), "Leftarrow": ("⇐", .rel), "Leftrightarrow": ("⇔", .rel), "implies": ("⟹", .rel),
    "impliedby": ("⟸", .rel), "iff": ("⟺", .rel), "mapsto": ("↦", .rel), "longrightarrow": ("⟶", .rel),
    "longleftarrow": ("⟵", .rel), "longmapsto": ("⟼", .rel), "uparrow": ("↑", .rel), "downarrow": ("↓", .rel),
    "updownarrow": ("↕", .rel), "Uparrow": ("⇑", .rel), "Downarrow": ("⇓", .rel), "nearrow": ("↗", .rel),
    "searrow": ("↘", .rel), "swarrow": ("↙", .rel), "nwarrow": ("↖", .rel), "hookrightarrow": ("↪", .rel),
    "hookleftarrow": ("↩", .rel), "rightharpoonup": ("⇀", .rel), "leftharpoonup": ("↼", .rel), "rightleftharpoons": ("⇌", .rel),
    "therefore": ("∴", .rel), "because": ("∵", .rel), "colon": (":", .punct),
    "langle": ("⟨", .open), "rangle": ("⟩", .close), "lfloor": ("⌊", .open), "rfloor": ("⌋", .close), "lceil": ("⌈", .open),
    "rceil": ("⌉", .close), "lvert": ("|", .open), "rvert": ("|", .close), "lVert": ("‖", .open), "rVert": ("‖", .close),
    "vert": ("|", .ord), "Vert": ("‖", .ord), "lbrace": ("{", .open), "rbrace": ("}", .close), "lbrack": ("[", .open), "rbrack": ("]", .close),
    "backslash": ("\\", .ord), "surd": ("√", .ord), "S": ("§", .ord), "P": ("¶", .ord), "copyright": ("©", .ord),
    "pounds": ("£", .ord), "yen": ("¥", .ord), "euro": ("€", .ord), "AA": ("Å", .ord), "mho": ("℧", .ord),
    "clubsuit": ("♣", .ord), "diamondsuit": ("♢", .ord), "heartsuit": ("♡", .ord), "spadesuit": ("♠", .ord),
    "flat": ("♭", .ord), "natural": ("♮", .ord), "sharp": ("♯", .ord), "blacksquare": ("■", .ord), "qed": ("∎", .ord),
    "cdotp": ("⋅", .punct), "ldotp": (".", .punct),
  ]
}
