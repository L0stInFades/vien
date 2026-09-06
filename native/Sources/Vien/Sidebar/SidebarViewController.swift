import AppKit
import VienMarkdown

/// Files, outline and search in one sidebar, switched with a segmented control like Finder's view
/// switcher. Each pane is its own view controller.
final class SidebarViewController: NSViewController {
  enum Pane: Int { case files = 0, outline, search }

  unowned let windowController: DocumentWindowController
  private(set) var pane: Pane = .outline
  private let container = NSView()
  let files: FileTreeViewController
  let outline: OutlineViewController
  let search: SearchViewController

  init(window: DocumentWindowController) {
    windowController = window
    files = FileTreeViewController(window: window)
    outline = OutlineViewController(window: window)
    search = SearchViewController(window: window)
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func loadView() {
    view = NSView()
    container.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(container)
    // The container fills the sidebar; its top tracks the safe area so content clears the toolbar.
    NSLayoutConstraint.activate([
      container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    for child in [files, outline, search] as [NSViewController] {
      addChild(child)
      child.view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(child.view)
      NSLayoutConstraint.activate([
        child.view.topAnchor.constraint(equalTo: container.topAnchor),
        child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      ])
    }
    show(.outline)
  }

  func show(_ p: Pane) {
    pane = p
    windowController.updatePaneSwitcher(p)
    files.view.isHidden = p != .files
    outline.view.isHidden = p != .outline
    search.view.isHidden = p != .search
    if p == .search { search.focusSearchField() }
  }

  func outlineChanged() { outline.reload() }
  func selectionMoved(toUTF16 location: Int) { outline.highlight(utf16: location) }
}
