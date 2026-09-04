import { HAS_TEXT_BLOCK_REG, DEFAULT_TURNDOWN_CONFIG } from '../config'
import type {
  Block,
  IContentState,
  IStateRender,
  IMuya,
  SearchMatches,
  MuyaOptions,
  Cursor as CursorInterface,
  IDragInfo,
  ICellSelectInfo,
  SelectedImage,
} from '../types'
import { getUniqueId, deepCopy } from '../utils'
import selection from '../selection'
import type { CursorConstructorArgs } from '../selection/cursor'
import enterCtrl from './enterCtrl'
import updateCtrl from './updateCtrl'
import backspaceCtrl from './backspaceCtrl'
import deleteCtrl from './deleteCtrl'
import codeBlockCtrl from './codeBlockCtrl'
import tableBlockCtrl from './tableBlockCtrl'
import tableDragBarCtrl from './tableDragBarCtrl'
import tableSelectCellsCtrl from './tableSelectCellsCtrl'
import coreApi from './core'
import marktextApi from './marktext'
import History from './history'
import arrowCtrl from './arrowCtrl'
import pasteCtrl from './pasteCtrl'
import copyCutCtrl from './copyCutCtrl'
import paragraphCtrl from './paragraphCtrl'
import tabCtrl from './tabCtrl'
import formatCtrl from './formatCtrl'
import searchCtrl from './searchCtrl'
import containerCtrl from './containerCtrl'
import htmlBlockCtrl from './htmlBlock'
import clickCtrl from './clickCtrl'
import inputCtrl from './inputCtrl'
import tocCtrl from './tocCtrl'
import emojiCtrl from './emojiCtrl'
import imageCtrl from './imageCtrl'
import linkCtrl from './linkCtrl'
import dragDropCtrl from './dragDropCtrl'
import footnoteCtrl from './footnoteCtrl'
import importMarkdown from '../utils/importMarkdown'
import Cursor from '../selection/cursor'
import escapeCharactersMap, { escapeCharacters } from '../parser/escapeCharacter'

const syncEditingContainerKey = (contentState: ContentState) => {
  if (!contentState.editingContainerKey) {
    return
  }

  const editingFigure = contentState.getBlock(contentState.editingContainerKey)
  const startBlock = contentState.getBlock(contentState.cursor.start.key)
  const outMostBlock = startBlock ? contentState.findOutMostBlock(startBlock) : null

  if (!editingFigure || editingFigure.functionType !== 'mermaid' || outMostBlock?.key !== editingFigure.key) {
    contentState.editingContainerKey = null
  }
}

class StateRenderStub implements IStateRender {
  tokenCache = new Map<string, unknown>()
  urlMap = new Map<string, unknown>()
  labels = new Map<string, { href: string; title: string }>()

  setContainer(_container: HTMLElement) {}

  collectLabels(_blocks: Block[]) {}

  render(_blocks: Block[], _activeBlocks: Block[], _matches: SearchMatches['matches']) {}

  partialRender(
    _blocks: Block[],
    _activeBlocks: Block[],
    _matches: SearchMatches['matches'],
    _startKey: string | null,
    _endKey: string | null,
  ) {}

  singleRender(_block: Block, _activeBlocks: Block[], _matches: SearchMatches['matches']) {}

  invalidateImageCache() {}
}

const prototypes = [
  coreApi,
  marktextApi,
  tabCtrl,
  enterCtrl,
  updateCtrl,
  backspaceCtrl,
  deleteCtrl,
  codeBlockCtrl,
  arrowCtrl,
  pasteCtrl,
  copyCutCtrl,
  tableBlockCtrl,
  tableDragBarCtrl,
  tableSelectCellsCtrl,
  paragraphCtrl,
  formatCtrl,
  searchCtrl,
  containerCtrl,
  htmlBlockCtrl,
  clickCtrl,
  inputCtrl,
  tocCtrl,
  emojiCtrl,
  imageCtrl,
  linkCtrl,
  dragDropCtrl,
  footnoteCtrl,
  importMarkdown,
]

