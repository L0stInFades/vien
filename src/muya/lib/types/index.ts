/**
 * Core type definitions for muya editor engine.
 * These types are shared across contentState, parser, selection, ui, and utils.
 */

// ---------------------------------------------------------------------------
// Block
// ---------------------------------------------------------------------------

export type BlockType =
  | 'span'
  | 'p'
  | 'div'
  | 'h1'
  | 'h2'
  | 'h3'
  | 'h4'
  | 'h5'
  | 'h6'
  | 'pre'
  | 'code'
  | 'ul'
  | 'ol'
  | 'li'
  | 'blockquote'
  | 'figure'
  | 'table'
  | 'thead'
  | 'tbody'
  | 'tr'
  | 'td'
  | 'th'
  | 'hr'
  | 'input'
  | 'root'
  | string // allow unknown block types from extensions

export type BlockFunctionType =
  | 'paragraphContent'
  | 'codeContent'
  | 'cellContent'
  | 'languageInput'
  | 'atxLine'
  | 'thematicBreakLine'
  | 'footnoteInput'
  | 'html'
  | 'table'
  | 'footnote'
  | 'frontmatter'
  | 'indentcode'
  | 'fencecode'
  | string

export type BlockAlign = 'left' | 'center' | 'right' | ''
export type ListType = 'bullet' | 'order' | 'task'
export type ListItemType = 'bullet' | 'order' | 'task'
export type HeadingStyle = 'atx' | 'setext'

export interface Block {
  key: string
  type: BlockType
  text: string
  editable: boolean
  parent: string | null
  preSibling: string | null
  nextSibling: string | null
  children: Block[]

  // Semantic role
  functionType?: BlockFunctionType

  // Heading
  headingStyle?: HeadingStyle
  marker?: string

  // Code block
  lang?: string

  // List container
  listType?: ListType
  start?: number | string

  // List item
  listItemType?: ListItemType
  bulletMarkerOrDelimiter?: string
  isLooseListItem?: boolean

  // Checkbox (task list)
  checked?: boolean

  // Table container
  row?: number
  column?: number

  // Table cell
  align?: BlockAlign

  // Diagram / misc
  style?: string

  // Dynamic properties attached by various controllers
  [key: string]: unknown
}

// ---------------------------------------------------------------------------
// Cursor / Selection
// ---------------------------------------------------------------------------

export interface CursorPosition {
  key: string
  offset: number
  delata?: number
}

export interface Cursor {
  start: CursorPosition
  end: CursorPosition
  anchor?: CursorPosition
  focus?: CursorPosition
  noHistory?: boolean
}

