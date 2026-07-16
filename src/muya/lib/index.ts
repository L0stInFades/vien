import ContentState from './contentState'
import EventCenter from './eventHandler/event'
import MuyaMouseEvent from './eventHandler/mouseEvent'
import Clipboard from './eventHandler/clipboard'
import Keyboard from './eventHandler/keyboard'
import DragDrop from './eventHandler/dragDrop'
import Resize from './eventHandler/resize'
import ClickEvent from './eventHandler/clickEvent'
import { CLASS_OR_ID, MUYA_DEFAULT_OPTION } from './config'
import { wordCount } from './utils'
import ExportMarkdown from './utils/exportMarkdown'
import ExportHtml from './utils/exportHtml'
import StateRender from './parser/render'
import ToolTip from './ui/tooltip'
import type { Cursor, MuyaOptions, Block, SearchMatches, IMuya, LineCursor, CursorPosition } from './types'
import './assets/styles/index.css'

interface PluginEntry {
  plugin: { pluginName: string; new (...args: unknown[]): unknown }
  options: Record<string, unknown>
}

interface SearchOptions {
  selectHighlight?: boolean
  isCaseSensitive?: boolean
  isWholeWord?: boolean
  isRegexp?: boolean
}

interface FontOptions {
  fontSize?: string | number
  lineHeight?: number
}

interface TableChecker {
  rows: number
  columns: number
  [key: string]: unknown
}

interface TableEditData {
  action: string
  location?: string
  [key: string]: unknown
}

class Muya {
  static plugins: PluginEntry[] = []

  clickEvent: ClickEvent
  clipboard: Clipboard
  codePicker: unknown
  container: HTMLElement
  contentState: ContentState
  dragdrop: DragDrop
  emojiPicker: unknown
  eventCenter: EventCenter
  imagePathPicker: unknown
  keyboard: Keyboard
  markdown: string
  mouseEvent: MuyaMouseEvent
  options: MuyaOptions
  quickInsert: unknown
  resize: Resize
  tablePicker: unknown
  tooltip: ToolTip

  static use(plugin: PluginEntry['plugin'], options: Record<string, unknown> = {}) {
    Muya.plugins.push({
      plugin,
      options,
    })
  }

  constructor(container: HTMLElement | string, options: Partial<MuyaOptions> = {}) {
    this.options = Object.assign({}, MUYA_DEFAULT_OPTION, options)
    const { markdown } = this.options
    this.markdown = (markdown as string) ?? ''
    this.container = getContainer(container as HTMLElement, this.options)
    this.eventCenter = new EventCenter()
    this.tooltip = new ToolTip(this as unknown as IMuya)
    // UI plugins
    if (Muya.plugins.length) {
      for (const { plugin: Plugin, options: opts } of Muya.plugins) {
        ;(this as Record<string, unknown>)[Plugin.pluginName] = new Plugin(this, opts)
      }
    }

    this.contentState = new ContentState(this as unknown as IMuya, this.options)
    this.contentState.setStateRender(new StateRender(this as unknown as IMuya))
    this.clipboard = new Clipboard(this as unknown as IMuya)
    this.clickEvent = new ClickEvent(this as unknown as IMuya)
    this.keyboard = new Keyboard(this as unknown as IMuya)
    this.dragdrop = new DragDrop(this as unknown as IMuya)
    this.resize = new Resize(this as unknown as IMuya)
    this.mouseEvent = new MuyaMouseEvent(this as unknown as IMuya)
    this.init()
  }

  init() {
    const { container, contentState, eventCenter } = this
    contentState.stateRender.setContainer(container.children[0] as HTMLElement)
    eventCenter.subscribe('stateChange', this.dispatchChange)
    const { markdown } = this
    const { focusMode } = this.options
    this.setMarkdown(markdown as string)
    this.setFocusMode(focusMode as boolean)
    this.mutationObserver()
    eventCenter.attachDOMEvent(container, 'focus', () => {
      eventCenter.dispatch('focus')
    })
    eventCenter.attachDOMEvent(container, 'blur', () => {
      eventCenter.dispatch('blur')
    })
  }

