import AppKit
import SwiftUI

/// Settings (⌘,) as a standard toolbar-style preferences window built with SwiftUI forms.
final class SettingsWindowController: NSWindowController {
  init() {
    let host = NSHostingController(rootView: SettingsView())
    let window = NSWindow(contentViewController: host)
    window.title = "Settings"
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    window.setContentSize(NSSize(width: 520, height: 420))
    window.center()
    super.init(window: window)
  }

  required init?(coder: NSCoder) { fatalError() }
}

struct SettingsView: View {
  @State private var prefs = Preferences.shared

  var body: some View {
    TabView {
      general.tabItem { Label("General", systemImage: "gearshape") }
      editor.tabItem { Label("Editor", systemImage: "textformat") }
      markdown.tabItem { Label("Markdown", systemImage: "number") }
      files.tabItem { Label("Files", systemImage: "doc") }
    }
    .frame(width: 520, height: 420)
  }

  private var general: some View {
    Form {
      Section("Updates") {
        Toggle("Check for updates automatically", isOn: $prefs.automaticUpdates)
        Text("Updates come from Vien’s GitHub releases. Each one is checked against its checksum and code signature before it replaces the app.").foregroundStyle(.secondary).font(.caption)
      }
      Section("Layout") {
        Slider(value: $prefs.contentWidth, in: 480...1100, step: 10) { Text("Line width") }
        Text("\(Int(prefs.contentWidth)) pt").foregroundStyle(.secondary).font(.caption)
      }
      Section("Images") {
        Picker("When inserting images", selection: $prefs.imageInsertAction) {
          Text("Keep original path").tag("path")
          Text("Copy into folder next to document").tag("copy")
        }
        TextField("Folder name", text: $prefs.imageFolderName)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var editor: some View {
    Form {
      Section("Appearance") {
        Picker("Theme", selection: $prefs.theme) {
          ForEach(Palette.all, id: \.name) { Text($0.name).tag($0.name) }
        }
      }
      Section("Typography") {
        Slider(value: $prefs.fontSize, in: 11...28, step: 1) { Text("Font size") }
        Text("\(Int(prefs.fontSize)) pt").foregroundStyle(.secondary).font(.caption)
        Slider(value: $prefs.lineHeight, in: 1.2...2.0, step: 0.05) { Text("Line height") }
        TextField("Text font (blank for system)", text: $prefs.fontFamily)
        TextField("Code font (blank for SF Mono)", text: $prefs.codeFontFamily)
      }
      Section("Typing") {
        Toggle("Auto-pair brackets", isOn: $prefs.autoPairBrackets)
        Toggle("Auto-pair quotes", isOn: $prefs.autoPairQuotes)
        Toggle("Auto-pair Markdown syntax (* _ ` $ ~)", isOn: $prefs.autoPairMarkdown)
        Stepper("Tab size: \(prefs.tabSize)", value: $prefs.tabSize, in: 2...8)
      }
      Section("Markup") {
        Toggle("Hide markup outside the current paragraph", isOn: $prefs.foldMarkup)
        Text("Links show their text, images and tables their rendering; the paragraph you are editing always shows its source.").foregroundStyle(.secondary).font(.caption)
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var markdown: some View {
    Form {
      Section("Lists") {
        Picker("Bullet marker", selection: $prefs.bulletMarker) {
          Text("-").tag("-"); Text("*").tag("*"); Text("+").tag("+")
        }
        Picker("Ordered list delimiter", selection: $prefs.orderedDelimiter) {
          Text("1.").tag("."); Text("1)").tag(")")
        }
      }
      Section("Extensions") {
        Toggle("Math ($…$ and $$ blocks)", isOn: $prefs.mathEnabled)
        Toggle("Footnotes", isOn: $prefs.footnotesEnabled)
        Toggle("Superscript ^x^ and subscript ~x~", isOn: $prefs.superSubScript)
        Toggle("Emoji shortcodes :smile:", isOn: $prefs.emojiEnabled)
        Picker("Front matter", selection: $prefs.frontMatterKind) {
          Text("YAML (---)").tag("---"); Text("TOML (+++)").tag("+++"); Text("JSON (;;;)").tag(";;;")
        }
      }
      Text("Changes apply to documents opened afterwards.").font(.caption).foregroundStyle(.secondary)
    }
    .formStyle(.grouped)
    .padding()
  }

  private var files: some View {
    Form {
      Section("Saving") {
        Toggle("Trim trailing whitespace", isOn: $prefs.trimTrailingWhitespaceOnSave)
        Toggle("Ensure file ends with a newline", isOn: $prefs.ensureFinalNewline)
      }
      Section("New documents") {
        Picker("Line endings", selection: $prefs.newDocumentLineEnding) {
          Text("LF (macOS, Linux)").tag("\n"); Text("CRLF (Windows)").tag("\r\n")
        }
        Toggle("Write UTF-8 byte order mark", isOn: $prefs.defaultEncodingUTF8BOM)
      }
      Section("Export") {
        Toggle("Include front matter", isOn: $prefs.showFrontMatterInExport)
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}