export interface CursorRange {
  anchor: CursorPosition
  focus: CursorPosition
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

export interface HistoryRecord {
  blocks: Block[]
  cursor: Cursor
}

export interface IHistoryState {
  blocks: Block[]
  cursor: Cursor & { noHistory?: boolean }
  renderRange: [string | null, string | null]
}

export interface IHistory {
  stack: IHistoryState[]
  index: number
  push(state: IHistoryState): void
  pushPending(state: IHistoryState): void
  commitPending(): void
  undo(): void
  redo(): void
  clearHistory(): void
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

export interface SearchMatch {
  key: string
  index: number
  start: number
  end: number
  active: boolean
  [key: string]: unknown
}

export interface SearchMatches {
  value: string
  matches: SearchMatch[]
  index: number
}

// ---------------------------------------------------------------------------
// Token — inline token produced by tokenizer()
// ---------------------------------------------------------------------------

export interface TokenRange {
  start: number
  end: number
}

export interface Token extends Record<string, unknown> {
  type: string
  raw: string
  range: TokenRange
  children?: Token[]
  highlights?: unknown[]
  tag?: string
  content?: string
  alt?: string
  src?: string
  marker?: string
  backlash?: Record<string, unknown>
  parent?: Token[]
  srcAndTitle?: string
  hrefAndTitle?: string
}

export interface SelectedImage extends Record<string, unknown> {
  key: string
  token: {
    raw: string
    range: TokenRange
    attrs?: Record<string, string>
    [key: string]: unknown
  }
  imageId?: string
}

// ---------------------------------------------------------------------------
// SelectionInfo — return type of selectionChange()
// ---------------------------------------------------------------------------

export type SelectionCursorPos = CursorPosition & { type?: string; block?: Block }

// LineCursor — first param of replaceWordInline (cursor carrying a block reference)
export interface LineCursor {
  start: CursorPosition & { block: Block }
  end: CursorPosition
}

export interface SelectionInfo {
  start: SelectionCursorPos
  end: SelectionCursorPos
  affiliation: Block[]
  cursorCoords: unknown
}

// ---------------------------------------------------------------------------
// SelectionFormatsResult — return type of selectionFormats()
// ---------------------------------------------------------------------------

export interface SelectionFormatsResult {
  formats: Token[]
  tokens: Token[]
  neighbors: Token[]
}

// ---------------------------------------------------------------------------
// DragInfo / CellSelectInfo — typed replacements for unknown
// ---------------------------------------------------------------------------

export interface IDragInfo {
  cells?: HTMLElement[][]
  dragCells?: HTMLElement[]
  curIndex?: number
  tableId?: string
  barType?: 'left' | 'bottom'
  index?: number
  offset?: number
  aspects?: number[]
  clientX?: number
  clientY?: number
  [key: string]: unknown
}

export interface ICellSelectInfo {
  tableId?: string
  anchor?: { key: string; row: number; column: number }
  focus?: { key: string; row: number; column: number } | null
  isStartSelect?: boolean
  cells?: HTMLElement[][]
  selectedCells?: Block[]
  [key: string]: unknown
}

// ---------------------------------------------------------------------------
// IContentState — interface covering all prototype methods from all mixin files.
// Use `this: IContentState` in mixin methods to avoid `any`.
// ---------------------------------------------------------------------------

export interface IContentState {
  // Core state
  muya: IMuya
  blocks: Block[]
  currentCursor: Cursor | null
  prevCursor: Cursor | null
  editingContainerKey: string | null
  selectedBlock: Block | null
  history: IHistory
  stateRender: IStateRender
  renderRange: [string | null, string | null]
  exemption: Set<string>
  searchMatches: SearchMatches
  dragInfo: IDragInfo | null
  isDragTableBar: boolean
  dragEventIds: string[]
  cellSelectInfo: ICellSelectInfo | null
  cellSelectEventIds: string[]
  turndownConfig: unknown
  resizeLineNumber: () => void
  tabSize: number
  isGitlabCompatibilityEnabled: boolean
  listIndentation: string | number
  /** Per-instance code block render throttle (CORE-003). */
  _renderCodeBlockTimer: ReturnType<typeof setTimeout> | null

  // Block tree traversal
  getBlock(key: string | null | undefined): Block | null
  getParent(block: Block): Block | null
  getParents(block: Block): Block[]
  getPreSibling(block: Block): Block | null
  getNextSibling(block: Block): Block | null
  getLastChild(block: Block): Block | null
  isInclude(parent: Block, target: Block): boolean
  isFirstChild(block: Block): boolean
  isLastChild(block: Block): boolean
  isOnlyChild(block: Block): boolean
  isOnlyRemoveableChild(block: Block): boolean
  findIndex(children: Block[], block: Block): number
  firstInDescendant(block: Block): Block | null
  lastInDescendant(block: Block): Block | null
  findOutMostBlock(block: Block): Block
  findPreBlockInLocation(block: Block): Block | null
  findNextBlockInLocation(block: Block): Block | null
  closest(block: Block | null, type: string | RegExp): Block | null
  getAnchor(block: Block): Block | null

  // Block tree modification
  appendChild(parent: Block, block: Block): void
  prependChild(parent: Block, block: Block): void
  insertAfter(newBlock: Block, oldBlock: Block): void
  insertBefore(newBlock: Block, oldBlock: Block): void
  replaceBlock(newBlock: Block, oldBlock: Block): void
  removeBlock(block: Block, fromBlocks?: Block[] | { children: Block[] }): void
  removeBlocks(before: Block, after: Block, isRemoveAfter?: boolean, isRecursion?: boolean): void

  // Block factories
  createBlock(type?: string, extras?: Partial<Block>): Block
  copyBlock(origin: Block): Block
  createBlockP(text?: string): Block

  // Cursor & selection
  getCursor(): Cursor
  setCursor(): void
  isCollapse(cursor?: Cursor): boolean
  getActiveBlocks(): Block[]
  getBlocks(): Block[]
  getFirstBlock(): Block | null
  getLastBlock(): Block | null

  // Rendering
  render(isRenderCursor?: boolean, clearCache?: boolean): void
  partialRender(isRenderCursor?: boolean): void
  singleRender(block: Block, isRenderCursor?: boolean): void
  setNextRenderRange(): void
  postRender(): void