  mutationObserver() {
    const { container, eventCenter } = this
    const config = { childList: true, subtree: true }

    const callback = (mutationsList: MutationRecord[], _observer: MutationObserver) => {
      for (const mutation of mutationsList) {
        if (mutation.type === 'childList') {
          const { removedNodes, target } = mutation
          if (removedNodes?.length) {
            const hasTable = Array.from(removedNodes).some(
              (node) => node.nodeType === 1 && (node as Element).closest('table.ag-paragraph'),
            )
            if (hasTable) {
              eventCenter.dispatch('crashed')
              console.warn('There was a problem with the table deletion.')
            }
          }

          if (
            (target as Element).getAttribute('id') === 'ag-editor-id' &&
            (target as Element).childElementCount === 0
          ) {
            eventCenter.dispatch('crashed')
            console.warn('editor crashed, and can not be input any more.')
          }
        }
      }
    }

    const observer = new MutationObserver(callback)
    observer.observe(container, config)
  }

  dispatchChange = () => {
    const { eventCenter } = this
    this.markdown = this.getMarkdown()
    const markdown = this.markdown
    const wc = this.getWordCount(markdown)
    const cursor = this.getCursor()
    const history = this.getHistory()
    const toc = this.getTOC()

    eventCenter.dispatch('change', { markdown, wordCount: wc, cursor, history, toc })
  }

  dispatchSelectionChange = () => {
    const selectionChanges = this.contentState.selectionChange()
    this.eventCenter.dispatch('selectionChange', selectionChanges)
  }

  dispatchSelectionFormats = () => {
    const { formats } = this.contentState.selectionFormats()
    this.eventCenter.dispatch('selectionFormats', formats)
  }

  getMarkdown() {
    const blocks = this.contentState.getBlocks()
    const isGitlabCompatibilityEnabled = this.contentState.isGitlabCompatibilityEnabled as boolean | undefined
    const listIndentation = this.contentState.listIndentation as string | number | undefined
    const trailingNewlines = (this.contentState as unknown as { _sourceTrailingNewlines?: number })
      ._sourceTrailingNewlines
    return new ExportMarkdown(blocks, listIndentation, isGitlabCompatibilityEnabled, trailingNewlines ?? 0).generate()
  }

  getHistory() {
    return this.contentState.getHistory()
  }

  getTOC() {
    return this.contentState.getTOC()
  }

  setHistory(history: unknown) {
    return this.contentState.setHistory(history as { stack: unknown[]; index: number })
  }

  clearHistory() {
    return this.contentState.history.clearHistory()
  }

  exportStyledHTML(options: Record<string, unknown>) {
    const { markdown } = this
    return new ExportHtml(markdown, this as unknown as IMuya).generate(options)
  }

  exportHtml() {
    const { markdown } = this
    return new ExportHtml(markdown, this as unknown as IMuya).renderHtml()
  }

  getWordCount(markdown: string) {
    return wordCount(markdown)
  }

  getCursor() {
    return this.contentState.getCodeMirrorCursor()
  }

  setMarkdown(markdown: string, cursor?: Cursor, isRenderCursor = true) {
    let newMarkdown = markdown
    let isValid = false
    if (cursor?.anchor && cursor.focus) {
      const cursorInfo = this.contentState.addCursorToMarkdown(markdown, cursor)
      newMarkdown = cursorInfo.markdown
      isValid = cursorInfo.isValid
    }
    this.contentState.importMarkdown(newMarkdown)
    this.contentState.importCursor(cursor && isValid)
    this.contentState.render(isRenderCursor)
    setTimeout(() => {
      this.dispatchChange()
    }, 0)
  }

  setCursor(cursor: Cursor) {
    const markdown = this.getMarkdown()
    return this.setMarkdown(markdown, cursor, true)
  }

  createTable(tableChecker: TableChecker) {
    return this.contentState.createTable(tableChecker)
  }