// biome-ignore lint/suspicious/noUnsafeDeclarationMerging: ContentState methods are composed via runtime mixins below.
class ContentState {
  _selectedImage: SelectedImage | null
  _selectedTableCells: {
    tableId: string
    row: number
    column: number
    cells: Array<{ key: string; [key: string]: unknown }>
    [key: string]: unknown
  } | null
  private _blocks: Block[] = []
  /** Lazy key -> block index (CORE-003); null means "rebuild on next use". */
  private _blockIndex: Map<string, Block> | null = null
  /** O(1) root membership for attachment verification (flat docs are huge). */
  private _rootSet: Set<Block> | null = null
  /** Per-instance code block render throttle (was module-level, leaked across editors). */
  _renderCodeBlockTimer: ReturnType<typeof setTimeout> | null = null
  cellSelectEventIds: string[]
  cellSelectInfo: ICellSelectInfo | null
  currentCursor: Cursor | null
  dragEventIds: string[]
  dragInfo: IDragInfo | null
  dropAnchor: { position: string; anchor: Block } | null
  editingContainerKey: string | null
  exemption: Set<string>
  history: History
  historyTimer: ReturnType<typeof setTimeout> | null
  isDragTableBar: boolean
  muya: IMuya
  prevCursor: Cursor | null
  renderRange: [string | null, string | null]
  resizeLineNumber!: () => void
  searchMatches!: SearchMatches
  selectedBlock: Block | null
  stateRender: IStateRender
  turndownConfig: Record<string, unknown>
  constructor(muya: IMuya, options: MuyaOptions) {
    const { bulletListMarker } = options

    this.muya = muya
    Object.assign(this, options)

    // Use to cache the keys which you don't want to remove.
    this.exemption = new Set()
    this._blocks = [this.createBlockP()]
    this.stateRender = new StateRenderStub()
    this.renderRange = [null, null]
    this.currentCursor = null
    this.editingContainerKey = null
    this.selectedBlock = null
    this._selectedImage = null
    this.dropAnchor = null
    this.prevCursor = null
    this.historyTimer = null
    this.history = new History(this as unknown as IContentState)
    this.turndownConfig = Object.assign({}, DEFAULT_TURNDOWN_CONFIG, { bulletListMarker })
    // table drag bar
    this.dragInfo = null
    this.isDragTableBar = false
    this.dragEventIds = []
    // table cell select
    this.cellSelectInfo = null
    this._selectedTableCells = null
    this.cellSelectEventIds = []
    this.init()
  }

  // Wholesale replacement (history undo/redo, import) invalidates the index.
  get blocks(): Block[] {
    return this._blocks
  }

  set blocks(value: Block[]) {
    this._blocks = value
    this._blockIndex = null
    this._rootSet = null
  }

  private _indexBlockTree(block: Block): void {
    this._blockIndex!.set(block.key, block)
    for (const child of block.children) {
      this._indexBlockTree(child)
    }
  }

  private _unindexBlockTree(block: Block): void {
    if (!this._blockIndex) return
    this._blockIndex.delete(block.key)
    for (const child of block.children) {
      this._unindexBlockTree(child)
    }
  }

  private _rebuildBlockIndex(): void {
    this._blockIndex = new Map()
    this._rootSet = new Set(this._blocks)
    for (const block of this._blocks) {
      this._indexBlockTree(block)
    }
  }

  /**
   * Verify an indexed block is still attached to the live tree by walking
   * its parent chain with identity membership checks. Guards against the
   * places that splice children arrays directly (enterCtrl/updateCtrl) and
   * against stale objects after history replaced the whole tree.
   */
  private _isAttachedToTree(block: Block): boolean {
    let current = block
    for (let depth = 0; depth < 1000; depth++) {
      // Root blocks carry parent '' (empty string), not null.
      if (!current.parent) {
        return this._rootSet!.has(current)
      }
      const parent = this._blockIndex!.get(current.parent)
      if (!parent || !parent.children.includes(current)) {
        return false
      }
      current = parent
    }
    return false
  }

  setStateRender(stateRender: IStateRender) {
    this.stateRender = stateRender
  }

