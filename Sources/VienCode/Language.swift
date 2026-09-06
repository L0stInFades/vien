/// A language is data: which words are keywords, how comments and strings look, and a flavour for
/// the few syntaxes (markup, CSS, diff, YAML, …) that need more than words.
public struct Language: Sendable {
  public enum Flavor: Sendable { case generic, markup, css, diff, markdown, yaml, shell, makefile, json, toml }

  public struct StringRule: Sendable {
    public var open: String
    public var close: String
    public var multiline: Bool
    public var escapes: Bool
    public init(_ open: String, _ close: String? = nil, multiline: Bool = false, escapes: Bool = true) {
      self.open = open
      self.close = close ?? open
      self.multiline = multiline
      self.escapes = escapes
    }
  }

  public var name: String
  public var flavor: Flavor = .generic
  public var keywords: Set<String> = []
  public var types: Set<String> = []
  public var constants: Set<String> = []
  public var builtins: Set<String> = []
  public var lineComments: [String] = []
  public var blockComments: [(String, String)] = []
  public var nestedComments = false
  public var strings: [StringRule] = []
  /// Identifier prefixes that turn a following quote into a string (`r"…"`, `f"…"`, `b'…'`).
  public var stringPrefixes: Set<String> = []
  /// `#"…"#` / `r#"…"#` raw strings: the number of hashes around the quotes must match.
  public var hashRawStrings = false
  /// `'x'` is a character literal (otherwise `'` is plain, e.g. Rust lifetimes fall through).
  public var charLiterals = false
  /// `#directive` at the start of a line is meta (C family).
  public var preprocessor = false
  /// `#name` anywhere is a keyword (Swift `#if`, `#available`).
  public var hashKeywords = false
  /// A `'` right after a value (identifier, `)`, `]`, `}`, digit or `'`) is an operator (MATLAB transpose).
  public var postfixQuote = false
  /// A `\command` (letters, or a single non-letter) is a keyword (TeX, some macro languages).
  public var backslashCommands = false
  /// Token kind for `@name` (attributes, decorators, Ruby instance variables).
  public var atPrefix: TokenKind? = nil
  /// Token kind for `$name` / `${name}`.
  public var dollarPrefix: TokenKind? = nil
  /// Capitalised identifiers are types; ALL_CAPS identifiers are constants.
  public var capitalizedTypes = false
  public var upperConstants = false
  /// An identifier directly followed by `(` is a function.
  public var functionCalls = true
  /// Extra bytes allowed inside identifiers (`-` for CSS and Lisp, `?`/`!` for Ruby, `$` for JS).
  public var identifierExtras: Set<UInt8> = []
  /// keywords ∪ constants ∪ types ∪ builtins, keyed by an FNV-1a hash of the bytes so lookups
  /// need no String; resolved once per language.
  var words: [UInt64: [(bytes: [UInt8], kind: TokenKind)]] = [:]
  var stringPrefixMaxLength = 0

  /// FNV-1a over the bytes; the scanner computes the same while it reads an identifier.
  static func hash(_ bytes: some Sequence<UInt8>) -> UInt64 {
    var h: UInt64 = 0xCBF29CE484222325
    for b in bytes { h = (h ^ UInt64(b)) &* 0x100000001B3 }
    return h
  }

  /// The kind of a word, or nil when it is not a known word.
  func kind(ofWord bytes: ArraySlice<UInt8>, hash: UInt64) -> TokenKind? {
    guard let candidates = words[hash] else { return nil }
    for c in candidates where c.bytes.count == bytes.count && c.bytes.elementsEqual(bytes) { return c.kind }
    return nil
  }

  public init(name: String) { self.name = name }

  /// The language with `words` filled in (keywords win over constants, types and builtins).
  func resolved() -> Language {
    var l = self
    var map: [UInt64: [(bytes: [UInt8], kind: TokenKind)]] = [:]
    func put(_ set: Set<String>, _ kind: TokenKind) {
      for w in set {
        let bytes = Array(w.utf8)
        let h = Self.hash(bytes)
        if let i = map[h]?.firstIndex(where: { $0.bytes == bytes }) { map[h]![i].kind = kind } else { map[h, default: []].append((bytes, kind)) }
      }
    }
    put(builtins, .function)
    put(types, .type)
    put(constants, .constant)
    put(keywords, .keyword)
    l.words = map
    l.stringPrefixMaxLength = stringPrefixes.map { $0.utf8.count }.max() ?? 0
    return l
  }

  static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
}

extension Language {
  /// The language for a fence info string (`swift`, `c++`, `js`, `sh`, …), or nil to leave the block plain.
  public static func named(_ alias: String) -> Language? {
    var key = alias.lowercased()
    if key.hasPrefix(".") { key.removeFirst() }
    if let canonical = aliases[key] { key = canonical }
    return table[key]
  }

