import AppKit
import VienMarkdown

/// A text view sized to the printable page, filled with a rendered (read-only) version of the document.
/// Used for Print and PDF export so both share the same native typesetting.
enum PrintView {
  static func make(document: MarkdownFile, printInfo: NSPrintInfo) -> NSTextView {
    let size = printInfo.paperSize
    let width = size.width - printInfo.leftMargin - printInfo.rightMargin
    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: size.height - printInfo.topMargin - printInfo.bottomMargin))
    view.isEditable = false
    view.isVerticallyResizable = true
    view.isHorizontallyResizable = false
    view.minSize = NSSize(width: 0, height: 0)
    view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    view.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    view.textContainer?.widthTracksTextView = true
    // Paper is white whatever the editor's palette.
    let rendered = Theme.using(.system) { AttributedRenderer(document: document.markdown, theme: Theme(zoom: 0.85, palette: .system)).render() }
    view.textStorage?.setAttributedString(rendered)
    view.sizeToFit()
    return view
  }
}