  set selectedTableCells(info) {
    const oldSelectedTableCells = this._selectedTableCells
    if (!info && !!oldSelectedTableCells) {
      const selectedCells = this.muya.container.querySelectorAll('.ag-cell-selected')

      for (const cell of Array.from(selectedCells)) {
        cell.classList.remove('ag-cell-selected')
        cell.classList.remove('ag-cell-border-top')
        cell.classList.remove('ag-cell-border-right')
        cell.classList.remove('ag-cell-border-bottom')
        cell.classList.remove('ag-cell-border-left')
      }
    }
    this._selectedTableCells = info
  }

  get selectedTableCells() {
    return this._selectedTableCells
  }

  set selectedImage(image: SelectedImage | null) {
    const oldSelectedImage = this._selectedImage
    // if there is no selected image, remove selected status of current selected image.
    if (!image && oldSelectedImage) {
      const selectedImages = this.muya.container.querySelectorAll('.ag-inline-image-selected')
      for (const img of selectedImages) {
        img.classList.remove('ag-inline-image-selected')
      }
    }
    this._selectedImage = image
  }

  get selectedImage(): SelectedImage | null {
    return this._selectedImage
  }

  set cursor(cursor: CursorInterface | CursorConstructorArgs) {
    const normalizedCursor = cursor instanceof Cursor ? cursor : new Cursor(cursor)

    this.prevCursor = this.currentCursor
    this.currentCursor = normalizedCursor

    const getHistoryState = () => {
      const { blocks, renderRange } = this
      return {
        blocks,
        renderRange,
        cursor: normalizedCursor,
      }
    }

    if (!normalizedCursor.noHistory) {
      if (
        this.prevCursor &&
        (this.prevCursor.start.key !== normalizedCursor.start.key ||
          this.prevCursor.end.key !== normalizedCursor.end.key)
      ) {
        // Push history immediately
        this.history.push(getHistoryState())
      } else {
        // Commit pending state at shorter intervals so that undo steps are
        // more granular (fixes #1321 — undo removing entire paragraphs).
        if (this.historyTimer) clearTimeout(this.historyTimer)
        this.history.pushPending(getHistoryState())

        this.historyTimer = setTimeout(() => {
          this.history.commitPending()
        }, 500)
      }
    }
  }

  get cursor(): Cursor {
    return this.currentCursor!
  }

  init() {
    const lastBlock = this.getLastBlock()!
    const { key, text } = lastBlock
    const offset = text.length
    this.searchMatches = {
      value: '', // the search value
      matches: [], // matches
      index: -1, // active match
    }
    this.cursor = {
      start: { key, offset },
      end: { key, offset },
      anchor: { key, offset },
      focus: { key, offset },
    }
  }

  getHistory() {
    const { stack, index } = this.history
    return { stack, index }
  }

  setHistory({ stack, index }: { stack: unknown[]; index: number }) {
    Object.assign(this.history, { stack, index })
  }

  setCursor() {
    const { anchor, focus } = this.cursor
    if (anchor && focus) {
      selection.setCursorRange({ anchor, focus })
    }
  }

  setNextRenderRange() {
    const { start, end } = this.cursor
    const startBlock = this.getBlock(start.key)
    const endBlock = this.getBlock(end.key)
    if (!startBlock || !endBlock) return

    const startOutMostBlock = this.findOutMostBlock(startBlock)
    const endOutMostBlock = this.findOutMostBlock(endBlock)

    this.renderRange = [startOutMostBlock.preSibling, endOutMostBlock.nextSibling]
  }

  postRender() {
    this.resizeLineNumber()
  }

  render(isRenderCursor = true, clearCache = false) {
    const {
      blocks,
      searchMatches: { matches, index },
    } = this
    syncEditingContainerKey(this)
    const activeBlocks = this.getActiveBlocks()
    if (clearCache) {
      this.stateRender.tokenCache.clear()
    }
    matches.forEach((m: { active: boolean }, i: number) => {
      m.active = i === index
    })
    this.setNextRenderRange()
    this.stateRender.collectLabels(blocks)
    this.stateRender.render(blocks, activeBlocks, matches)
    if (isRenderCursor) {
      this.setCursor()
    } else {
      this.muya.blur()
    }
    this.postRender()
  }

