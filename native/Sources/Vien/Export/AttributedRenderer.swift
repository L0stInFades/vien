import AppKit
import VienMarkdown

/// Renders a document to a styled NSAttributedString with no Markdown syntax visible. Used for
/// printing; the same typography as the editor, so the page looks like what you wrote.
struct AttributedRenderer {
  let document: MarkdownDocument
  let theme: Theme

  func render() -> NSAttributedString {
    let out = NSMutableAttributedString()
    for block in document.blocks { append(block, to: out, indent: 0, tight: false) }
    return out
  }

  private func append(_ block: Block, to out: NSMutableAttributedString, indent: CGFloat, tight: Bool) {
    switch block.kind {
    case .paragraph:
      out.append(inlines(document.inlines(of: block), font: theme.body(), color: Theme.text))
      out.append(paragraphEnd(spacing: tight ? 0 : theme.paragraphSpacing, indent: indent))
    case .heading(let level, _, _, _):
      out.append(inlines(document.inlines(of: block), font: theme.heading(level: level), color: Theme.text))
      out.append(paragraphEnd(spacing: theme.paragraphSpacing * 0.5, before: theme.headingSpacingBefore, indent: indent, lineHeight: 1.2))
    case .thematicBreak:
      out.append(NSAttributedString(string: "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}", attributes: [.font: theme.body(), .foregroundColor: Theme.marker]))
      out.append(paragraphEnd(spacing: theme.paragraphSpacing, indent: indent))
    case .blockQuote:
      for child in block.children { append(child, to: out, indent: indent + 24, tight: false) }
    case .list(let info):
      for (i, item) in block.children.enumerated() {
        let marker = info.ordered ? "\(info.start + i)." : "•"
        var task = ""
        if case .listItem(let li) = item.kind, let t = li.task { task = t.checked ? "☑ " : "☐ " }
        let markerString = NSAttributedString(string: marker + "\t" + task, attributes: [.font: theme.body(), .foregroundColor: Theme.secondary])
        var first = true
        for child in item.children {
          if first {
            out.append(markerString)
            first = false
            var c = child
            if case .listItem(let li) = item.kind, let t = li.task, case .paragraph = c.kind, !c.lines.isEmpty {
              var l = c.lines[0]
              var s = t.range.upperBound
              while s < l.range.upperBound, document.bytes[s] == 0x20 { s += 1 }
              l.range = s..<l.range.upperBound
              c.lines[0] = l
            }
            append(c, to: out, indent: indent + 22, tight: info.tight)
          } else {
            append(child, to: out, indent: indent + 22, tight: info.tight)
          }
        }
        if item.children.isEmpty { out.append(markerString); out.append(paragraphEnd(spacing: 0, indent: indent + 22)) }
      }
      if tight == false { out.append(NSAttributedString(string: "", attributes: [:])) }
    case .listItem:
      for child in block.children { append(child, to: out, indent: indent, tight: tight) }
    case .fencedCode, .indentedCode, .htmlBlock, .mathBlock, .frontMatter:
      let text = document.text(of: block)
      out.append(NSAttributedString(string: text, attributes: [.font: theme.code(), .foregroundColor: Theme.text, .backgroundColor: Theme.codeBackground]))
      out.append(paragraphEnd(spacing: theme.paragraphSpacing, indent: indent, lineHeight: 1.3))
    case .table(let info):
      let cols = info.alignments.count
      let tabs = (0..<cols).map { NSTextTab(textAlignment: .left, location: CGFloat($0 + 1) * 140, options: [:]) }
      for (r, row) in block.children.enumerated() {
        let font = r == 0 ? theme.body(weight: .semibold) : theme.body()
        for (c, cell) in row.children.enumerated() {
          if c > 0 { out.append(NSAttributedString(string: "\t", attributes: [.font: font])) }
          out.append(inlines(document.inlines(of: cell), font: font, color: Theme.text))
        }
        let style = theme.paragraphStyle(indent: indent, spacingAfter: r == block.children.count - 1 ? theme.paragraphSpacing : 2) as! NSMutableParagraphStyle
        style.tabStops = tabs
        out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .font: font]))
      }
    case .footnoteDefinition(let label, _):
      out.append(NSAttributedString(string: "[\(label)] ", attributes: [.font: theme.body(size: theme.baseSize * 0.85), .foregroundColor: Theme.secondary]))
      for child in block.children { append(child, to: out, indent: indent + 16, tight: true) }
    case .linkReferenceDefinition, .tableRow, .tableCell:
      break
    }
  }

  private func paragraphEnd(spacing: CGFloat, before: CGFloat = 0, indent: CGFloat, lineHeight: CGFloat? = nil) -> NSAttributedString {
    let style = theme.paragraphStyle(lineHeight: lineHeight, indent: indent, firstLineIndent: indent, spacingBefore: before, spacingAfter: spacing)
    return NSAttributedString(string: "\n", attributes: [.paragraphStyle: style, .font: theme.body()])
  }

  private func inlines(_ nodes: [Inline], font: NSFont, color: NSColor) -> NSAttributedString {
    let out = NSMutableAttributedString()
    for n in nodes { inline(n, into: out, font: font, color: color, bold: false, italic: false) }
    return out
  }

  private func inline(_ node: Inline, into out: NSMutableAttributedString, font: NSFont, color: NSColor, bold: Bool, italic: Bool) {
    var bold = bold, italic = italic
    func styled() -> NSFont {
      var f = font
      if bold { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
      if italic { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
      return f
    }
    switch node.kind {
    case .text(let s): out.append(NSAttributedString(string: s, attributes: [.font: styled(), .foregroundColor: color]))
    case .softBreak: out.append(NSAttributedString(string: " ", attributes: [.font: styled()]))
    case .hardBreak: out.append(NSAttributedString(string: "\u{2028}", attributes: [.font: styled()]))
    case .code(let s, _): out.append(NSAttributedString(string: s, attributes: [.font: theme.code(size: font.pointSize), .foregroundColor: color, .backgroundColor: Theme.codeBackground]))
    case .emphasis: italic = true
    case .strong: bold = true
    case .strikethrough:
      let inner = NSMutableAttributedString()
      for c in node.children { inline(c, into: inner, font: font, color: color, bold: bold, italic: italic) }
      inner.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: inner.length))
      out.append(inner)
      return
    case .link(let dest, _):
      let inner = NSMutableAttributedString()
      for c in node.children { inline(c, into: inner, font: font, color: Theme.link, bold: bold, italic: italic) }
      if let url = URL(string: dest) { inner.addAttribute(.link, value: url, range: NSRange(location: 0, length: inner.length)) }
      out.append(inner)
      return
    case .image(_, _):
      out.append(NSAttributedString(string: "[" + node.plainText + "]", attributes: [.font: styled(), .foregroundColor: Theme.secondary]))
      return
    case .autolink(let url, let text), .extendedAutolink(let url, let text):
      out.append(NSAttributedString(string: text, attributes: [.font: styled(), .foregroundColor: Theme.link, .link: URL(string: url) ?? url]))
      return
    case .html(let raw): out.append(NSAttributedString(string: raw, attributes: [.font: theme.code(size: font.pointSize), .foregroundColor: Theme.secondary]))
    case .math(let s): out.append(NSAttributedString(string: s, attributes: [.font: theme.code(size: font.pointSize), .foregroundColor: color]))
    case .footnoteReference(let label): out.append(NSAttributedString(string: "[\(label)]", attributes: [.font: theme.body(size: font.pointSize * 0.75), .baselineOffset: font.pointSize * 0.35, .foregroundColor: Theme.accent]))
    case .emoji(let e, _): out.append(NSAttributedString(string: e, attributes: [.font: styled()]))
    case .superscript:
      out.append(NSAttributedString(string: node.plainText, attributes: [.font: theme.body(size: font.pointSize * 0.75), .baselineOffset: font.pointSize * 0.35, .foregroundColor: color]))
      return
    case .subscript:
      out.append(NSAttributedString(string: node.plainText, attributes: [.font: theme.body(size: font.pointSize * 0.75), .baselineOffset: -font.pointSize * 0.15, .foregroundColor: color]))
      return
    }
    for c in node.children { inline(c, into: out, font: font, color: color, bold: bold, italic: italic) }
  }
}