  // Misc
  removeTextOrBlock(block: Block): void
  getPositionReference(): {
    getBoundingClientRect(): {
      x: number
      y: number
      top: number
      left: number
      right: number
      bottom: number
      height: number
      width: number
    }
    clientWidth: number
    clientHeight: number
    id: string | null
  }

  // Cursor property (mutable, used by event handlers)
  cursor: Cursor

  // Selected state
  selectedImage: SelectedImage | null
  selectedTableCells: {
    tableId: string
    row: number
    column: number
    cells: Array<{ key: string; [key: string]: unknown }>
    [key: string]: unknown
  } | null

  // Event handler methods (keyboard/clipboard/click/mouse/drag controllers)
  inputHandler(event: Event): void
  enterHandler(event: KeyboardEvent): void
  backspaceHandler(event: KeyboardEvent): void
  deleteHandler(event: KeyboardEvent): void
  arrowHandler(event: KeyboardEvent): void
  tabHandler(event: KeyboardEvent): void
  clickHandler(event: MouseEvent): void
  docEnterHandler(event: KeyboardEvent): void
  docBackspaceHandler(event: KeyboardEvent): void
  docDeleteHandler(event: KeyboardEvent): void
  docArrowHandler(event: KeyboardEvent): void
  docPasteHandler(event: ClipboardEvent): void
  docCopyHandler(event: ClipboardEvent): void
  docCutHandler(event: ClipboardEvent): void
  copyHandler(event: ClipboardEvent, copyType: string, copyInfo: unknown): void
  cutHandler(): void
  pasteHandler(
    event: ClipboardEvent,
    type?: string,
    rawText?: string | null,
    rawHtml?: string | null,
  ): Promise<void> | void
  dragoverHandler(event: DragEvent): void
  dropHandler(event: DragEvent): void
  dragleaveHandler(event: DragEvent): void
  handleMouseDown(event: Event): void
  handleCellMouseDown(event: Event): void

  // Selection & formatting
  selectionChange(cursor?: unknown): SelectionInfo
  selectionFormats(cursor?: { start?: CursorPosition; end?: CursorPosition }): SelectionFormatsResult
  checkNeedRender(cursor: unknown): boolean
  checkEditLanguage(): { lang: string | null; paragraph: HTMLElement | null }
  selectLanguage(paragraph: HTMLElement | null, name: string): void

  // Table
  tableToolBarClick(type: string | null): void

  // Image
  selectImage(imageInfo: unknown): void
  deleteImage(imageInfo: unknown): void
  copyCodeBlock(event: Event): void

  // Container block
  handleContainerBlockClick(element: unknown): void

  // Checkbox
  listItemCheckBoxClick(checkbox: HTMLInputElement): void

  // Format & editing
  format(type: string): void
  duplicate(): void
  deleteParagraph(key?: string): void
  insertParagraph(position: string, text?: string, flag?: boolean): void
  updateParagraph(label: string, flag?: boolean): void
  unlink(linkInfo: unknown): void
  editTable(item: { action: string; [key: string]: unknown }, cellContentKey?: string | null): void
  canInserFrontMatter(block: unknown): boolean

  // Image operations
  replaceImage(imageInfo: unknown, attrs: Record<string, string>): void
  updateImage(imageInfo: unknown, attr: string, value: unknown): void
  setEmoji(item: unknown): void
  createFootnote(identifier: unknown): void
  insertImage(imageInfo: Record<string, unknown>): void

  // History
  getHistory(): unknown
  setHistory(history: { stack: unknown[]; index: number }): void

  // Table
  createTable(tableChecker: unknown): unknown

  // TOC
  getTOC(): unknown

  // Cursor / markdown I/O (mixin-provided)
  getCodeMirrorCursor(): Cursor
  addCursorToMarkdown(markdown: string, cursor: Cursor): { markdown: string; isValid: boolean }
  importMarkdown(markdown: string): void
  importCursor(cursor: Cursor | boolean | null | undefined): void

  // Search (mixin-provided)
  search(value: string, opt: unknown): void
  replace(value: string, opt: unknown): void
  find(action: string): void

  // Misc (mixin-provided)
  selectAll(): void
  extractImages(markdown: string): unknown
  replaceWordInline(
    line: LineCursor,
    wordCursor: { start: CursorPosition; end: CursorPosition },
    replacement: string,
    setCursor?: boolean,
  ): void
  _replaceCurrentWordInlineUnsafe(word: string, replacement: string): unknown

