/**
 * EditorEngine contract (PLAN.md CORE-001 / §5.5, ADR-002).
 *
 * The Vue shell talks to the editing kernel ONLY through this interface.
 * It captures the capability surface the shell actually uses today; the
 * Phase 3 target narrows it toward source transactions
 * (open/apply/getSnapshot/execute/subscribe — see ADR-001/ADR-002). Every
 * method added here is a liability for the engine swap: extend it only
 * when the shell genuinely needs a new capability, never for convenience.
 *
 * No Muya types leak through this file — that is the point.
 */

export type EngineEventListener = (...payload: unknown[]) => void

export interface EditorEngineOptions {
  markdown?: string
  [key: string]: unknown
}

export interface EngineSelection {
  start?: unknown
  end?: unknown
  [key: string]: unknown
}

export interface TocEntry {
  content: string
  lvl: number
  slug: string
}

export interface EditorEngine {
  /** Root DOM element the engine renders into. */
  readonly container: HTMLElement

  // --- lifecycle -----------------------------------------------------------
  destroy(): void

  // --- content -------------------------------------------------------------
  setMarkdown(markdown: string, cursor?: unknown, renderCursor?: boolean): void
  getTOC(): TocEntry[]

  // --- events --------------------------------------------------------------
  on(event: string, listener: EngineEventListener): void

  // --- focus & selection ---------------------------------------------------
  focus(): void
  blur(vibrate?: boolean, noNeedRender?: boolean): void
  hasFocus(): boolean
  selectAll(): void
  getSelection(): EngineSelection | null
  setCursor(cursor: unknown): void
  /** True while a table cell-range selection is active (guards copy handling). */
  hasSelectedTableCells(): boolean

  // --- history -------------------------------------------------------------
  undo(): void
  redo(): void
  clearHistory(): void
  setHistory(history: unknown): void

  // --- search --------------------------------------------------------------
  search(value: string, options?: Record<string, unknown>): unknown
  replace(value: string, options?: Record<string, unknown>): unknown
  find(action: 'prev' | 'next'): unknown

  // --- commands ------------------------------------------------------------
  updateParagraph(type: string): void
  duplicate(): void
  deleteParagraph(): void
  insertParagraph(location: 'before' | 'after'): void
  setFocusMode(focusMode: boolean): void
  setFont(options: { fontSize?: number | string; lineHeight?: number | string }): void
  setTabSize(tabSize: number): void
  setListIndentation(listIndentation: number | string): void
  setOptions(options: Record<string, unknown>, needRender?: boolean): void
  invalidateImageCache(): void
  /** Replace the word at the cursor (spellchecker suggestion flow). */
  replaceCurrentWordInline(word: string, replacement: string): void

  // --- export --------------------------------------------------------------
  exportStyledHTML(options: Record<string, unknown>): Promise<string>
}