  public static var names: [String] { table.keys.sorted() }

  private static let aliases: [String: String] = [
    "c++": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "h": "c", "objc": "objectivec", "objective-c": "objectivec",
    "obj-c": "objectivec", "mm": "objectivec", "cs": "csharp", "c#": "csharp", "kt": "kotlin", "kts": "kotlin", "golang": "go",
    "rs": "rust", "py": "python", "python3": "python", "rb": "ruby", "js": "javascript", "jsx": "javascript", "mjs": "javascript",
    "cjs": "javascript", "node": "javascript", "ts": "typescript", "tsx": "typescript", "json5": "json", "jsonc": "json",
    "yml": "yaml", "htm": "html", "xhtml": "html", "vue": "html", "svelte": "html", "svg": "xml", "plist": "xml", "xsl": "xml",
    "xsd": "xml", "scss": "css", "less": "css", "mysql": "sql", "postgresql": "sql", "postgres": "sql", "pgsql": "sql",
    "sqlite": "sql", "plsql": "sql", "sh": "bash", "zsh": "bash", "shell": "bash", "console": "bash", "shell-session": "bash",
    "fish": "bash", "ps1": "powershell", "pwsh": "powershell", "docker": "dockerfile", "make": "makefile", "mk": "makefile",
    "patch": "diff", "md": "markdown", "mkd": "markdown", "pl": "perl", "hs": "haskell", "ex": "elixir", "exs": "elixir",
    "erl": "erlang", "clj": "clojure", "cljs": "clojure", "edn": "clojure", "scheme": "lisp", "racket": "lisp", "elisp": "lisp",
    "emacs-lisp": "lisp", "tex": "latex", "gql": "graphql", "proto": "protobuf", "cfg": "ini", "conf": "ini", "properties": "ini",
    "jl": "julia", "m": "matlab", "octave": "matlab", "f90": "fortran", "f": "fortran", "vimscript": "vim", "viml": "vim",
    "zsh-session": "bash", "bat": "batch", "cmd": "batch", "dockerfile.": "dockerfile",
  ]