  getSelection() {
    return this.contentState.selectionChange()
  }

  setFocusMode(bool: boolean) {
    const { container } = this
    const { focusMode } = this.options
    if (bool && !focusMode) {
      container.classList.add(CLASS_OR_ID.AG_FOCUS_MODE)
    } else {
      container.classList.remove(CLASS_OR_ID.AG_FOCUS_MODE)
    }
    this.options.focusMode = bool
  }

  setFont({ fontSize, lineHeight }: FontOptions) {
    if (fontSize) {
      this.options.fontSize = parseInt(String(fontSize), 10)
    }
    if (lineHeight) {
      this.options.lineHeight = lineHeight
    }
    this.contentState.render(false)
  }

  setTabSize(tabSize: number) {
    if (!tabSize || typeof tabSize !== 'number') {
      tabSize = 4
    } else if (tabSize < 1) {
      tabSize = 1
    } else if (tabSize > 4) {
      tabSize = 4
    }
    this.contentState.tabSize = tabSize
  }

  setListIndentation(listIndentation: number | 'dfm') {
    if (typeof listIndentation === 'number') {
      if (listIndentation < 1 || listIndentation > 4) {
        listIndentation = 1
      }
    } else if (listIndentation !== 'dfm') {
      listIndentation = 1
    }
    this.contentState.listIndentation = listIndentation
  }

  updateParagraph(type: string) {
    this.contentState.updateParagraph(type)
  }

  duplicate() {
    this.contentState.duplicate()
  }

  deleteParagraph() {
    this.contentState.deleteParagraph()
  }

  insertParagraph(location: 'before' | 'after', text = '', outMost = false) {
    this.contentState.insertParagraph(location, text, outMost)
  }

  editTable(data: TableEditData) {
    this.contentState.editTable(data)
  }

  hasFocus() {
    return document.activeElement === this.container
  }

  focus() {
    this.contentState.setCursor()
    this.container.focus()
  }

  blur(isRemoveAllRange = false, unSelect = false) {
    if (isRemoveAllRange) {
      document.getSelection()?.removeAllRanges()
    }

    if (unSelect) {
      this.contentState.selectedImage = null
      this.contentState.selectedTableCells = null
    }

    this.hideAllFloatTools()
    this.container.blur()
  }

  format(type: string) {
    this.contentState.format(type)
  }

  insertImage(imageInfo: Record<string, unknown>) {
    this.contentState.insertImage(imageInfo)
  }

  search(value: string, opt: SearchOptions = {}): SearchMatches {
    const { selectHighlight } = opt
    this.contentState.search(value, opt)
    this.contentState.render(!!selectHighlight)
    return this.contentState.searchMatches
  }

  replace(value: string, opt: SearchOptions): SearchMatches {
    this.contentState.replace(value, opt)
    this.contentState.render(false)
    return this.contentState.searchMatches
  }

  find(action: 'pre' | 'next'): SearchMatches {
    this.contentState.find(action)
    this.contentState.render(false)
    return this.contentState.searchMatches
  }

  on(event: string, listener: (...args: unknown[]) => void) {
    this.eventCenter.subscribe(event, listener)
  }

  off(event: string, listener: (...args: unknown[]) => void) {
    this.eventCenter.unsubscribe(event, listener)
  }

  once(event: string, listener: (...args: unknown[]) => void) {
    this.eventCenter.subscribeOnce(event, listener)
  }

  invalidateImageCache() {
    this.contentState.stateRender.invalidateImageCache()
    this.contentState.render(true)
  }

  undo() {
    this.contentState.history.undo()
    this.dispatchSelectionChange()
    this.dispatchSelectionFormats()
    this.dispatchChange()
  }

  redo() {
    this.contentState.history.redo()
    this.dispatchSelectionChange()
    this.dispatchSelectionFormats()
    this.dispatchChange()
  }

  selectAll() {
    if (!this.hasFocus() && !this.contentState.selectedTableCells) {
      return
    }
    this.contentState.selectAll()
  }

