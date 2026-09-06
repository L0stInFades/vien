/// AST → HTML. Output follows the CommonMark/GFM reference format exactly (used by the spec ratchet)
/// and adds Vien's extension markup (math, mermaid, footnotes, front matter).

public struct HTMLRenderer {
  public struct Options: Sendable {
    /// Escape raw HTML instead of passing it through.
    public var safe = false
    /// Emit `<pre class="mermaid">` for mermaid fences so a page script can render them.
    public var diagrams = true
    /// Render task list items with checkboxes.
    public var taskLists = true
    /// Emit front matter as `<pre class="front-matter">` (otherwise omitted).
    public var showFrontMatter = false
    /// Add `id` attributes to headings (slugified) for TOC links.
    public var headingIDs = false
    /// GFM "tagfilter": neutralise `<script>`, `<style>`, `<iframe>`… by escaping their `<`.
    public var filterDisallowedHTML = false
    /// Renders a fenced code block (`language` may be empty) to HTML, e.g. with syntax colouring;
    /// nil keeps the plain `<pre><code>` output.
    public var codeBlock: (@Sendable (_ language: String, _ code: String) -> String?)? = nil

    public init() {}
  }

  private let doc: MarkdownDocument
  private let options: Options
  private var out = ""
  private var footnoteOrder: [String] = []
  private var footnoteBodies: [String: Block] = [:]
  private var slugCounts: [String: Int] = [:]

  public init(document: MarkdownDocument, options: Options = Options()) {
    doc = document
    self.options = options
  }

  public static func render(_ document: MarkdownDocument, options: Options = Options()) -> String {
    var r = HTMLRenderer(document: document, options: options)
    return r.render()
  }

  public mutating func render() -> String {
    out = ""
    out.reserveCapacity(doc.bytes.count * 2)
    collectFootnotes(Array(doc.blocks))
    for (i, b) in doc.blocks.enumerated() { renderBlock(b, tight: false, isLast: i == doc.blocks.count - 1) }
    renderFootnotes()
    return out
  }

  // MARK: - Blocks

  private mutating func collectFootnotes(_ blocks: [Block]) {
    for b in blocks {
      if case .footnoteDefinition(let label, _) = b.kind { footnoteBodies[label] = b }
      collectFootnotes(b.children)
    }
  }

  private mutating func renderBlocks(_ blocks: [Block], tight: Bool) {
    for (i, b) in blocks.enumerated() { renderBlock(b, tight: tight, isLast: i == blocks.count - 1) }
  }