  // Arrow / cell navigation (arrowCtrl, tableBlockCtrl)
  findNextRowCell(block: Block): Block | null
  findPrevRowCell(block: Block): Block | null
  getTableBlock(): Block | null
  findPreviousCell(block: Block): Block | null
  findNextCell(block: Block): Block | null

  // Backspace / delete (backspaceCtrl, deleteCtrl)
  deleteSelectedTableCells(isCopy?: boolean): void
  isSelectAll(): boolean
  updateToParagraph(block: Block, line?: Block): Block | undefined
  checkBackspaceCase(): unknown
  checkInlineUpdate(block: Block): boolean | Block

  // Click / checkbox (clickCtrl)
  codeBlockUpdate(block: Block): boolean
  setCheckBoxState(checkbox: HTMLInputElement, checked: boolean): void
  updateChildrenCheckBoxState(checkbox: HTMLInputElement, checked: boolean): void
  updateParentsCheckBoxState(checkbox: HTMLInputElement): void

  // Code block (codeBlockCtrl)
  updateMathBlock(block: Block): Block | false
  updateCodeLanguage(block: Block, lang: string): void

  // Container (containerCtrl)
  createPreAndPreview(functionType: string, value?: string): { preBlock: Block; preview: Block }
  initContainerBlock(functionType: string, block: Block, mathStyle?: string): Block | false

  // Copy/cut (copyCutCtrl)
  htmlToMarkdown(html: string): string
  createTableInFigure(dimensions: unknown, contents?: unknown): Block
  getClipBoardData(): { html: string; text: string }

  // Drag/drop (dragDropCtrl)
  hideGhost(): void
  createGhost(event: DragEvent): void

  // Enter (enterCtrl)
  chopBlock(block: Block): Block
  createTaskItemBlock(block: Block | null, checked: boolean): Block
  createBlockLi(block?: Block | null): Block
  updateFootnote(parent: Block, block: Block): Block | undefined
  createRow(row: Block, isHeader?: boolean): Block
  chopBlockByCursor(block: Block, key: string, offset: number): Block
  enterInEmptyParagraph(block: Block): void
  tableBlockUpdate(block: Block): Block | false
  updateHtmlBlock(block: Block): Block | false

  // Format (formatCtrl)
  clearBlockFormat(block: Block, range: unknown, formatType: string | undefined): void

  // HTML block
  initHtmlBlock(block: Block): Block | false
  insertHtmlBlock(block: Block): void

  // Input (inputCtrl)
  checkCursorInTokenType(functionType: string, text: string, offset: number, tokenType: string): boolean
  checkNotSameToken(functionType: string, text: string, newText: string): boolean
  checkQuickInsert(block: Block): unknown

  // Paragraph (paragraphCtrl)
  updateList(block: Block, listType: string, marker?: string, line?: Block): Block | undefined
  updateTaskListItem(block: Block, listType?: string, tasklist?: unknown): Block | undefined
  getCommonParent(): { parent: Block | null; startIndex: number; endIndex: number }
  markdownToState(markdown: string): Block[]
  createContainerBlock(functionType: string, value: string): Block
  isAllowedTransformation(block: Block, paraType: string, isMultiBlock?: boolean): boolean
  getTypeFromBlock(block: Block): string
  handleFrontMatter(): void
  handleListMenu(paraType: string, insertMode?: string): boolean
  handleLooseListItem(): void
  handleCodeBlockMenu(): void
  handleQuoteMenu(insertMode?: string): void
  insertContainerBlock(type: string, block: Block): void
  showTablePicker(): void
  isSingleCellSelected(): Block | null
  isWholeTableSelected(): Block | null
  selectAllContent(): void
  selectTable(table: Block): void

  // Paste (pasteCtrl)
  pasteImage(event: ClipboardEvent): Promise<string | File | null>
  standardizeHTML(html: string): Promise<string>
  checkCopyType(html: string, text: string): string
  html2State(html: string): Block[]
  checkPasteType(block: Block, fragment: Block): string

  // Search (searchCtrl)
  buildRegexValue(match: unknown, replaceValue: string): string
  replaceOne(match: unknown, replaceValue: string): void
  setCursorToHighlight(index?: number): void

  // Tab (tabCtrl)
  isUnindentableListItem(block: Block): string | false
  unindentListItem(block: Block, type: string): void
  checkCursorAtEndFormat(text: string, offset: number): { offset: number } | null
  isIndentableListItem(): boolean
  indentListItem(): void
  insertTab(): void

