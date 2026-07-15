/**
 * MuyaAdapter (PLAN.md CORE-001): the ONLY module in the shell that may
 * import Muya. It owns plugin registration, construction and the full
 * method delegation behind the EditorEngine contract. When ADR-002 decides
 * the engine's future, this file is the swap point — the shell keeps
 * compiling against EditorEngine.
 */
import Muya from 'muya/lib'
import TablePicker from 'muya/lib/ui/tablePicker'
import QuickInsert from 'muya/lib/ui/quickInsert'
import CodePicker from 'muya/lib/ui/codePicker'
import EmojiPicker from 'muya/lib/ui/emojiPicker'
import ImagePathPicker from 'muya/lib/ui/imagePicker'
import ImageSelector from 'muya/lib/ui/imageSelector'
import ImageToolbar from 'muya/lib/ui/imageToolbar'
import Transformer from 'muya/lib/ui/transformer'
import FormatPicker from 'muya/lib/ui/formatPicker'
import LinkTools from 'muya/lib/ui/linkTools'
import FootnoteTool from 'muya/lib/ui/footnoteTool'
import TableBarTools from 'muya/lib/ui/tableTools'
import FrontMenu from 'muya/lib/ui/frontMenu'
import type { EditorEngine, EditorEngineOptions, EngineEventListener, EngineSelection, TocEntry } from './engine'

export interface MuyaEngineHooks {
  /** Unsplash attribution click in the image selector. */
  photoCreatorClick?: (url: string) => void
  /** Link jump handling for the link tools popup. */
  jumpClick?: (linkInfo: unknown) => void
}

type MuyaPluginLike = { new (...args: unknown[]): unknown; pluginName: string }

const usePlugin = (plugin: unknown, options?: Record<string, unknown>): void => {
  Muya.use(plugin as MuyaPluginLike, options)
}

/**
 * Muya UI plugins register on the constructor with per-mount hook options.
 * Re-registration on every mount mirrors the legacy behavior (the latest
 * editor's hooks win — a single visible editor exists per window).
 */
const registerMuyaPlugins = (hooks: MuyaEngineHooks): void => {
  usePlugin(TablePicker)
  usePlugin(QuickInsert)
  usePlugin(CodePicker)
  usePlugin(EmojiPicker)
  usePlugin(ImagePathPicker)
  usePlugin(ImageSelector, {
    unsplashAccessKey: process.env.UNSPLASH_ACCESS_KEY,
    photoCreatorClick: hooks.photoCreatorClick,
  })
  usePlugin(Transformer)
  usePlugin(ImageToolbar)
  usePlugin(FormatPicker)
  usePlugin(FrontMenu)
  usePlugin(LinkTools, {
    jumpClick: hooks.jumpClick,
  })
  usePlugin(FootnoteTool)
  usePlugin(TableBarTools)
}

/** The loosely-typed legacy Muya surface the adapter delegates to. */
interface MuyaLike {
  container: HTMLElement
  contentState: { selectedTableCells: unknown }
  destroy(): void
  setMarkdown(markdown: string, cursor?: unknown, renderCursor?: boolean): void
  getTOC(): TocEntry[]
  on(event: string, listener: EngineEventListener): void
  focus(): void
  blur(vibrate?: boolean, noNeedRender?: boolean): void
  hasFocus(): boolean
  selectAll(): void
  getSelection(): EngineSelection | null
  setCursor(cursor: unknown): void
  undo(): void
  redo(): void
  clearHistory(): void
  setHistory(history: unknown): void
  search(value: string, options?: Record<string, unknown>): unknown
  replace(value: string, options?: Record<string, unknown>): unknown
  find(action: string): unknown
  updateParagraph(type: string): void
  duplicate(): void
  deleteParagraph(): void
  insertParagraph(location: string): void
  setFocusMode(focusMode: boolean): void
  setFont(options: Record<string, unknown>): void
  setTabSize(tabSize: number): void
  setListIndentation(listIndentation: number | string): void
  setOptions(options: Record<string, unknown>, needRender?: boolean): void
  invalidateImageCache(): void
  _replaceCurrentWordInlineUnsafe(word: string, replacement: string): void
  exportStyledHTML(options: Record<string, unknown>): Promise<string>
}

class MuyaAdapter implements EditorEngine {
  private readonly _muya: MuyaLike

  constructor(element: HTMLElement, options: EditorEngineOptions) {
    this._muya = new Muya(element, options) as unknown as MuyaLike
  }

  get container(): HTMLElement {
    return this._muya.container
  }

  destroy(): void {
    this._muya.destroy()
  }

  setMarkdown(markdown: string, cursor?: unknown, renderCursor?: boolean): void {
    this._muya.setMarkdown(markdown, cursor, renderCursor)
  }

  getTOC(): TocEntry[] {
    return this._muya.getTOC()
  }

  on(event: string, listener: EngineEventListener): void {
    this._muya.on(event, listener)
  }

  focus(): void {
    this._muya.focus()
  }

  blur(vibrate?: boolean, noNeedRender?: boolean): void {
    this._muya.blur(vibrate, noNeedRender)
  }

  hasFocus(): boolean {
    return this._muya.hasFocus()
  }

  selectAll(): void {
    this._muya.selectAll()
  }

  getSelection(): EngineSelection | null {
    return this._muya.getSelection()
  }

  setCursor(cursor: unknown): void {
    this._muya.setCursor(cursor)
  }

  hasSelectedTableCells(): boolean {
    return !!this._muya.contentState.selectedTableCells
  }

  undo(): void {
    this._muya.undo()
  }

  redo(): void {
    this._muya.redo()
  }

  clearHistory(): void {
    this._muya.clearHistory()
  }

  setHistory(history: unknown): void {
    this._muya.setHistory(history)
  }

  search(value: string, options?: Record<string, unknown>): unknown {
    return this._muya.search(value, options)
  }

  replace(value: string, options?: Record<string, unknown>): unknown {
    return this._muya.replace(value, options)
  }

  find(action: 'prev' | 'next'): unknown {
    return this._muya.find(action)
  }

  updateParagraph(type: string): void {
    this._muya.updateParagraph(type)
  }

  duplicate(): void {
    this._muya.duplicate()
  }

  deleteParagraph(): void {
    this._muya.deleteParagraph()
  }

  insertParagraph(location: 'before' | 'after'): void {
    this._muya.insertParagraph(location)
  }

  setFocusMode(focusMode: boolean): void {
    this._muya.setFocusMode(focusMode)
  }

  setFont(options: { fontSize?: number | string; lineHeight?: number | string }): void {
    this._muya.setFont(options)
  }

  setTabSize(tabSize: number): void {
    this._muya.setTabSize(tabSize)
  }

  setListIndentation(listIndentation: number | string): void {
    this._muya.setListIndentation(listIndentation)
  }

  setOptions(options: Record<string, unknown>, needRender?: boolean): void {
    this._muya.setOptions(options, needRender)
  }

  invalidateImageCache(): void {
    this._muya.invalidateImageCache()
  }

  replaceCurrentWordInline(word: string, replacement: string): void {
    this._muya._replaceCurrentWordInlineUnsafe(word, replacement)
  }

  exportStyledHTML(options: Record<string, unknown>): Promise<string> {
    return this._muya.exportStyledHTML(options)
  }
}

/**
 * Create the editing engine for an editor mount.
 */
export const createMuyaEngine = (
  element: HTMLElement,
  options: EditorEngineOptions,
  hooks: MuyaEngineHooks = {},
): EditorEngine => {
  registerMuyaPlugins(hooks)
  return new MuyaAdapter(element, options)
}
