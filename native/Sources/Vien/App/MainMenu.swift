import AppKit

/// The menu bar, mirroring the original app's commands with standard macOS placement and keys.
enum MainMenu {
  static func build() -> NSMenu {
    let main = NSMenu()
    main.addItem(app())
    main.addItem(file())
    main.addItem(edit())
    main.addItem(paragraph())
    main.addItem(format())
    main.addItem(view())
    main.addItem(window())
    main.addItem(help())
    return main
  }

  private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
    i.keyEquivalentModifierMask = mods
    i.target = target
    return i
  }

  private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
    let m = NSMenu(title: title)
    for i in items { m.addItem(i) }
    let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    holder.submenu = m
    return holder
  }

  /// The Table submenu; also offered in the editor's context menu when the caret is in a table.
  static func tableItems() -> [NSMenuItem] {
    [
      item("Insert Table…", #selector(EditorViewController.insertTable(_:)), "t", [.command, .shift]),
      item("Format Table", #selector(EditorViewController.formatTable(_:)), "t", [.command, .shift, .option]),
      .separator(),
      item("Add Row Above", #selector(EditorViewController.addRowAbove(_:))),
      item("Add Row Below", #selector(EditorViewController.addRowBelow(_:)), "\r"),
      item("Add Column Before", #selector(EditorViewController.addColumnBefore(_:))),
      item("Add Column After", #selector(EditorViewController.addColumnAfter(_:))),
      .separator(),
      item("Move Row Up", #selector(EditorViewController.moveRowUp(_:))),
      item("Move Row Down", #selector(EditorViewController.moveRowDown(_:))),
      item("Move Column Left", #selector(EditorViewController.moveColumnLeft(_:))),
      item("Move Column Right", #selector(EditorViewController.moveColumnRight(_:))),
      .separator(),
      item("Delete Row", #selector(EditorViewController.deleteRow(_:))),
      item("Delete Column", #selector(EditorViewController.deleteColumn(_:))),
      .separator(),
      submenu("Align Column", [
        item("Left", #selector(EditorViewController.alignColumnLeft(_:))),
        item("Center", #selector(EditorViewController.alignColumnCenter(_:))),
        item("Right", #selector(EditorViewController.alignColumnRight(_:))),
        item("Default", #selector(EditorViewController.alignColumnNone(_:))),
      ]),
    ]
  }

  private static func app() -> NSMenuItem {
    let name = "Vien"
    return submenu(name, [
      item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
      .separator(),
      item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
      .separator(),
      { let s = submenu("Services", []); NSApp.servicesMenu = s.submenu; return s }(),
      .separator(),
      item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"),
      item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
      item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
      .separator(),
      item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"),
    ])
  }

  private static func file() -> NSMenuItem {
    let recentFolders = Workspace.shared.recentFolders.map { url -> NSMenuItem in
      let i = item(url.lastPathComponent, #selector(AppDelegate.openRecentFolder(_:)))
      i.representedObject = url
      i.toolTip = url.path
      return i
    }
    return submenu("File", [
      item("New", #selector(NSDocumentController.newDocument(_:)), "n"),
      item("New Window", #selector(NSDocumentController.newDocument(_:)), "n", [.command, .shift]),
      item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"),
      item("Open Folder…", #selector(AppDelegate.openFolder(_:)), "o", [.command, .shift]),
      { let s = submenu("Open Recent", []); s.submenu?.perform(NSSelectorFromString("_setMenuName:"), with: "NSRecentDocumentsMenu"); return s }(),
      submenu("Recent Folders", recentFolders),
      item("Quick Open…", #selector(AppDelegate.quickOpen(_:)), "p"),
      .separator(),
      item("Close", #selector(NSWindow.performClose(_:)), "w"),
      item("Save", #selector(NSDocument.save(_:)), "s"),
      item("Save As…", #selector(NSDocument.saveAs(_:)), "S", [.command, .shift]),
      item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]),
      item("Rename…", #selector(NSDocument.rename(_:))),
      item("Move To…", #selector(NSDocument.move(_:))),
      item("Revert To Saved", #selector(NSDocument.revertToSaved(_:)), "r"),
      item("Browse All Versions…", #selector(NSDocument.browseVersions(_:))),
      .separator(),
      item("Show in Finder", #selector(MarkdownFile.showInFinder(_:))),
      item("Copy Path", #selector(MarkdownFile.copyPath(_:))),
      submenu("Encoding", ["UTF-8", "UTF-8 with BOM", "UTF-16"].map { name -> NSMenuItem in
        let i = item(name, #selector(MarkdownFile.changeEncoding(_:)))
        i.representedObject = name
        return i
      }),
      .separator(),
      item("Import…", #selector(MarkdownFile.importWithPandoc(_:))),
      submenu("Export", [
        item("HTML…", #selector(MarkdownFile.exportHTML(_:))),
        item("PDF…", #selector(MarkdownFile.exportPDF(_:))),
        item("Word (.docx)…", #selector(MarkdownFile.exportDocx(_:))),
      ]),
      .separator(),
      item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "P", [.command, .shift]),
      item("Print…", #selector(NSDocument.printDocument(_:)), "p"),
    ])
  }

  private static func edit() -> NSMenuItem {
    let lineEndings = TextCodec.LineEnding.allCases.map { ending -> NSMenuItem in
      let names: [TextCodec.LineEnding: String] = [.lf: "Line Feed (LF)", .crlf: "Carriage Return and Line Feed (CRLF)", .cr: "Carriage Return (CR)"]
      let i = item(names[ending]!, #selector(MarkdownFile.convertLineEndings(_:)))
      i.representedObject = ending.rawValue
      return i
    }
    return submenu("Edit", [
      item("Undo", Selector(("undo:")), "z"),
      item("Redo", Selector(("redo:")), "Z", [.command, .shift]),
      .separator(),
      item("Cut", #selector(NSText.cut(_:)), "x"),
      item("Copy", #selector(NSText.copy(_:)), "c"),
      item("Paste", #selector(NSText.paste(_:)), "v"),
      item("Paste as Plain Text", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .shift]),
      item("Copy as Markdown", #selector(EditorViewController.copyAsMarkdown(_:)), "c", [.command, .shift]),
      item("Copy as HTML", #selector(EditorViewController.copyAsHTML(_:))),
      item("Delete", #selector(NSText.delete(_:))),
      item("Select All", #selector(NSText.selectAll(_:)), "a"),
      .separator(),
      item("Duplicate Paragraph", #selector(EditorViewController.duplicateParagraph(_:)), "d", [.command, .option]),
      item("New Paragraph", #selector(EditorViewController.createParagraph(_:)), "n", [.command, .shift, .option]),
      item("Delete Paragraph", #selector(EditorViewController.deleteParagraph(_:)), "d", [.command, .shift]),
      .separator(),
      submenu("Find", [
        { let i = item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f"); i.tag = 1; return i }(),
        { let i = item("Find and Replace…", #selector(NSTextView.performFindPanelAction(_:)), "f", [.command, .option]); i.tag = 12; return i }(),
        { let i = item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g"); i.tag = 2; return i }(),
        { let i = item("Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "G", [.command, .shift]); i.tag = 3; return i }(),
        { let i = item("Use Selection for Find", #selector(NSTextView.performFindPanelAction(_:)), "e"); i.tag = 7; return i }(),
        .separator(),
        item("Find in Folder…", #selector(DocumentWindowController.findInFolder(_:)), "f", [.command, .shift]),
      ]),
      submenu("Spelling and Grammar", [
        item("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":"),
        item("Check Document Now", #selector(NSText.checkSpelling(_:)), ";"),
        .separator(),
        item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))),
        item("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:))),
      ]),
      submenu("Line Endings", lineEndings),
      .separator(),
      item("Start Dictation…", Selector(("startDictation:"))),
      item("Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control]),
    ])
  }

  private static func paragraph() -> NSMenuItem {
    submenu("Paragraph", [
      item("Heading 1", #selector(EditorViewController.setHeading1(_:)), "1"),
      item("Heading 2", #selector(EditorViewController.setHeading2(_:)), "2"),
      item("Heading 3", #selector(EditorViewController.setHeading3(_:)), "3"),
      item("Heading 4", #selector(EditorViewController.setHeading4(_:)), "4"),
      item("Heading 5", #selector(EditorViewController.setHeading5(_:)), "5"),
      item("Heading 6", #selector(EditorViewController.setHeading6(_:)), "6"),
      item("Paragraph", #selector(EditorViewController.setParagraph(_:)), "0"),
      .separator(),
      item("Promote Heading", #selector(EditorViewController.promoteHeading(_:)), "=", [.command]),
      item("Demote Heading", #selector(EditorViewController.demoteHeading(_:)), "-", [.command, .shift]),
      .separator(),
      submenu("Table", tableItems()),
      item("Code Fences", #selector(EditorViewController.insertCodeFence(_:)), "c", [.command, .option]),
      item("Math Block", #selector(EditorViewController.insertMathBlock(_:)), "m", [.command, .option]),
      item("Quote Block", #selector(EditorViewController.toggleBlockQuote(_:)), "q", [.command, .option]),
      item("HTML Block", #selector(EditorViewController.insertHTMLBlock(_:)), "j", [.command, .option]),
      .separator(),
      item("Ordered List", #selector(EditorViewController.toggleOrderedList(_:)), "o", [.command, .option]),
      item("Bullet List", #selector(EditorViewController.toggleBulletList(_:)), "u", [.command, .option]),
      item("Task List", #selector(EditorViewController.toggleTaskList(_:)), "x", [.command, .option]),
      item("Loose List Item", #selector(EditorViewController.toggleLooseList(_:)), "l", [.command, .option]),
      .separator(),
      item("Horizontal Rule", #selector(EditorViewController.insertHorizontalRule(_:)), "-", [.command, .option]),
      item("Front Matter", #selector(EditorViewController.insertFrontMatter(_:)), "y", [.command, .option]),
    ])
  }

  private static func format() -> NSMenuItem {
    submenu("Format", [
      item("Bold", #selector(EditorViewController.toggleBold(_:)), "b"),
      item("Italic", #selector(EditorViewController.toggleItalic(_:)), "i"),
      item("Underline", #selector(EditorViewController.toggleUnderline(_:)), "u"),
      item("Strikethrough", #selector(EditorViewController.toggleStrikethrough(_:)), "d"),
      item("Highlight", #selector(EditorViewController.toggleHighlight(_:)), "h", [.command, .shift]),
      item("Superscript", #selector(EditorViewController.toggleSuperscript(_:))),
      item("Subscript", #selector(EditorViewController.toggleSubscript(_:))),
      .separator(),
      item("Inline Code", #selector(EditorViewController.toggleInlineCode(_:)), "`"),
      item("Inline Math", #selector(EditorViewController.toggleInlineMath(_:)), "m", [.command, .shift]),
      .separator(),
      item("Link", #selector(EditorViewController.insertLink(_:)), "l"),
      item("Image…", #selector(EditorViewController.insertImage(_:)), "i", [.command, .shift]),
      .separator(),
      item("Clear Formatting", #selector(EditorViewController.clearFormatting(_:)), "r", [.command, .shift]),
    ])
  }

  private static func view() -> NSMenuItem {
    submenu("View", [
      item("Source Code Mode", #selector(EditorViewController.toggleSourceMode(_:)), "s", [.command, .option]),
      item("Typewriter Mode", #selector(EditorViewController.toggleTypewriterMode(_:)), "t", [.command, .option]),
      item("Focus Mode", #selector(EditorViewController.toggleFocusMode(_:)), "j", [.command, .shift]),
      .separator(),
      item("Toggle Sidebar", #selector(DocumentWindowController.toggleSidebar(_:)), "j"),
      item("Toggle Outline", #selector(DocumentWindowController.toggleOutline(_:)), "k"),
      .separator(),
      item("Reload Images", #selector(EditorViewController.reloadImages(_:)), "r", [.command, .option]),
      .separator(),
      item("Actual Size", #selector(EditorViewController.zoomActualSize(_:)), "0", [.command, .control]),
      item("Zoom In", #selector(EditorViewController.zoomIn(_:)), "+", [.command]),
      item("Zoom Out", #selector(EditorViewController.zoomOut(_:)), "_", [.command]),
      .separator(),
      item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
    ])
  }

  private static func window() -> NSMenuItem {
    let w = submenu("Window", [
      item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
      item("Zoom", #selector(NSWindow.performZoom(_:))),
      .separator(),
      item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:)), "\t", [.control, .shift]),
      item("Show Next Tab", #selector(NSWindow.selectNextTab(_:)), "\t", [.control]),
      item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:))),
      item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:))),
      .separator(),
      item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
    ])
    NSApp.windowsMenu = w.submenu
    return w
  }

  private static func help() -> NSMenuItem {
    let h = submenu("Help", [
      item("Markdown Reference", #selector(AppDelegate.openMarkdownReference(_:))),
      item("Vien on GitHub", #selector(AppDelegate.openWebsite(_:))),
      item("Report an Issue…", #selector(AppDelegate.reportIssue(_:))),
    ])
    NSApp.helpMenu = h.submenu
    return h
  }
}
