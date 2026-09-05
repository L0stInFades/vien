import AppKit
import VienMarkdown

/// Files, outline and search in one sidebar, switched with a segmented control like Finder's view
/// switcher. Each pane is its own view controller.
final class SidebarViewController: NSViewController {
  enum Pane: Int { case files = 0, outline, search }

  unowned let windowController: DocumentWindowController
  private(set) var pane: Pane = .outline
  private let segments = NSSegmentedControl(images: [
    NSImage(systemSymbolName: "folder", accessibilityDescription: "Files")!,
    NSImage(systemSymbolName: "list.bullet.indent", accessibilityDescription: "Outline")!,
    NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")!,
  ], trackingMode: .selectOne, target: nil, action: nil)
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
    segments.segmentStyle = .automatic
    segments.controlSize = .small
    segments.target = self
    segments.action = #selector(switchPane)
    segments.translatesAutoresizingMaskIntoConstraints = false
    container.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(segments)
    view.addSubview(container)
    NSLayoutConstraint.activate([
      segments.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      segments.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      container.topAnchor.constraint(equalTo: segments.bottomAnchor, constant: 8),
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
    segments.selectedSegment = p.rawValue
    files.view.isHidden = p != .files
    outline.view.isHidden = p != .outline
    search.view.isHidden = p != .search
    if p == .search { search.focusSearchField() }
  }

  @objc private func switchPane() {
    show(Pane(rawValue: segments.selectedSegment) ?? .outline)
  }

  func outlineChanged() { outline.reload() }
  func selectionMoved(toUTF16 location: Int) { outline.highlight(utf16: location) }
}
