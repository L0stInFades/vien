import AppKit
import UniformTypeIdentifiers
import VienDiagrams
import VienCode
import VienMarkdown
import VienMath

/// HTML and PDF export, plus Pandoc import/export when Pandoc is installed. Diagrams and math are
/// rendered by the native engines, so exports are deterministic and never need the network.
extension MarkdownFile {
  @IBAction func exportHTML(_ sender: Any?) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.html]
    panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".html"
    guard let window = windowForSheet else { return }
    panel.beginSheetModal(for: window) { [self] response in
      guard response == .OK, let url = panel.url else { return }
      Task {
        let html = await HTMLExport.document(for: self, title: (displayName as NSString).deletingPathExtension)
        do { try html.write(to: url, atomically: true, encoding: .utf8) } catch { self.presentError(error) }
      }
    }
  }

  @IBAction func exportPDF(_ sender: Any?) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".pdf"
    guard let window = windowForSheet else { return }
    panel.beginSheetModal(for: window) { [self] response in
      guard response == .OK, let url = panel.url else { return }
      do { try HTMLExport.pdf(for: self).write(to: url) } catch { self.presentError(error) }
    }
  }

  @IBAction func exportDocx(_ sender: Any?) {
    guard Pandoc.isAvailable else { presentError(Pandoc.missingError); return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
    panel.nameFieldStringValue = (displayName as NSString).deletingPathExtension + ".docx"
    guard let window = windowForSheet else { return }
    panel.beginSheetModal(for: window) { [self] response in
      guard response == .OK, let url = panel.url else { return }
      Task {
        do { try await Pandoc.convert(markdown: storage.string, to: url, format: "docx") } catch { self.presentError(error) }
      }
    }
  }

  @IBAction func importWithPandoc(_ sender: Any?) {
    guard Pandoc.isAvailable else { presentError(Pandoc.missingError); return }
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType(filenameExtension: "docx"), UTType(filenameExtension: "odt"), UTType(filenameExtension: "rst"), UTType(filenameExtension: "tex"), UTType.html, UTType(filenameExtension: "epub")].compactMap { $0 }
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task {
        do {
          let markdown = try await Pandoc.importMarkdown(from: url)
          let doc = try NSDocumentController.shared.makeUntitledDocument(ofType: "net.daringfireball.markdown") as! MarkdownFile
          doc.setText(markdown)
          NSDocumentController.shared.addDocument(doc)
          doc.makeWindowControllers()
          doc.showWindows()
        } catch { NSApp.presentError(error) }
      }
    }
  }
}

enum HTMLExport {
  /// A self-contained HTML page: system typography, inline SVG for Mermaid, MathML for math.
  static func document(for file: MarkdownFile, title: String, forPrint: Bool = false) async -> String {
    var options = HTMLRenderer.Options()
    options.headingIDs = true
    options.showFrontMatter = Preferences.shared.showFrontMatterInExport
    options.diagrams = true
    options.codeBlock = { language, code in highlightedCodeBlock(language: language, code: code) }
    let doc = file.markdown
    var body = HTMLRenderer.render(doc, options: options)

    body = replaceAll(in: body, open: "<pre class=\"mermaid\">", close: "</pre>") { src in
      let source = unescape(src)
      if let r = try? DiagramRenderer.render(source, dark: false, maxWidth: 1200) { return "<figure class=\"diagram\">\(r.svg)</figure>" }
      return "<pre class=\"mermaid-error\">\(src)</pre>"
    }
    body = replaceAll(in: body, open: "<div class=\"math display\">", close: "</div>") { src in
      if let mathml = try? MathRenderer.mathML(unescape(src), display: true) { return "<div class=\"math display\">\(mathml)</div>" }
      return "<pre>\(src)</pre>"
    }
    body = replaceAll(in: body, open: "<span class=\"math inline\">", close: "</span>") { src in
      if let mathml = try? MathRenderer.mathML(unescape(src), display: false) { return mathml }
      return "<code>\(src)</code>"
    }
    return """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>\(HTMLExport.escape(title))</title>
    <style>\(css(forPrint: forPrint))</style>
    </head>
    <body>
    <article class="markdown">
    \(body)
    </article>
    </body>
    </html>
    """
  }