  partialRender(isRenderCursor = true) {
    const {
      blocks,
      searchMatches: { matches, index },
    } = this
    syncEditingContainerKey(this)
    const activeBlocks = this.getActiveBlocks()
    const [startKey, endKey] = this.renderRange
    matches.forEach((m: { active: boolean }, i: number) => {
      m.active = i === index
    })

    // The `endKey` may already be removed from blocks if range was selected via keyboard (GH#1854).
    let startIndex = startKey ? blocks.findIndex((block: Block) => block.key === startKey) : 0
    if (startIndex === -1) {
      startIndex = 0
    }

    let endIndex = blocks.length
    if (endKey) {
      const tmpEndIndex = blocks.findIndex((block: Block) => block.key === endKey)
      if (tmpEndIndex >= 0) {
        endIndex = tmpEndIndex + 1
      }
    }

    const blocksToRender = blocks.slice(startIndex, endIndex)

    this.setNextRenderRange()
    this.stateRender.collectLabels(blocks)
    this.stateRender.partialRender(blocksToRender, activeBlocks, matches, startKey, endKey)
    if (isRenderCursor) {
      this.setCursor()
    } else {
      this.muya.blur()
    }
    this.postRender()
  }

  singleRender(block: Block, isRenderCursor = true) {
    const {
      blocks,
      searchMatches: { matches, index },
    } = this
    syncEditingContainerKey(this)
    const activeBlocks = this.getActiveBlocks()
    matches.forEach((m: { active: boolean }, i: number) => {
      m.active = i === index
    })
    this.setNextRenderRange()
    this.stateRender.collectLabels(blocks)
    this.stateRender.singleRender(block, activeBlocks, matches)
    if (isRenderCursor) {
      this.setCursor()
    } else {
      this.muya.blur()
    }
    this.postRender()
  }

  /**
   * A block in MarkText present a paragraph(block syntax in GFM) or a line in paragraph.
   * a `span` block must in a `p block` or `pre block` and `p block`'s children must be `span` blocks.
   */
  createBlock(type = 'span', extras: Record<string, unknown> = {}): Block {
    const key = getUniqueId()
    const blockData: Block = {
      key,
      text: '',
      type,
      editable: true,
      parent: null,
      preSibling: null,
      nextSibling: null,
      children: [],
    }

    // give span block a default functionType `paragraphContent`
    if (type === 'span' && !extras.functionType) {
      blockData.functionType = 'paragraphContent'
    }

    if (extras.functionType === 'codeContent' && extras.text) {
      const CHAR_REG = new RegExp(`(${escapeCharacters.join('|')})`, 'gi')
      extras.text = (extras.text as string).replace(CHAR_REG, (_: string, p: string) => {
        return escapeCharactersMap[p]
      })
    }

    Object.assign(blockData, extras)
    return blockData
  }

  createBlockP(text = '') {
    const pBlock = this.createBlock('p')
    const contentBlock = this.createBlock('span', { text })
    this.appendChild(pBlock, contentBlock)
    return pBlock
  }

  isCollapse(cursor = this.cursor) {
    const { start, end } = cursor
    return start.key === end.key && start.offset === end.offset
  }

  // getBlocks
  getBlocks() {
    return this.blocks
  }

  getCursor() {
    return this.cursor
  }

  getBlock(key: string | null | undefined): Block | null {
    if (!key) return null
    if (!this._blockIndex) {
      this._rebuildBlockIndex()
    }
    const hit = this._blockIndex!.get(key)
    if (hit && this._isAttachedToTree(hit)) {
      return hit
    }
    // Miss or detached entry: rebuild once and take the authoritative answer.
    this._rebuildBlockIndex()
    return this._blockIndex!.get(key) ?? null
  }

  copyBlock(origin: Block) {
    const copiedBlock = deepCopy(origin)
    const travel = (block: Block, parent: Block | null, preBlock: Block | null, nextBlock: Block | null) => {
      const key = getUniqueId()
      block.key = key
      block.parent = parent ? parent.key : null
      block.preSibling = preBlock ? preBlock.key : null
      block.nextSibling = nextBlock ? nextBlock.key : null
      const { children } = block
      const len = children.length
      if (children && len) {
        let i: number
        for (i = 0; i < len; i++) {
          const b = children[i]
          const preB = i >= 1 ? children[i - 1] : null
          const nextB = i < len - 1 ? children[i + 1] : null
          travel(b, block, preB, nextB)
        }
      }
    }

    travel(copiedBlock, null, null, null)
    return copiedBlock
  }