  private static let table: [String: Language] = {
    var t: [String: Language] = [:]
    func add(_ l: Language) { t[l.name] = l.resolved() }

    let cComments: [(String, String)] = [("/*", "*/")]
    let cStrings = [StringRule("\""), StringRule("'")]

    var swift = Language(name: "swift")
    swift.keywords = words("""
      associatedtype class deinit enum extension func import init inout internal let operator private fileprivate \
      protocol public open rethrows static struct subscript typealias var break case continue default defer do else \
      fallthrough for guard if in repeat return switch where while as Any catch is nil super self Self throw throws \
      try async await actor some any macro consuming borrowing nonisolated isolated package convenience dynamic final \
      indirect lazy mutating nonmutating optional override required unowned weak willSet didSet get set precedencegroup \
      infix prefix postfix each
      """)
    swift.types = words("Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Float Double Bool String Character Array Dictionary Set Optional Result Error Void Never AnyObject Sendable Codable Equatable Hashable Comparable Identifiable")
    swift.constants = words("true false nil")
    swift.lineComments = ["//"]
    swift.blockComments = cComments
    swift.nestedComments = true
    swift.strings = [StringRule("\"\"\"", multiline: true), StringRule("\"")]
    swift.hashRawStrings = true
    swift.hashKeywords = true
    swift.atPrefix = .attribute
    swift.capitalizedTypes = true
    add(swift)

    var c = Language(name: "c")
    c.keywords = words("auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch typedef union volatile while _Alignas _Alignof _Atomic _Generic _Noreturn _Static_assert _Thread_local")
    c.types = words("char short int long float double void signed unsigned bool size_t ssize_t int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t uintptr_t intptr_t FILE")
    c.constants = words("NULL true false EOF")
    c.lineComments = ["//"]
    c.blockComments = cComments
    c.strings = cStrings
    c.charLiterals = true
    c.preprocessor = true
    c.upperConstants = true
    add(c)

    var cpp = c
    cpp.name = "cpp"
    cpp.keywords.formUnion(words("alignas alignof and and_eq asm bitand bitor catch class compl concept consteval constexpr constinit const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export false friend mutable namespace new noexcept not not_eq nullptr operator or or_eq private protected public reinterpret_cast requires static_assert static_cast template this throw try typeid typename using virtual xor xor_eq override final"))
    cpp.types.formUnion(words("string vector map set unordered_map unordered_set shared_ptr unique_ptr weak_ptr optional variant array pair tuple wchar_t char8_t char16_t char32_t auto"))
    cpp.constants.formUnion(words("nullptr"))
    cpp.capitalizedTypes = false
    cpp.strings = [StringRule("R\"(", ")\"", multiline: true, escapes: false), StringRule("\""), StringRule("'")]
    add(cpp)

    var objc = c
    objc.name = "objectivec"
    objc.keywords.formUnion(words("self super nil YES NO id Class SEL IMP instancetype in out inout bycopy byref oneway"))
    objc.keywords.formUnion(words("@interface @implementation @end @protocol @class @property @synthesize @dynamic @selector @encode @try @catch @finally @throw @autoreleasepool @synchronized @import @optional @required @public @private @protected @package"))
    objc.constants.formUnion(words("nil YES NO Nil"))
    objc.atPrefix = .keyword
    objc.capitalizedTypes = true
    objc.strings = [StringRule("@\""), StringRule("\""), StringRule("'")]
    add(objc)

    var csharp = Language(name: "csharp")
    csharp.keywords = words("abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected public readonly ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual volatile while add alias ascending async await by descending dynamic equals from get global group init into join let nameof not notnull on or orderby partial record remove select set unmanaged value var when where with yield")
    csharp.types = words("bool byte char decimal double float int long object sbyte short string uint ulong ushort void nint nuint")
    csharp.constants = words("true false null")
    csharp.lineComments = ["//"]
    csharp.blockComments = cComments
    csharp.strings = [StringRule("\"\"\"", multiline: true), StringRule("@\"", "\"", multiline: true, escapes: false), StringRule("$\""), StringRule("\""), StringRule("'")]
    csharp.charLiterals = true
    csharp.preprocessor = true
    csharp.atPrefix = .attribute
    csharp.capitalizedTypes = true
    add(csharp)

    var java = Language(name: "java")
    java.keywords = words("abstract assert break case catch class const continue default do else enum extends final finally for goto if implements import instanceof interface native new package private protected public return static strictfp super switch synchronized this throw throws transient try volatile while var record sealed permits yield non-sealed")
    java.types = words("boolean byte char double float int long short void String Object Integer Long Double Float Boolean Character List Map Set ArrayList HashMap Optional")
    java.constants = words("true false null")
    java.lineComments = ["//"]
    java.blockComments = cComments
    java.strings = [StringRule("\"\"\"", multiline: true), StringRule("\""), StringRule("'")]
    java.charLiterals = true
    java.atPrefix = .attribute
    java.capitalizedTypes = true
    java.upperConstants = true
    add(java)

    var kotlin = java
    kotlin.name = "kotlin"
    kotlin.keywords = words("as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam value where abstract actual annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg it")
    kotlin.types = words("Int Long Short Byte Float Double Boolean Char String Unit Any Nothing Array List MutableList Map MutableMap Set MutableSet Pair")
    kotlin.nestedComments = true
    add(kotlin)

    var scala = java
    scala.name = "scala"
    scala.keywords = words("abstract case catch class def do else extends false final finally for forSome if implicit import lazy match new null object override package private protected return sealed super this throw trait try true type val var while with yield given using enum export extension then end inline opaque open transparent")
    scala.types = words("Int Long Short Byte Float Double Boolean Char String Unit Any AnyRef AnyVal Nothing Option Some None List Seq Map Set Vector Either Future")
    scala.nestedComments = true
    add(scala)

    var go = Language(name: "go")
    go.keywords = words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")
    go.types = words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable")
    go.constants = words("true false nil iota")
    go.builtins = words("append cap close complex copy delete imag len make new panic print println real recover min max clear")
    go.lineComments = ["//"]
    go.blockComments = cComments
    go.strings = [StringRule("`", multiline: true, escapes: false), StringRule("\""), StringRule("'")]
    go.capitalizedTypes = true
    add(go)

    var rust = Language(name: "rust")
    rust.keywords = words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while union macro_rules")
    rust.types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Box Option Result Some None Ok Err Rc Arc RefCell Cell HashMap HashSet BTreeMap")
    rust.constants = words("true false")
    rust.lineComments = ["//"]
    rust.blockComments = cComments
    rust.nestedComments = true
    rust.strings = [StringRule("\"", multiline: true)]
    rust.stringPrefixes = ["r", "b", "br", "c", "cr"]
    rust.hashRawStrings = true
    rust.charLiterals = true
    rust.atPrefix = nil
    rust.capitalizedTypes = true
    rust.upperConstants = true
    add(rust)

    var python = Language(name: "python")
    python.keywords = words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case type")
    python.constants = words("True False None Ellipsis NotImplemented self cls")
    python.builtins = words("abs all any bin bool bytes callable chr dict dir divmod enumerate eval exec filter float format frozenset getattr hasattr hash hex id input int isinstance issubclass iter len list map max min next object open ord pow print range repr reversed round set setattr slice sorted str sum super tuple type vars zip __init__ __name__ __repr__ __str__")
    python.lineComments = ["#"]
    python.strings = [StringRule("\"\"\"", multiline: true), StringRule("'''", multiline: true), StringRule("\""), StringRule("'")]
    python.stringPrefixes = ["r", "b", "f", "u", "rb", "br", "fr", "rf", "rb"]
    python.atPrefix = .attribute
    python.capitalizedTypes = true
    python.upperConstants = true
    add(python)

    var ruby = Language(name: "ruby")
    ruby.keywords = words("alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return then undef unless until when while yield require require_relative include extend attr_accessor attr_reader attr_writer private public protected raise lambda proc puts")
    ruby.constants = words("true false nil self __FILE__ __LINE__")
    ruby.lineComments = ["#"]
    ruby.blockComments = [("=begin", "=end")]
    ruby.strings = [StringRule("\"", multiline: true), StringRule("'", multiline: true), StringRule("`")]
    ruby.atPrefix = .variable
    ruby.dollarPrefix = .variable
    ruby.capitalizedTypes = true
    ruby.identifierExtras = [0x3F, 0x21]  // ? !
    add(ruby)

    var php = Language(name: "php")
    php.keywords = words("abstract and array as break callable case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile enum eval exit extends final finally fn for foreach function global goto if implements include include_once instanceof insteadof interface isset list match namespace new or print private protected public readonly require require_once return static switch throw trait try unset use var while xor yield")
    php.types = words("int float string bool array object mixed void null iterable never self parent static")
    php.constants = words("true false null TRUE FALSE NULL PHP_EOL")
    php.lineComments = ["//", "#"]
    php.blockComments = cComments
    php.strings = [StringRule("\"", multiline: true), StringRule("'", multiline: true)]
    php.dollarPrefix = .variable
    php.atPrefix = .attribute
    php.capitalizedTypes = true
    add(php)

    var js = Language(name: "javascript")
    js.keywords = words("async await break case catch class const continue debugger default delete do else enum export extends finally for from function get if implements import in instanceof interface let new of package private protected public return set static super switch this throw try typeof var void while with yield as")
    js.types = words("Array Boolean Date Error Function JSON Map Math Number Object Promise Proxy Reflect RegExp Set String Symbol WeakMap WeakSet BigInt Intl Uint8Array ArrayBuffer")
    js.constants = words("true false null undefined NaN Infinity globalThis window document console module exports require")
    js.lineComments = ["//"]
    js.blockComments = cComments
    js.strings = [StringRule("`", multiline: true), StringRule("\""), StringRule("'")]
    js.atPrefix = .attribute
    js.capitalizedTypes = true
    js.identifierExtras = [0x24]  // $
    add(js)

    var ts = js
    ts.name = "typescript"
    ts.keywords.formUnion(words("abstract any asserts declare infer is keyof namespace never readonly satisfies type unique unknown override out"))
    ts.types.formUnion(words("string number boolean bigint symbol object void undefined null Record Partial Required Readonly Pick Omit Exclude Extract ReturnType Parameters Awaited"))
    add(ts)

    var dart = js
    dart.name = "dart"
    dart.keywords = words("abstract as assert async await break case catch class const continue covariant default deferred do dynamic else enum export extends extension external factory false final finally for Function get hide if implements import in interface is late library mixin new null on operator part required rethrow return sealed set show static super switch sync this throw true try typedef var void when while with yield base")
    dart.types = words("int double num bool String List Map Set Iterable Future Stream Object Null Never void dynamic")
    dart.constants = words("true false null")
    dart.strings = [StringRule("\"\"\"", multiline: true), StringRule("'''", multiline: true), StringRule("\""), StringRule("'")]
    dart.stringPrefixes = ["r"]
    dart.identifierExtras = []
    add(dart)

    var json = Language(name: "json")
    json.flavor = .json
    json.constants = words("true false null")
    json.lineComments = ["//"]
    json.blockComments = cComments
    json.strings = [StringRule("\"")]
    json.functionCalls = false
    add(json)

    var yaml = Language(name: "yaml")
    yaml.flavor = .yaml
    yaml.constants = words("true false null yes no on off ~ True False Null Yes No On Off TRUE FALSE NULL")
    yaml.lineComments = ["#"]
    yaml.strings = [StringRule("\""), StringRule("'", escapes: false)]
    yaml.functionCalls = false
    add(yaml)

    var toml = Language(name: "toml")
    toml.flavor = .toml
    toml.constants = words("true false inf nan")
    toml.lineComments = ["#"]
    toml.strings = [StringRule("\"\"\"", multiline: true), StringRule("'''", multiline: true, escapes: false), StringRule("\""), StringRule("'", escapes: false)]
    toml.functionCalls = false
    add(toml)

    var ini = toml
    ini.name = "ini"
    ini.lineComments = ["#", ";"]
    ini.strings = [StringRule("\""), StringRule("'", escapes: false)]
    add(ini)

    var html = Language(name: "html")
    html.flavor = .markup
    html.blockComments = [("<!--", "-->")]
    html.strings = [StringRule("\"", escapes: false), StringRule("'", escapes: false)]
    html.functionCalls = false
    add(html)
    var xml = html
    xml.name = "xml"
    add(xml)

    var css = Language(name: "css")
    css.flavor = .css
    css.keywords = words("important @media @import @font-face @keyframes @supports @charset @namespace @page @layer @container @property from to and not only screen print")
    css.blockComments = cComments
    css.strings = [StringRule("\""), StringRule("'")]
    css.identifierExtras = [0x2D]  // -
    add(css)

    var sql = Language(name: "sql")
    sql.keywords = words("select from where insert into values update set delete create table drop alter add column index view trigger procedure function returns begin end declare as join inner left right full outer on group by order having limit offset union all distinct and or not null is in exists between like ilike case when then else if while for loop return with recursive primary key foreign references unique check default constraint cascade commit rollback transaction grant revoke explain analyze vacuum truncate replace ignore asc desc using cross natural over partition window rows range fetch first next only top SELECT FROM WHERE INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP ALTER ADD COLUMN INDEX VIEW TRIGGER PROCEDURE FUNCTION RETURNS BEGIN END DECLARE AS JOIN INNER LEFT RIGHT FULL OUTER ON GROUP BY ORDER HAVING LIMIT OFFSET UNION ALL DISTINCT AND OR NOT NULL IS IN EXISTS BETWEEN LIKE ILIKE CASE WHEN THEN ELSE IF WHILE FOR LOOP RETURN WITH RECURSIVE PRIMARY KEY FOREIGN REFERENCES UNIQUE CHECK DEFAULT CONSTRAINT CASCADE COMMIT ROLLBACK TRANSACTION GRANT REVOKE EXPLAIN ANALYZE VACUUM TRUNCATE REPLACE IGNORE ASC DESC USING CROSS NATURAL OVER PARTITION WINDOW ROWS RANGE FETCH FIRST NEXT ONLY TOP")
    sql.types = words("int integer bigint smallint tinyint serial bigserial decimal numeric float real double precision boolean bool char varchar text blob bytea date time timestamp timestamptz interval json jsonb uuid array INT INTEGER BIGINT SMALLINT TINYINT SERIAL BIGSERIAL DECIMAL NUMERIC FLOAT REAL DOUBLE PRECISION BOOLEAN BOOL CHAR VARCHAR TEXT BLOB BYTEA DATE TIME TIMESTAMP TIMESTAMPTZ INTERVAL JSON JSONB UUID ARRAY")
    sql.constants = words("true false null TRUE FALSE NULL")
    sql.builtins = words("count sum avg min max coalesce nullif cast now current_date current_timestamp length lower upper trim substring concat round abs COUNT SUM AVG MIN MAX COALESCE NULLIF CAST NOW LENGTH LOWER UPPER TRIM SUBSTRING CONCAT ROUND ABS")
    sql.lineComments = ["--"]
    sql.blockComments = cComments
    sql.strings = [StringRule("'", multiline: true), StringRule("\""), StringRule("`")]
    add(sql)

    var bash = Language(name: "bash")
    bash.flavor = .shell
    bash.keywords = words("if then else elif fi for while until do done case esac in function select time coproc return exit break continue local export readonly declare typeset unset shift source alias set eval exec trap")
    bash.builtins = words("echo printf read cd pwd ls cp mv rm mkdir rmdir touch cat grep sed awk find xargs sort uniq head tail wc tr cut chmod chown curl wget tar zip unzip ssh scp git make sudo test true false kill ps which env date sleep")
    bash.lineComments = ["#"]
    bash.strings = [StringRule("\"", multiline: true), StringRule("'", escapes: false)]
    bash.dollarPrefix = .variable
    bash.functionCalls = false
    add(bash)

    var powershell = Language(name: "powershell")
    powershell.flavor = .shell
    powershell.keywords = words("if else elseif switch foreach for while do until break continue return function param begin process end try catch finally throw class enum using in filter workflow parallel sequence dynamicparam trap exit")
    powershell.builtins = words("Write-Host Write-Output Get-ChildItem Get-Item Set-Item Get-Content Set-Content Get-Process Select-Object Where-Object ForEach-Object New-Item Remove-Item Copy-Item Move-Item Invoke-WebRequest Invoke-RestMethod Import-Module Export-ModuleMember Test-Path Join-Path Get-Date Start-Process")
    powershell.lineComments = ["#"]
    powershell.blockComments = [("<#", "#>")]
    powershell.strings = [StringRule("@\"", "\"@", multiline: true, escapes: false), StringRule("\"", multiline: true), StringRule("'", multiline: true, escapes: false)]
    powershell.dollarPrefix = .variable
    powershell.identifierExtras = [0x2D]
    add(powershell)

    var docker = Language(name: "dockerfile")
    docker.keywords = words("FROM RUN CMD LABEL MAINTAINER EXPOSE ENV ADD COPY ENTRYPOINT VOLUME USER WORKDIR ARG ONBUILD STOPSIGNAL HEALTHCHECK SHELL AS from run cmd label expose env add copy entrypoint volume user workdir arg onbuild stopsignal healthcheck shell as")
    docker.lineComments = ["#"]
    docker.strings = [StringRule("\""), StringRule("'", escapes: false)]
    docker.dollarPrefix = .variable
    docker.functionCalls = false
    add(docker)

    var makefile = Language(name: "makefile")
    // $@ $< $^ $? $* and $(VAR) are all variables.
    makefile.flavor = .makefile
    makefile.keywords = words("ifeq ifneq ifdef ifndef else endif include define endef export unexport override vpath")
    makefile.lineComments = ["#"]
    makefile.strings = [StringRule("\""), StringRule("'", escapes: false)]
    makefile.dollarPrefix = .variable
    makefile.functionCalls = false
    add(makefile)

    var cmake = Language(name: "cmake")
    cmake.keywords = words("if else elseif endif foreach endforeach while endwhile function endfunction macro endmacro return break continue set unset option project cmake_minimum_required add_executable add_library add_subdirectory target_link_libraries target_include_directories include find_package install message list string file get_filename_component configure_file add_custom_command add_custom_target enable_testing add_test set_target_properties target_compile_options target_compile_definitions")
    cmake.constants = words("ON OFF TRUE FALSE YES NO")
    cmake.lineComments = ["#"]
    cmake.strings = [StringRule("\"", multiline: true)]
    cmake.dollarPrefix = .variable
    cmake.upperConstants = true
    add(cmake)

    var diff = Language(name: "diff")
    diff.flavor = .diff
    diff.functionCalls = false
    add(diff)

    var markdown = Language(name: "markdown")
    markdown.flavor = .markdown
    markdown.functionCalls = false
    add(markdown)

    var lua = Language(name: "lua")
    lua.keywords = words("and break do else elseif end for function goto if in local not or repeat return then until while")
    lua.constants = words("true false nil self _G")
    lua.builtins = words("print type pairs ipairs tostring tonumber require pcall error assert setmetatable getmetatable rawget rawset next select unpack string table math io os coroutine")
    lua.lineComments = ["--"]
    lua.blockComments = [("--[[", "]]"), ("--[==[", "]==]")]
    lua.strings = [StringRule("[[", "]]", multiline: true, escapes: false), StringRule("\""), StringRule("'")]
    add(lua)

    var perl = Language(name: "perl")
    perl.keywords = words("my our local use no package sub return if elsif else unless while until for foreach do last next redo goto and or not xor eq ne lt gt le ge cmp print printf die warn eval require shift unshift push pop splice keys values each exists delete defined undef ref bless scalar wantarray")
    perl.lineComments = ["#"]
    perl.strings = [StringRule("\"", multiline: true), StringRule("'", multiline: true, escapes: false), StringRule("`")]
    perl.dollarPrefix = .variable
    perl.atPrefix = .variable
    add(perl)

    var r = Language(name: "r")
    r.keywords = words("if else repeat while function for in next break library require return invisible stop warning tryCatch switch")
    r.constants = words("TRUE FALSE NULL NA NA_integer_ NA_real_ NA_character_ Inf NaN T F")
    r.builtins = words("c length print paste paste0 cat sum mean median sd var min max seq rep apply lapply sapply vapply mapply Map Reduce Filter data.frame list vector matrix names nrow ncol dim head tail str summary plot ggplot aes")
    r.lineComments = ["#"]
    r.strings = [StringRule("\"", multiline: true), StringRule("'", multiline: true)]
    r.identifierExtras = [0x2E]  // .
    add(r)

    var haskell = Language(name: "haskell")
    haskell.keywords = words("case class data default deriving do else foreign if import in infix infixl infixr instance let module newtype of then type where qualified as hiding forall mdo family pattern")
    haskell.types = words("Int Integer Float Double Bool Char String Maybe Either IO Ordering Word Show Eq Ord Functor Applicative Monad Foldable Traversable")
    haskell.constants = words("True False Nothing Just Left Right LT EQ GT otherwise")
    haskell.lineComments = ["--"]
    haskell.blockComments = [("{-", "-}")]
    haskell.nestedComments = true
    haskell.strings = [StringRule("\"")]
    haskell.charLiterals = true
    haskell.capitalizedTypes = true
    haskell.identifierExtras = [0x27]  // '
    add(haskell)

    var elixir = Language(name: "elixir")
    elixir.keywords = words("def defp defmodule defstruct defprotocol defimpl defmacro defmacrop defguard defdelegate defexception do end fn if else unless case cond when and or not in with for receive after rescue catch raise throw try import require alias use quote unquote super")
    elixir.constants = words("true false nil")
    elixir.lineComments = ["#"]
    elixir.strings = [StringRule("\"\"\"", multiline: true), StringRule("\""), StringRule("'")]
    elixir.stringPrefixes = ["~s", "~S", "~r", "~w", "~W", "~c"]
    elixir.atPrefix = .attribute
    elixir.capitalizedTypes = true
    elixir.identifierExtras = [0x3F, 0x21]
    add(elixir)

    var erlang = Language(name: "erlang")
    erlang.keywords = words("after and andalso band begin bnot bor bsl bsr bxor case catch cond div end fun if let not of or orelse receive rem try when xor module export import record spec type behaviour define")
    erlang.constants = words("true false undefined ok error")
    erlang.lineComments = ["%"]
    erlang.strings = [StringRule("\"", multiline: true)]
    erlang.capitalizedTypes = false
    erlang.identifierExtras = []
    add(erlang)

    var clojure = Language(name: "clojure")
    clojure.keywords = words("def defn defn- defmacro defmulti defmethod defprotocol defrecord deftype defonce fn let letfn if if-let if-not when when-let when-not cond condp case do loop recur for doseq dotimes while try catch finally throw ns require import use in-ns quote var set! . .. -> ->> as-> some-> some->> cond-> cond->> and or not new")
    clojure.constants = words("true false nil")
    clojure.builtins = words("map filter reduce apply conj cons first rest next seq count get assoc dissoc update merge into vec vector list hash-map str println print keyword symbol name inc dec range take drop partial comp identity")
    clojure.lineComments = [";"]
    clojure.strings = [StringRule("\"", multiline: true)]
    clojure.identifierExtras = [0x2D, 0x3F, 0x21, 0x2A, 0x3E, 0x3C, 0x2B, 0x2E]  // - ? ! * > < + .
    add(clojure)
    var lisp = clojure
    lisp.name = "lisp"
    lisp.keywords = words("define lambda let let* letrec if cond case else when unless begin do set! quote quasiquote unquote define-syntax syntax-rules defun defvar defparameter defmacro setq setf progn loop dolist dotimes return function funcall apply car cdr cons list")
    lisp.blockComments = [("#|", "|#")]
    add(lisp)

    var latex = Language(name: "latex")
    latex.lineComments = ["%"]
    latex.strings = [StringRule("$$", multiline: true, escapes: false), StringRule("$", escapes: false)]
    latex.functionCalls = false
    latex.backslashCommands = true
    add(latex)

    var graphql = Language(name: "graphql")
    graphql.keywords = words("query mutation subscription fragment on type interface union enum input scalar schema extend directive implements repeatable")
    graphql.types = words("Int Float String Boolean ID")
    graphql.constants = words("true false null")
    graphql.lineComments = ["#"]
    graphql.strings = [StringRule("\"\"\"", multiline: true), StringRule("\"")]
    graphql.atPrefix = .attribute
    graphql.dollarPrefix = .variable
    graphql.capitalizedTypes = true
    add(graphql)

    var proto = Language(name: "protobuf")
    proto.keywords = words("syntax package import option message enum service rpc returns stream oneof map repeated optional required reserved extend extensions to max group")
    proto.types = words("double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes")
    proto.constants = words("true false")
    proto.lineComments = ["//"]
    proto.blockComments = cComments
    proto.strings = cStrings
    proto.capitalizedTypes = true
    add(proto)

    var nginx = Language(name: "nginx")
    nginx.keywords = words("server location upstream http events worker_processes listen server_name root index proxy_pass proxy_set_header return rewrite include error_log access_log ssl_certificate ssl_certificate_key if set try_files add_header expires gzip client_max_body_size keepalive_timeout")
    nginx.constants = words("on off")
    nginx.lineComments = ["#"]
    nginx.strings = [StringRule("\""), StringRule("'")]
    nginx.dollarPrefix = .variable
    nginx.functionCalls = false
    nginx.identifierExtras = [0x2D]
    add(nginx)

    var vim = Language(name: "vim")
    vim.keywords = words("set setlocal let unlet if else elseif endif for endfor while endwhile function endfunction return call execute normal map nmap imap vmap nnoremap inoremap vnoremap noremap autocmd augroup end syntax highlight colorscheme filetype source echo silent command finish try catch endtry throw")
    vim.lineComments = ["\""]
    vim.strings = [StringRule("'", escapes: false)]
    vim.functionCalls = true
    add(vim)

    var zig = rust
    zig.name = "zig"
    zig.keywords = words("align allowzero and anyframe anytype asm async await break callconv catch comptime const continue defer else enum errdefer error export extern fn for if inline linksection noalias noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test threadlocal try union unreachable usingnamespace var volatile while")
    zig.types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f16 f32 f64 f128 bool void noreturn type anyerror comptime_int comptime_float c_int c_uint c_long c_char")
    zig.constants = words("true false null undefined")
    zig.nestedComments = false
    zig.stringPrefixes = []
    zig.hashRawStrings = false
    zig.strings = [StringRule("\""), StringRule("\\\\", "\n", multiline: false, escapes: false)]
    add(zig)

    var nim = python
    nim.name = "nim"
    nim.keywords = words("addr and as asm bind block break case cast concept const continue converter defer discard distinct div do elif else end enum except export finally for from func if import in include interface is isnot iterator let macro method mixin mod nil not notin object of or out proc ptr raise ref return shl shr static template try tuple type using var when while xor yield echo result")
    nim.types = words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float float32 float64 bool char string seq array set cstring pointer auto void")
    nim.blockComments = [("#[", "]#")]
    nim.nestedComments = true
    nim.stringPrefixes = ["r"]
    add(nim)

    var julia = Language(name: "julia")
    julia.keywords = words("abstract type baremodule begin break catch const continue do else elseif end export finally for function global if import in isa let local macro module mutable struct primitive quote return try using where while")
    julia.constants = words("true false nothing missing Inf NaN pi im")
    julia.lineComments = ["#"]
    julia.blockComments = [("#=", "=#")]
    julia.nestedComments = true
    julia.strings = [StringRule("\"\"\"", multiline: true), StringRule("\""), StringRule("'")]
    julia.atPrefix = .attribute
    julia.capitalizedTypes = true
    julia.identifierExtras = [0x21]
    add(julia)

    var groovy = java
    groovy.name = "groovy"
    groovy.keywords.formUnion(words("def in as trait with println it"))
    groovy.strings = [StringRule("\"\"\"", multiline: true), StringRule("'''", multiline: true), StringRule("\""), StringRule("'"), StringRule("/", "/", escapes: true)]
    groovy.strings.removeLast()
    add(groovy)

    var matlab = Language(name: "matlab")
    matlab.keywords = words("break case catch classdef continue else elseif end for function global if otherwise parfor persistent return spmd switch try while properties methods events enumeration")
    matlab.constants = words("true false pi Inf NaN eps i j end")
    matlab.builtins = words("disp fprintf sprintf zeros ones eye rand randn size length numel sum prod mean max min abs sqrt exp log sin cos tan plot figure hold xlabel ylabel title legend linspace reshape find any all isempty numel cell struct")
    matlab.lineComments = ["%"]
    matlab.blockComments = [("%{", "%}")]
    matlab.strings = [StringRule("\""), StringRule("'", escapes: false)]
    matlab.postfixQuote = true  // A' is transpose, not a string opener
    add(matlab)

    var fortran = Language(name: "fortran")
    fortran.keywords = words("program end subroutine function module contains use implicit none integer real double precision complex character logical dimension allocatable allocate deallocate if then else elseif endif do enddo while select case default call return stop print write read open close format intent in out inout type interface procedure pure elemental recursive result parameter public private save data common goto continue exit cycle PROGRAM END SUBROUTINE FUNCTION MODULE CONTAINS USE IMPLICIT NONE INTEGER REAL DOUBLE PRECISION COMPLEX CHARACTER LOGICAL DIMENSION ALLOCATABLE ALLOCATE DEALLOCATE IF THEN ELSE ELSEIF ENDIF DO ENDDO WHILE SELECT CASE DEFAULT CALL RETURN STOP PRINT WRITE READ OPEN CLOSE FORMAT INTENT IN OUT INOUT TYPE INTERFACE PROCEDURE")
    fortran.lineComments = ["!"]
    fortran.strings = [StringRule("\"", escapes: false), StringRule("'", escapes: false)]
    add(fortran)

    var batch = Language(name: "batch")
    batch.keywords = words("echo set if else for in do goto call exit rem pause setlocal endlocal enabledelayedexpansion not exist defined errorlevel start cd dir copy move del mkdir rmdir type ECHO SET IF ELSE FOR IN DO GOTO CALL EXIT REM PAUSE SETLOCAL ENDLOCAL START CD DIR COPY MOVE DEL MKDIR RMDIR TYPE")
    batch.lineComments = ["::", "REM ", "rem "]
    batch.strings = [StringRule("\"", escapes: false)]
    batch.functionCalls = false
    add(batch)

    return t
  }()
}