  private mutating func renderBlock(_ block: Block, tight: Bool, isLast: Bool) {
    switch block.kind {
    case .paragraph:
      if tight {
        renderInlines(doc.inlines(of: block))
        if !isLast { out += "\n" }
      } else {
        out += "<p>"
        renderInlines(doc.inlines(of: block))
        out += "</p>\n"
      }
    case .heading(let level, _, _, _):
      let inlines = doc.inlines(of: block)
      if options.headingIDs {
        out += "<h\(level) id=\"\(slug(for: inlines))\">"
      } else {
        out += "<h\(level)>"
      }
      renderInlines(inlines)
      out += "</h\(level)>\n"
    case .thematicBreak:
      out += "<hr />\n"
    case .blockQuote:
      out += "<blockquote>\n"
      renderBlocks(block.children, tight: false)
      out += "</blockquote>\n"
    case .list(let info):
      let tag = info.ordered ? "ol" : "ul"
      if info.ordered, info.start != 1 { out += "<\(tag) start=\"\(info.start)\">\n" } else { out += "<\(tag)>\n" }
      for item in block.children { renderListItem(item, tight: info.tight) }
      out += "</\(tag)>\n"
    case .listItem:
      renderListItem(block, tight: tight)
    case .fencedCode:
      let lang = block.language(in: doc.bytes)
      if options.diagrams, let lang, lang == "mermaid" {
        out += "<pre class=\"mermaid\">" + Text.escapeHTML(codeText(block)) + "</pre>\n"
      } else if lang == "math" {
        out += "<div class=\"math display\">" + Text.escapeHTML(codeText(block)) + "</div>\n"
      } else if let html = options.codeBlock?(lang ?? "", codeText(block)) {
        out += html
      } else {
        out += "<pre><code"
        if let lang, !lang.isEmpty { out += " class=\"language-\(Text.escapeHTML(lang))\"" }
        out += ">" + Text.escapeHTML(codeText(block)) + "</code></pre>\n"
      }
    case .indentedCode:
      out += "<pre><code>" + Text.escapeHTML(codeText(block)) + "</code></pre>\n"
    case .htmlBlock:
      let raw = doc.text(of: block)
      out += options.safe ? "<!-- raw HTML omitted -->\n" : (options.filterDisallowedHTML ? filterDisallowed(raw) : raw) + "\n"
    case .linkReferenceDefinition, .footnoteDefinition:
      break
    case .table(let info):
      out += "<table>\n"
      for (r, row) in block.children.enumerated() {
        let header = r == 0
        if header { out += "<thead>\n" } else if r == 1 { out += "<tbody>\n" }
        out += "<tr>\n"
        for c in 0..<info.alignments.count {
          let tag = header ? "th" : "td"
          var attr = ""
          switch info.alignments[c] {
          case .left: attr = " align=\"left\""
          case .center: attr = " align=\"center\""
          case .right: attr = " align=\"right\""
          case .none: break
          }
          out += "<\(tag)\(attr)>"
          if c < row.children.count { renderInlines(doc.inlines(of: row.children[c])) }
          out += "</\(tag)>\n"
        }
        out += "</tr>\n"
        if header { out += "</thead>\n" }
        if !header, r == block.children.count - 1 { out += "</tbody>\n" }
      }
      out += "</table>\n"
    case .tableRow, .tableCell:
      break
    case .mathBlock:
      out += "<div class=\"math display\">" + Text.escapeHTML(doc.text(of: block)) + "</div>\n"
    case .frontMatter(let kind, _, _):
      if options.showFrontMatter {
        let name = switch kind { case .yaml: "yaml"; case .toml: "toml"; case .json: "json" }
        out += "<pre class=\"front-matter language-\(name)\">" + Text.escapeHTML(doc.text(of: block)) + "</pre>\n"
      }
    }
  }

  private mutating func renderListItem(_ item: Block, tight: Bool) {
    out += "<li>"
    if case .listItem(let info) = item.kind, let task = info.task, options.taskLists {
      out += task.checked ? "<input checked=\"\" disabled=\"\" type=\"checkbox\"> " : "<input disabled=\"\" type=\"checkbox\"> "
    }
    let children = item.children
    if children.isEmpty {
      out += "</li>\n"
      return
    }
    // Block children start on a new line unless the item is tight and begins with a paragraph.
    var needsNewline = true
    if tight, case .paragraph = children[0].kind { needsNewline = false }
    if needsNewline { out += "\n" }
    for (i, child) in children.enumerated() {
      var c = child
      // Strip the task checkbox text from the first paragraph.
      if i == 0, case .listItem(let info) = item.kind, let task = info.task, case .paragraph = c.kind, !c.lines.isEmpty {
        var first = c.lines[0]
        var s = task.range.upperBound
        while s < first.range.upperBound, doc.bytes[s].isSpaceOrTab { s += 1 }
        first.range = s..<first.range.upperBound
        first.virtualSpaces = 0
        c.lines[0] = first
      }
      renderBlock(c, tight: tight, isLast: i == children.count - 1)
      if tight, i == children.count - 1, case .paragraph = c.kind { /* no trailing newline */ }
    }
    out += "</li>\n"
  }

  private func codeText(_ block: Block) -> String {
    var s = doc.text(of: block)
    if !s.isEmpty { s += "\n" }
    return s
  }

  private mutating func slug(for inlines: [Inline]) -> String {
    var text = ""
    for i in inlines { i.appendPlainText(to: &text) }
    var slug = ""
    for ch in text.lowercased() {
      if ch.isLetter || ch.isNumber { slug.append(ch) } else if ch == " " || ch == "-" { slug.append("-") }
    }
    if slug.isEmpty { slug = "section" }
    let n = slugCounts[slug, default: 0]
    slugCounts[slug] = n + 1
    return n == 0 ? slug : "\(slug)-\(n)"
  }

  // MARK: - Inlines

  private static let disallowedTags = ["title", "textarea", "style", "xmp", "iframe", "noembed", "noframes", "script", "plaintext"]