  getParent(block: Block) {
    if (block?.parent) {
      return this.getBlock(block.parent)
    }
    return null
  }

  // return block and its parents
  getParents(block: Block) {
    const result = []
    result.push(block)
    let parent = this.getParent(block)
    while (parent) {
      result.push(parent)
      parent = this.getParent(parent)
    }
    return result
  }

  getPreSibling(block: Block) {
    return block.preSibling ? this.getBlock(block.preSibling) : null
  }

  getNextSibling(block: Block) {
    return block.nextSibling ? this.getBlock(block.nextSibling) : null
  }

  /**
   * if target is descendant of parent return true, else return false
   * @param  {[type]}  parent [description]
   * @param  {[type]}  target [description]
   * @return {Boolean}        [description]
   */
  isInclude(parent: Block, target: Block): boolean {
    const children = parent.children
    if (children.length === 0) {
      return false
    } else {
      if (children.some((child: Block) => child.key === target.key)) {
        return true
      } else {
        return children.some((child: Block) => this.isInclude(child, target))
      }
    }
  }

  removeTextOrBlock(block: Block) {
    if (block.functionType === 'languageInput') return
    const checkerIn = (block: Block): boolean => {
      if (this.exemption.has(block.key)) {
        return true
      } else {
        const parent = this.getBlock(block.parent)
        return parent ? checkerIn(parent) : false
      }
    }

    const checkerOut = (block: Block): boolean => {
      const children = block.children
      if (children.length) {
        if (children.some((child: Block) => this.exemption.has(child.key))) {
          return true
        } else {
          return children.some((child: Block) => checkerOut(child))
        }
      } else {
        return false
      }
    }

    if (checkerIn(block) || checkerOut(block)) {
      block.text = ''
      const { children } = block
      if (children.length) {
        children.forEach((child: Block) => {
          this.removeTextOrBlock(child)
        })
      }
    } else if (block.editable) {
      this.removeBlock(block)
    }
  }

  /**
   * remove blocks between before and after, and includes after block.
   */
  removeBlocks(before: Block, after: Block, isRemoveAfter = true, isRecursion = false) {
    if (!isRecursion) {
      if (/td|th/.test(before.type)) {
        const fig = this.closest(before, 'figure')
        if (fig) this.exemption.add(fig.key)
      }
      if (/td|th/.test(after.type)) {
        const fig = this.closest(after, 'figure')
        if (fig) this.exemption.add(fig.key)
      }
    }
    let nextSibling: Block | null = this.getBlock(before.nextSibling)
    let beforeEnd = false
    while (nextSibling) {
      if (nextSibling.key === after.key || this.isInclude(nextSibling, after)) {
        beforeEnd = true
        break
      }
      this.removeTextOrBlock(nextSibling)
      nextSibling = this.getBlock(nextSibling.nextSibling)
    }
    if (!beforeEnd) {
      const parent = this.getParent(before)
      if (parent) {
        this.removeBlocks(parent, after, false, true)
      }
    }
    let preSibling: Block | null = this.getBlock(after.preSibling)
    let afterEnd = false
    while (preSibling) {
      if (preSibling.key === before.key || this.isInclude(preSibling, before)) {
        afterEnd = true
        break
      }
      this.removeTextOrBlock(preSibling)
      preSibling = this.getBlock(preSibling.preSibling)
    }
    if (!afterEnd) {
      const parent = this.getParent(after)
      if (parent) {
        const removeAfter = isRemoveAfter && this.isOnlyRemoveableChild(after)
        this.removeBlocks(before, parent, removeAfter, true)
      }
    }
    if (isRemoveAfter) {
      this.removeTextOrBlock(after)
    }
    if (!isRecursion) {
      this.exemption.clear()
    }
  }

