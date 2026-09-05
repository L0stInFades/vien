import AppKit
import Observation

/// User settings, stored in UserDefaults. Defaults follow the original app where it had an opinion
/// and macOS where it did not.
@Observable
final class Preferences {
  static let shared = Preferences()

  private let defaults = UserDefaults.standard

  private init() {
    fontSize = defaults.object(forKey: "fontSize") as? Double ?? 16
    lineHeight = defaults.object(forKey: "lineHeight") as? Double ?? 1.55
    contentWidth = defaults.object(forKey: "contentWidth") as? Double ?? 700
    fontFamily = defaults.string(forKey: "fontFamily") ?? ""
    codeFontFamily = defaults.string(forKey: "codeFontFamily") ?? ""
    typewriter = defaults.bool(forKey: "typewriter")
    focus = defaults.bool(forKey: "focus")
    sourceMode = defaults.bool(forKey: "sourceMode")
    autoPairBrackets = defaults.object(forKey: "autoPairBrackets") as? Bool ?? true
    autoPairMarkdown = defaults.object(forKey: "autoPairMarkdown") as? Bool ?? true
    autoPairQuotes = defaults.object(forKey: "autoPairQuotes") as? Bool ?? true
    tabSize = defaults.object(forKey: "tabSize") as? Int ?? 4
    bulletMarker = defaults.string(forKey: "bulletMarker") ?? "-"
    orderedDelimiter = defaults.string(forKey: "orderedDelimiter") ?? "."
    preferLooseLists = defaults.object(forKey: "preferLooseLists") as? Bool ?? true
    mathEnabled = defaults.object(forKey: "mathEnabled") as? Bool ?? true
    footnotesEnabled = defaults.object(forKey: "footnotesEnabled") as? Bool ?? true
    superSubScript = defaults.bool(forKey: "superSubScript")
    emojiEnabled = defaults.object(forKey: "emojiEnabled") as? Bool ?? true
    frontMatterKind = defaults.string(forKey: "frontMatterKind") ?? "---"
    imageInsertAction = defaults.string(forKey: "imageInsertAction") ?? "path"
    imageFolderName = defaults.string(forKey: "imageFolderName") ?? "assets"
    showFrontMatterInExport = defaults.bool(forKey: "showFrontMatterInExport")
    defaultEncodingUTF8BOM = defaults.bool(forKey: "defaultEncodingUTF8BOM")
    newDocumentLineEnding = defaults.string(forKey: "newDocumentLineEnding") ?? "\n"
    trimTrailingWhitespaceOnSave = defaults.bool(forKey: "trimTrailingWhitespaceOnSave")
    ensureFinalNewline = defaults.object(forKey: "ensureFinalNewline") as? Bool ?? true
  }

  // Typography
  var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
  var lineHeight: Double { didSet { defaults.set(lineHeight, forKey: "lineHeight") } }
  var contentWidth: Double { didSet { defaults.set(contentWidth, forKey: "contentWidth") } }
  /// Empty means the system font.
  var fontFamily: String { didSet { defaults.set(fontFamily, forKey: "fontFamily") } }
  var codeFontFamily: String { didSet { defaults.set(codeFontFamily, forKey: "codeFontFamily") } }

  // Modes
  var typewriter: Bool { didSet { defaults.set(typewriter, forKey: "typewriter") } }
  var focus: Bool { didSet { defaults.set(focus, forKey: "focus") } }
  var sourceMode: Bool { didSet { defaults.set(sourceMode, forKey: "sourceMode") } }

  // Editing
  var autoPairBrackets: Bool { didSet { defaults.set(autoPairBrackets, forKey: "autoPairBrackets") } }
  var autoPairMarkdown: Bool { didSet { defaults.set(autoPairMarkdown, forKey: "autoPairMarkdown") } }
  var autoPairQuotes: Bool { didSet { defaults.set(autoPairQuotes, forKey: "autoPairQuotes") } }
  var tabSize: Int { didSet { defaults.set(tabSize, forKey: "tabSize") } }
  var bulletMarker: String { didSet { defaults.set(bulletMarker, forKey: "bulletMarker") } }
  var orderedDelimiter: String { didSet { defaults.set(orderedDelimiter, forKey: "orderedDelimiter") } }
  var preferLooseLists: Bool { didSet { defaults.set(preferLooseLists, forKey: "preferLooseLists") } }

  // Markdown dialect
  var mathEnabled: Bool { didSet { defaults.set(mathEnabled, forKey: "mathEnabled") } }
  var footnotesEnabled: Bool { didSet { defaults.set(footnotesEnabled, forKey: "footnotesEnabled") } }
  var superSubScript: Bool { didSet { defaults.set(superSubScript, forKey: "superSubScript") } }
  var emojiEnabled: Bool { didSet { defaults.set(emojiEnabled, forKey: "emojiEnabled") } }
  var frontMatterKind: String { didSet { defaults.set(frontMatterKind, forKey: "frontMatterKind") } }

  // Images
  /// `path` keeps the original location, `copy` copies into `imageFolderName` next to the document.
  var imageInsertAction: String { didSet { defaults.set(imageInsertAction, forKey: "imageInsertAction") } }
  var imageFolderName: String { didSet { defaults.set(imageFolderName, forKey: "imageFolderName") } }

  // Export
  var showFrontMatterInExport: Bool { didSet { defaults.set(showFrontMatterInExport, forKey: "showFrontMatterInExport") } }

  // Files
  var defaultEncodingUTF8BOM: Bool { didSet { defaults.set(defaultEncodingUTF8BOM, forKey: "defaultEncodingUTF8BOM") } }
  var newDocumentLineEnding: String { didSet { defaults.set(newDocumentLineEnding, forKey: "newDocumentLineEnding") } }
  var trimTrailingWhitespaceOnSave: Bool { didSet { defaults.set(trimTrailingWhitespaceOnSave, forKey: "trimTrailingWhitespaceOnSave") } }
  var ensureFinalNewline: Bool { didSet { defaults.set(ensureFinalNewline, forKey: "ensureFinalNewline") } }
}