  // Table block (tableBlockCtrl)
  createFigure(tableChecker: unknown): void
  initTable(block: Block): Block | false

  // Table drag bar (tableDragBarCtrl)
  hideUnnecessaryBar(): void
  calculateCurIndex(): void
  setDragTargetStyle(): void
  setSwitchStyle(): void
  setDropTargetStyle(): void
  switchTableData(): void
  resetDragTableBar(): void

  // Table cell select (tableSelectCellsCtrl)
  calculateSelectedCells(): void
  setSelectedCellsStyle(): void

  // Update (updateCtrl)
  updateThematicBreak(block: Block, hr: unknown, line: Block): Block | undefined
  updateAtxHeader(block: Block, atxHeader: unknown, line: Block): Block | undefined
  updateSetextHeader(block: Block, setextHeader: unknown, line: Block): Block | undefined
  updateBlockQuote(block: Block, line: Block): Block | undefined
  updateIndentCode(block: Block, line: Block): Block | undefined
  checkSameMarkerOrDelimiter(block: Block, delimiter: string): boolean

  // init (from contentState/index.ts)
  init(): void

  // Plugin/controller methods (added by mixin files — typed loosely here,
  // individual mixin files use `this: IContentState` for full coverage)
  [key: string]: unknown
}

// ---------------------------------------------------------------------------
// IMuya — top-level editor instance (minimal, avoids circular import)
// ---------------------------------------------------------------------------

export interface IMuya {
  options: MuyaOptions
  eventCenter: IEventCenter
  container: HTMLElement
  contentState: IContentState
  markdown: string
  blur(keepCursor?: boolean): void
  dispatchChange(): void
  dispatchSelectionChange(): void
  dispatchSelectionFormats(): void
  keyboard: { hideAllFloatTools(): void; isComposed?: boolean; [key: string]: unknown }
  clipboard: { copy(type: string, content: unknown): void; [key: string]: unknown }
  [key: string]: unknown
}

export interface MuyaOptions {
  markdown?: string
  autofocus?: boolean
  tabSize?: number
  listIndentation?: string | number
  frontMatter?: string
  preferLooseListItem?: boolean
  sequenceTheme?: string
  mermaidTheme?: string
  vegaTheme?: string
  hideQuickInsertHint?: boolean
  hideLinkPopup?: boolean
  autoCheck?: boolean
  imageAction?: (...args: unknown[]) => Promise<string>
  imagePathPicker?: unknown
  clipboardFilePath?: () => Promise<string>
  imageUploader?: unknown
  searchIsCaseSensitive?: boolean
  searchIsWholeWord?: boolean
  searchIsRegexp?: boolean
  footnote?: boolean
  [key: string]: unknown
}

// ---------------------------------------------------------------------------
// EventCenter
// ---------------------------------------------------------------------------

export type EventHandler = (...args: unknown[]) => void

export interface IEventCenter {
  on(event: string, handler: EventHandler): void
  off(event: string, handler: EventHandler): void
  emit(event: string, ...args: unknown[]): void
  once(event: string, handler: EventHandler): void

  // DOM event management (from EventCenter class)
  // biome-ignore lint/suspicious/noExplicitAny: EventListener accepts Event but callers pass specific subtypes (KeyboardEvent, etc.)
  attachDOMEvent(target: EventTarget, event: string, listener: (event: any) => void, capture?: boolean): string | false
  detachDOMEvent(eventId: string): void
  detachAllDomEvents(): void

  // Custom event pub/sub (from EventCenter class)
  subscribe(event: string, listener: (...args: unknown[]) => void): void
  unsubscribe(event: string, listener: (...args: unknown[]) => void): void
  subscribeOnce(event: string, listener: (...args: unknown[]) => void): void
  dispatch(event: string, ...data: unknown[]): void

  [key: string]: unknown
}

// ---------------------------------------------------------------------------
// StateRender
// ---------------------------------------------------------------------------

export interface IStateRender {
  tokenCache: Map<string, unknown>
  urlMap: Map<string, unknown>
  labels: Map<string, { href: string; title: string }>
  setContainer(container: HTMLElement): void
  collectLabels(blocks: Block[]): void
  render(blocks: Block[], activeBlocks: Block[], matches: SearchMatch[]): void
  partialRender(
    blocks: Block[],
    activeBlocks: Block[],
    matches: SearchMatch[],
    startKey: string | null,
    endKey: string | null,
  ): void
  singleRender(block: Block, activeBlocks: Block[], matches: SearchMatch[]): void
  invalidateImageCache(): void
}