  private static func replaceAll(in html: String, open: String, close: String, _ transform: (String) -> String) -> String {
    var out = ""
    var rest = Substring(html)
    while let r = rest.range(of: open) {
      out += rest[..<r.lowerBound]
      let afterOpen = rest[r.upperBound...]
      guard let c = afterOpen.range(of: close) else { out += rest[r.lowerBound...]; return out }
      let inner = String(afterOpen[..<c.lowerBound])
      out += transform(inner)
      rest = afterOpen[c.upperBound...]
    }
    out += rest
    return out
  }

  /// A fenced code block with the editor's tokens as `tk-*` spans (nil for unknown languages).
  nonisolated static func highlightedCodeBlock(language: String, code: String) -> String? {
    guard let lang = Language.named(language) else { return nil }
    let bytes = Array(code.utf8)
    var out = "<pre><code class=\"language-\(escape(language))\">"
    var pos = 0
    for token in Highlighter.tokens(bytes, language: lang) {
      out += escape(String(decoding: bytes[pos..<token.range.lowerBound], as: UTF8.self))
      out += "<span class=\"\(token.kind.cssClass)\">" + escape(String(decoding: bytes[token.range], as: UTF8.self)) + "</span>"
      pos = token.range.upperBound
    }
    out += escape(String(decoding: bytes[pos...], as: UTF8.self)) + "</code></pre>\n"
    return out
  }

  private static func unescape(_ s: String) -> String {
    s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
  }

  static func css(forPrint: Bool) -> String {
    """
    :root { color-scheme: light dark; }
    html { -webkit-text-size-adjust: 100%; }
    body { margin: 0; padding: 0; background: \(forPrint ? "#fff" : "Canvas"); color: \(forPrint ? "#1d1d1f" : "CanvasText");
      font: 16px/1.6 -apple-system, "SF Pro Text", "Helvetica Neue", Helvetica, Arial, sans-serif; }
    article.markdown { max-width: 42em; margin: 0 auto; padding: 3em 2em; }
    h1, h2, h3, h4, h5, h6 { font-weight: 600; line-height: 1.25; margin: 1.6em 0 0.5em; }
    h1 { font-size: 1.9em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; } h4 { font-size: 1.1em; }
    p, ul, ol, blockquote, pre, table, figure { margin: 0 0 1em; }
    a { color: -apple-system-blue; text-decoration: none; } a:hover { text-decoration: underline; }
    code, pre { font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 0.88em; }
    code { background: rgba(127,127,127,0.14); padding: 0.1em 0.35em; border-radius: 4px; }
    pre { background: rgba(127,127,127,0.10); padding: 0.9em 1em; border-radius: 8px; overflow-x: auto; line-height: 1.45; }
    pre code { background: none; padding: 0; font-size: 1em; }
    blockquote { border-left: 3px solid rgba(127,127,127,0.35); margin-left: 0; padding-left: 1em; color: rgba(127,127,127,0.95); }
    hr { border: 0; border-top: 1px solid rgba(127,127,127,0.35); margin: 2em 0; }
    img { max-width: 100%; height: auto; }
    table { border-collapse: collapse; width: 100%; font-size: 0.95em; }
    th, td { border: 1px solid rgba(127,127,127,0.3); padding: 0.4em 0.7em; text-align: left; }
    th { background: rgba(127,127,127,0.08); font-weight: 600; }
    li:has(> input[type=checkbox]) { list-style: none; margin-left: -1.4em; }
    figure.diagram { text-align: center; } figure.diagram svg { max-width: 100%; height: auto; }
    .footnotes { font-size: 0.9em; color: rgba(127,127,127,0.95); border-top: 1px solid rgba(127,127,127,0.3); margin-top: 3em; padding-top: 1em; }
    .footnote-ref a { text-decoration: none; }
    pre.front-matter { font-size: 0.8em; opacity: 0.7; }
    .math.display { text-align: center; overflow-x: auto; margin: 1em 0; } math { font-size: 1.05em; }
    .tk-keyword, .tk-heading { color: #9B2393; } .tk-type, .tk-tag { color: #0B4F79; } .tk-string, .tk-deleted { color: #C41A16; }
    .tk-number, .tk-constant { color: #1C00CF; } .tk-comment { color: #5D6C79; } .tk-function, .tk-property { color: #326D74; }
    .tk-variable { color: #6C36A5; } .tk-attribute, .tk-meta { color: #643820; } .tk-inserted { color: #008A00; } .tk-heading { font-weight: 600; }
    @media (prefers-color-scheme: dark) { .tk-keyword, .tk-heading { color: #FC5FA3; } .tk-type, .tk-tag { color: #5DD8FF; }
      .tk-string, .tk-deleted { color: #FC6A5D; } .tk-number, .tk-constant { color: #D0BF69; } .tk-comment { color: #6C7986; }
      .tk-function, .tk-property { color: #67B7A4; } .tk-variable { color: #A167E6; } .tk-attribute, .tk-meta { color: #BF8555; } .tk-inserted { color: #6AD26A; } }
    @media print { article.markdown { max-width: none; padding: 0; } pre { white-space: pre-wrap; } a { color: inherit; } }
    @page { margin: 20mm 15mm; }
    """
  }