  removeBlock(block: Block, fromBlocks: Block[] | { children: Block[] } = this.blocks) {
    const remove = (blocks: Block[], b: Block) => {
      const len = blocks.length
      let i: number
      for (i = 0; i < len; i++) {
        if (blocks[i].key === b.key) {
          const preSibling: Block | null = this.getBlock(b.preSibling)
          const nextSibling: Block | null = this.getBlock(b.nextSibling)

          if (preSibling) {
            preSibling.nextSibling = nextSibling ? nextSibling.key : null
          }
          if (nextSibling) {
            nextSibling.preSibling = preSibling ? preSibling.key : null
          }

          return blocks.splice(i, 1)
        } else {
          if (blocks[i].children.length) {
            remove(blocks[i].children, b)
            remove(blocks[i].children, b)
          }
        }
      }
    }
    remove(Array.isArray(fromBlocks) ? fromBlocks : fromBlocks.children, block)
    if (this._blockIndex) {
      this._unindexBlockTree(block)
      this._rootSet?.delete(block)
    }
  }

  getActiveBlocks(): Block[] {
    const result: Block[] = []
    let block: Block | null = this.getBlock(this.cursor.start.key)
    if (block) {
      result.push(block)
    }
    while (block?.parent) {
      block = this.getBlock(block.parent)
      if (block) result.push(block)
    }
    return result
  }

  insertAfter(newBlock: Block, oldBlock: Block) {
    const siblings = oldBlock.parent ? this.getBlock(oldBlock.parent)!.children : this.blocks
    const oldNextSibling: Block | null = this.getBlock(oldBlock.nextSibling)
    const index = this.findIndex(siblings, oldBlock)
    siblings.splice(index + 1, 0, newBlock)
    oldBlock.nextSibling = newBlock.key
    newBlock.parent = oldBlock.parent
    newBlock.preSibling = oldBlock.key
    if (oldNextSibling) {
      newBlock.nextSibling = oldNextSibling.key
      oldNextSibling.preSibling = newBlock.key
    }
    if (this._blockIndex) {
      this._indexBlockTree(newBlock)
      if (!newBlock.parent) {
        this._rootSet?.add(newBlock)
      }
    }
  }

  insertBefore(newBlock: Block, oldBlock: Block) {
    const siblings = oldBlock.parent ? this.getBlock(oldBlock.parent)!.children : this.blocks
    const oldPreSibling: Block | null = this.getBlock(oldBlock.preSibling)
    const index = this.findIndex(siblings, oldBlock)
    siblings.splice(index, 0, newBlock)
    oldBlock.preSibling = newBlock.key
    newBlock.parent = oldBlock.parent
    newBlock.nextSibling = oldBlock.key
    newBlock.preSibling = null

    if (oldPreSibling) {
      oldPreSibling.nextSibling = newBlock.key
      newBlock.preSibling = oldPreSibling.key
    }
    if (this._blockIndex) {
      this._indexBlockTree(newBlock)
      if (!newBlock.parent) {
        this._rootSet?.add(newBlock)
      }
    }
  }

  findOutMostBlock(block: Block): Block {
    const parent = this.getBlock(block.parent)
    return parent ? this.findOutMostBlock(parent) : block
  }

  findIndex(children: Block[], block: Block) {
    return children.indexOf(block)
  }

  prependChild(parent: Block, block: Block) {
    block.parent = parent.key
    block.preSibling = null
    if (parent.children.length) {
      block.nextSibling = parent.children[0].key
    }
    parent.children.unshift(block)
    if (this._blockIndex) {
      this._indexBlockTree(block)
    }
  }

  appendChild(parent: Block, block: Block) {
    const len = parent.children.length
    const lastChild = parent.children[len - 1]
    parent.children.push(block)
    block.parent = parent.key
    if (lastChild) {
      lastChild.nextSibling = block.key
      block.preSibling = lastChild.key
    } else {
      block.preSibling = null
    }
    block.nextSibling = null
    if (this._blockIndex) {
      this._indexBlockTree(block)
    }
  }

  replaceBlock(newBlock: Block, oldBlock: Block) {
    const blockList = oldBlock.parent ? this.getParent(oldBlock)!.children : this.blocks
    const index = this.findIndex(blockList, oldBlock)

    blockList.splice(index, 1, newBlock)
    newBlock.parent = oldBlock.parent
    newBlock.preSibling = oldBlock.preSibling
    newBlock.nextSibling = oldBlock.nextSibling
  }

  canInserFrontMatter(block: Block) {
    if (!block) return true
    const parent = this.getParent(block)
    return block.type === 'span' && !block.preSibling && parent ? !parent.preSibling && !parent.parent : false
  }