  private mutating func renderInlines(_ inlines: [Inline]) {
    for node in inlines { renderInline(node) }
  }

  private mutating func renderInline(_ node: Inline) {
    switch node.kind {
    case .text(let s): out += Text.escapeHTML(s)
    case .softBreak: out += "\n"
    case .hardBreak: out += "<br />\n"
    case .code(let s, _): out += "<code>" + Text.escapeHTML(s) + "</code>"
    case .emphasis: out += "<em>"; renderInlines(node.children); out += "</em>"
    case .strong: out += "<strong>"; renderInlines(node.children); out += "</strong>"
    case .strikethrough: out += "<del>"; renderInlines(node.children); out += "</del>"
    case .superscript: out += "<sup>"; renderInlines(node.children); out += "</sup>"
    case .subscript: out += "<sub>"; renderInlines(node.children); out += "</sub>"
    case .link(let dest, let title):
      out += "<a href=\"" + Text.escapeHTML(Text.encodeURL(dest)) + "\""
      if let title { out += " title=\"" + Text.escapeHTML(title) + "\"" }
      out += ">"
      renderInlines(node.children)
      out += "</a>"
    case .image(let dest, let title):
      var alt = ""
      for c in node.children { c.appendPlainText(to: &alt) }
      out += "<img src=\"" + Text.escapeHTML(Text.encodeURL(dest)) + "\" alt=\"" + Text.escapeHTML(alt) + "\""
      if let title { out += " title=\"" + Text.escapeHTML(title) + "\"" }
      out += " />"
    case .autolink(let url, let text):
      out += "<a href=\"" + Text.escapeHTML(Text.encodeURL(url)) + "\">" + Text.escapeHTML(text) + "</a>"
    case .extendedAutolink(let url, let text):
      out += "<a href=\"" + Text.escapeHTML(Text.encodeURL(url)) + "\">" + Text.escapeHTML(text) + "</a>"
    case .html(let raw):
      if options.safe { out += "<!-- raw HTML omitted -->" } else { out += options.filterDisallowedHTML ? filterDisallowed(raw) : raw }
    case .math(let s): out += "<span class=\"math inline\">" + Text.escapeHTML(s) + "</span>"
    case .footnoteReference(let label):
      let n: Int
      if let i = footnoteOrder.firstIndex(of: label) { n = i + 1 } else { footnoteOrder.append(label); n = footnoteOrder.count }
      out += "<sup class=\"footnote-ref\"><a href=\"#fn-\(n)\" id=\"fnref-\(n)\">\(n)</a></sup>"
    case .emoji(let e, _): out += e
    }
  }

  /// GFM "disallowed raw HTML": neutralise a handful of tag names by escaping their `<`.
  private func filterDisallowed(_ raw: String) -> String {
    guard raw.contains("<") else { return raw }
    let bytes = Array(raw.utf8)
    var out = [Byte]()
    out.reserveCapacity(bytes.count + 8)
    var i = 0
    while i < bytes.count {
      let c = bytes[i]
      if c == ASCII.lt {
        var k = i + 1
        if k < bytes.count, bytes[k] == ASCII.slash { k += 1 }
        let nameStart = k
        while k < bytes.count, bytes[k].isLetter { k += 1 }
        let name = String(decoding: bytes[nameStart..<k], as: UTF8.self).lowercased()
        let after = k < bytes.count ? bytes[k] : nil
        let terminated = after == nil || after!.isASCIIWhitespace || after == ASCII.gt || after == ASCII.slash
        if Self.disallowedTags.contains(name), terminated {
          out.append(contentsOf: Array("&lt;".utf8))
          i += 1
          continue
        }
      }
      out.append(c)
      i += 1
    }
    return String(decoding: out, as: UTF8.self)
  }

  private mutating func renderFootnotes() {
    guard !footnoteOrder.isEmpty else { return }
    out += "<section class=\"footnotes\">\n<ol>\n"
    for (i, label) in footnoteOrder.enumerated() {
      let n = i + 1
      out += "<li id=\"fn-\(n)\">\n"
      if let body = footnoteBodies[label] {
        renderBlocks(body.children, tight: false)
      }
      out += "<a href=\"#fnref-\(n)\" class=\"footnote-backref\">↩</a>\n</li>\n"
    }
    out += "</ol>\n</section>\n"
  }
}