  /**
   * Get all images' src from the given markdown.
   * @param {string} markdown you want to extract images from this markdown.
   */
  extractImages(markdown = this.markdown) {
    return this.contentState.extractImages(markdown)
  }

  copyAsMarkdown() {
    this.clipboard.copyAsMarkdown()
  }

  copyAsHtml() {
    this.clipboard.copyAsHtml()
  }

  pasteAsPlainText() {
    this.clipboard.pasteAsPlainText()
  }

  /**
   * Copy the anchor block contains the block with `info`. like copy as markdown.
   * @param {string|object} key the block key or block
   */
  copy(info: string | Block) {
    return this.clipboard.copy('copyBlock', info)
  }

  setOptions(options: Partial<MuyaOptions>, needRender = false) {
    // FIXME: Just to be sure, disabled due to #1648.
    if ((options as Record<string, unknown>).codeBlockLineNumbers) {
      ;(options as Record<string, unknown>).codeBlockLineNumbers = false
    }

    Object.assign(this.options, options)
    if (needRender) {
      this.contentState.render(false, true)
    }

    const hideQuickInsertHint = options.hideQuickInsertHint
    if (typeof hideQuickInsertHint !== 'undefined') {
      const hasClass = this.container.classList.contains('ag-show-quick-insert-hint')
      if (hideQuickInsertHint && hasClass) {
        this.container.classList.remove('ag-show-quick-insert-hint')
      } else if (!hideQuickInsertHint && !hasClass) {
        this.container.classList.add('ag-show-quick-insert-hint')
      }
    }

    const spellcheckEnabled = (options as Record<string, unknown>).spellcheckEnabled
    if (typeof spellcheckEnabled !== 'undefined') {
      this.container.setAttribute('spellcheck', String(!!spellcheckEnabled))
    }

    if ((options as Record<string, unknown>).bulletListMarker) {
      this.contentState.turndownConfig.bulletListMarker = (options as Record<string, unknown>).bulletListMarker
    }
  }

  hideAllFloatTools() {
    return this.keyboard.hideAllFloatTools()
  }

  /**
   * Replace the word range with the given replacement.
   */
  replaceWordInline(
    line: LineCursor,
    wordCursor: { start: CursorPosition; end: CursorPosition },
    replacement: string,
    setCursor = false,
  ) {
    this.contentState.replaceWordInline(line, wordCursor, replacement, setCursor)
  }

  /**
   * Replace the current selected word with the given replacement.
   */
  _replaceCurrentWordInlineUnsafe(word: string, replacement: string) {
    return this.contentState._replaceCurrentWordInlineUnsafe(word, replacement)
  }

  destroy() {
    this.contentState.clear()
    ;(this.quickInsert as { destroy(): void })?.destroy()
    ;(this.codePicker as { destroy(): void })?.destroy()
    ;(this.tablePicker as { destroy(): void })?.destroy()
    ;(this.emojiPicker as { destroy(): void })?.destroy()
    ;(this.imagePathPicker as { destroy(): void })?.destroy()
    this.eventCenter.detachAllDomEvents()
  }
}

/**
 * Ensure container element is div
 */
function getContainer(originContainer: HTMLElement, options: MuyaOptions) {
  const { hideQuickInsertHint, spellcheckEnabled } = options
  const container = document.createElement('div')
  const rootDom = document.createElement('div')
  const attrs = originContainer.attributes
  // copy attrs from origin container to new div element
  Array.from(attrs).forEach((attr) => {
    container.setAttribute(attr.name, attr.value)
  })

  if (!hideQuickInsertHint) {
    container.classList.add('ag-show-quick-insert-hint')
  }

  container.setAttribute('contenteditable', 'true')
  container.setAttribute('autocorrect', 'false')
  container.setAttribute('autocomplete', 'off')
  container.setAttribute('spellcheck', String(!!spellcheckEnabled))
  container.appendChild(rootDom)
  originContainer.replaceWith(container)
  return container
}

export default Muya