  isFirstChild(block: Block) {
    return !block.preSibling
  }

  isLastChild(block: Block) {
    return !block.nextSibling
  }

  isOnlyChild(block: Block) {
    return !block.nextSibling && !block.preSibling
  }

  isOnlyRemoveableChild(block: Block) {
    if (block.editable === false) return false
    const parent = this.getParent(block)
    return (
      (parent ? parent.children : this.blocks).filter(
        (child: Block) => child.editable && child.functionType !== 'languageInput',
      ).length === 1
    )
  }

  getLastChild(block: Block) {
    if (block) {
      const len = block.children.length
      if (len) {
        return block.children[len - 1]
      }
    }
    return null
  }

  firstInDescendant(block: Block): Block | null {
    const children = block.children
    if (block.children.length === 0 && HAS_TEXT_BLOCK_REG.test(block.type)) {
      return block
    } else if (children.length) {
      if (children[0].type === 'input' || (children[0].type === 'div' && children[0].editable === false)) {
        // handle task item
        return children[1] ? this.firstInDescendant(children[1]) : null
      } else {
        return this.firstInDescendant(children[0])
      }
    }
    return null
  }

  lastInDescendant(block: Block): Block | null {
    if (block.children.length === 0 && HAS_TEXT_BLOCK_REG.test(block.type)) {
      return block
    } else if (block.children.length) {
      const children = block.children
      let lastChild: Block | null = children[children.length - 1]
      while (lastChild && lastChild.editable === false) {
        lastChild = this.getPreSibling(lastChild)
      }
      return lastChild ? this.lastInDescendant(lastChild) : null
    }
    return null
  }

  findPreBlockInLocation(block: Block): Block | null {
    const parent = this.getParent(block)
    const preBlock = this.getPreSibling(block)
    if (
      block.preSibling &&
      preBlock &&
      preBlock.type !== 'input' &&
      preBlock.type !== 'div' &&
      preBlock.editable !== false
    ) {
      // handle task item and table
      return this.lastInDescendant(preBlock)
    } else if (parent) {
      return this.findPreBlockInLocation(parent)
    } else {
      return null
    }
  }

  findNextBlockInLocation(block: Block): Block | null {
    const parent = this.getParent(block)
    const nextBlock = this.getNextSibling(block)

    if (nextBlock && nextBlock.editable !== false) {
      return this.firstInDescendant(nextBlock) ?? null
    } else if (parent) {
      return this.findNextBlockInLocation(parent)
    } else {
      return null
    }
  }

  getPositionReference() {
    const fontSize = this.muya.options.fontSize as number
    const lineHeight = this.muya.options.lineHeight as number
    const { start } = this.cursor
    const block = this.getBlock(start.key)
    const { x, y, width } = selection.getCursorCoords()
    const height = fontSize * lineHeight
    const bottom = y + height
    const right = x + width
    const left = x
    const top = y
    return {
      getBoundingClientRect() {
        return { x, y, top, left, right, bottom, height, width }
      },
      clientWidth: width,
      clientHeight: height,
      id: block ? block.key : null,
    }
  }

  getFirstBlock() {
    return this.firstInDescendant(this.blocks[0])
  }

  getLastBlock() {
    const { blocks } = this
    const len = blocks.length
    return this.lastInDescendant(blocks[len - 1])
  }

  closest(block: Block | null, type: string | RegExp): Block | null {
    if (!block) {
      return null
    }
    if (type instanceof RegExp ? type.test(block.type) : block.type === type) {
      return block
    } else {
      const parent = this.getParent(block)
      return this.closest(parent, type)
    }
  }

  getAnchor(block: Block) {
    const { type, functionType } = block
    if (type !== 'span') {
      return null
    }

    if (functionType === 'codeContent' || functionType === 'cellContent') {
      return this.closest(block, 'figure') || this.closest(block, 'pre')
    } else {
      return this.getParent(block)
    }
  }

  clear() {
    this.history.clearHistory()
  }
}

// Tell TypeScript that ContentState has all IContentState prototype methods (added via mixins above).
interface ContentState extends IContentState {}

prototypes.forEach((ctrl) => {
  ctrl(ContentState as unknown as { prototype: IContentState })
})

export default ContentState
