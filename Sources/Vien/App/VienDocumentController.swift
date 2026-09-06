import AppKit

/// Opening a folder (from File ▸ Open, the Dock, or the command line) opens it as a workspace in
/// the sidebar instead of failing like a document would.
final class VienDocumentController: NSDocumentController {
  override func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void) {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
      (NSApp.delegate as? AppDelegate)?.open(folder: url)
      completionHandler(nil, false, nil)
      return
    }
    super.openDocument(withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
  }

  override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = true
    openPanel.allowsMultipleSelection = true
    openPanel.message = "Open a Markdown file, or a folder to browse it in the sidebar."
    return super.runModalOpenPanel(openPanel, forTypes: types)
  }

  override func typeForContents(of url: URL) throws -> String {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return "public.folder" }
    return MarkdownFile.markdownType
  }

  // The following make the controller work without a bundle Info.plist (`swift run`).
  override var defaultType: String? { MarkdownFile.markdownType }
  override func documentClass(forType typeName: String) -> AnyClass? { MarkdownFile.self }
  override func displayName(forType typeName: String) -> String { "Markdown Document" }
}