  /// PDF through the native print pipeline: the same typesetting as Print, no web engine.
  static func pdf(for file: MarkdownFile) throws -> Data {
    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
    info.paperSize = NSSize(width: 595, height: 842)  // A4 in points
    info.topMargin = 56; info.bottomMargin = 56; info.leftMargin = 48; info.rightMargin = 48
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    let view = PrintView.make(document: file, printInfo: info)
    let data = NSMutableData()
    let op = NSPrintOperation.pdfOperation(with: view, inside: view.bounds, to: data, printInfo: info)
    op.showsPrintPanel = false
    op.showsProgressPanel = false
    guard op.run() else { throw NSError(domain: "Vien", code: 1, userInfo: [NSLocalizedDescriptionKey: "PDF export failed."]) }
    return data as Data
  }
}

/// Pandoc bridge for formats Markdown cannot express natively. Optional: the menu explains how to
/// install it when it is missing.
enum Pandoc {
  static var path: String? {
    for p in ["/opt/homebrew/bin/pandoc", "/usr/local/bin/pandoc", "/usr/bin/pandoc"] where FileManager.default.isExecutableFile(atPath: p) { return p }
    return nil
  }

  static var isAvailable: Bool { path != nil }

  static var missingError: NSError {
    NSError(domain: "Vien", code: 2, userInfo: [
      NSLocalizedDescriptionKey: "Pandoc is not installed.",
      NSLocalizedRecoverySuggestionErrorKey: "Install it with “brew install pandoc” to import and export Word, OpenDocument, EPUB and LaTeX files.",
    ])
  }

  static func convert(markdown: String, to url: URL, format: String) async throws {
    guard let path else { throw missingError }
    try await run(path, ["-f", "gfm+tex_math_dollars+footnotes", "-t", format, "-s", "-o", url.path], input: Data(markdown.utf8))
  }

  static func importMarkdown(from url: URL) async throws -> String {
    guard let path else { throw missingError }
    let out = try await run(path, [url.path, "-t", "gfm", "--wrap=none"], input: nil)
    return String(decoding: out, as: UTF8.self)
  }

  @discardableResult
  private static func run(_ path: String, _ args: [String], input: Data?) async throws -> Data {
    try await withCheckedThrowingContinuation { c in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: path)
      p.arguments = args
      let out = Pipe(), err = Pipe()
      p.standardOutput = out
      p.standardError = err
      if let input {
        let inPipe = Pipe()
        p.standardInput = inPipe
        p.terminationHandler = { proc in
          let data = out.fileHandleForReading.readDataToEndOfFile()
          if proc.terminationStatus == 0 { c.resume(returning: data) } else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            c.resume(throwing: NSError(domain: "Vien", code: 3, userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Pandoc failed." : msg]))
          }
        }
        do { try p.run() } catch { c.resume(throwing: error); return }
        inPipe.fileHandleForWriting.write(input)
        try? inPipe.fileHandleForWriting.close()
      } else {
        p.terminationHandler = { proc in
          let data = out.fileHandleForReading.readDataToEndOfFile()
          if proc.terminationStatus == 0 { c.resume(returning: data) } else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            c.resume(throwing: NSError(domain: "Vien", code: 3, userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Pandoc failed." : msg]))
          }
        }
        do { try p.run() } catch { c.resume(throwing: error) }
      }
    }
  }
}

extension HTMLExport {
  nonisolated static func escape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
  }
}
