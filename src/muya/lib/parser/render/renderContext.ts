/**
 * StateRenderContext — captures all properties and methods available on `this`
 * in StateRender mixin functions (renderBlock, renderInlines, etc.).
 *
 * Use `this: StateRenderContext` instead of `this: any` in mixin methods.
 */

import type { h as hFn, VNode } from 'snabbdom'
import type { Block } from '../types'
import type { Token, SearchMatch } from '../../types'

// ---------------------------------------------------------------------------
// Helper sub-types (re-exported from index.ts locals for shared use)
// ---------------------------------------------------------------------------

export interface Cursor {
  start: { key: string; offset: number }
  end: { key: string; offset: number }
}

export interface TokenRange {
  start: number
  end: number
}

export interface ImageInfo {
  id?: string
  isSuccess?: boolean
  width?: number
  height?: number
  dispMsec?: number
  touchMsec?: number
  domsrc?: string
}

export interface MuyaInstance {
  contentState: {
    cursor: Cursor
    selectedBlock: Block | null
    selectedTableCells: { cells: Array<{ key: string; [key: string]: unknown }> } | null
    selectedImage: {
      key: string
      token: { attrs?: Record<string, string>; range: TokenRange }
      imageId?: string
    } | null
    [k: string]: unknown
  }
  options: Record<string, unknown>
  [k: string]: unknown
}

// ---------------------------------------------------------------------------
// Match type used across render methods
// ---------------------------------------------------------------------------

export type HighlightRange = SearchMatch

// ---------------------------------------------------------------------------
// Inline render method signature
// ---------------------------------------------------------------------------

/** Signature shared by most renderInlines methods (backlash, link, del, em, strong, etc.) */
export type InlineRenderMethod = (
  h: typeof hFn,
  cursor: Cursor,
  block: Block,
  token: Token,
  outerClass?: string,
) => (string | VNode)[]

// ---------------------------------------------------------------------------
// StateRenderContext interface
// ---------------------------------------------------------------------------

export interface StateRenderContext {
  // ---- Properties from StateRender class ----

  codeCache: Map<string, string>
  container: HTMLElement | null
  diagramCache: Map<string, { code: string; functionType: string }>
  eventCenter: unknown
  labels: Map<string, { href: string; title: string }>
  loadImageMap: Map<string, ImageInfo>
  loadMathMap: Map<string, unknown>
  mermaidCache: Map<string, { code: string; functionType: string }>
  muya: MuyaInstance
  renderingRowContainer: Block | null
  renderingTable: Block | null
  tokenCache: Map<string, Record<string, unknown>[]>
  urlMap: Map<string, string>

  // ---- Methods from StateRender class ----

  setContainer(container: HTMLElement): void

  collectLabels(blocks: Block[]): void

  checkConflicted(block: Block, token: { range: TokenRange }, cursor: Cursor): boolean

  getClassName(outerClass: string, block: Block, token: { range: TokenRange }, cursor: Cursor): string

  getHighlightClassName(active: boolean): string

  getSelector(block: Block, activeBlocks: Block[]): string

  renderMermaid(): Promise<void>

  renderDiagram(): Promise<void>

  render(blocks: Block[], activeBlocks: Block[], matches: HighlightRange[]): void

  partialRender(
    blocks: Block[],
    activeBlocks: Block[],
    matches: HighlightRange[],
    startKey: string | null,
    endKey: string | null,
  ): void

  singleRender(block: Block, activeBlocks: Block[], matches: HighlightRange[]): void

  invalidateImageCache(): void

  // ---- Mixin methods from renderBlock ----

  renderBlock(
    parent: Block | null,
    block: Block,
    activeBlocks: Block[],
    matches: HighlightRange[],
    useCache?: boolean,
  ): VNode

  renderContainerBlock(
    parent: Block | null,
    block: Block,
    activeBlocks: Block[],
    matches: HighlightRange[],
    useCache?: boolean,
  ): VNode

  renderLeafBlock(
    parent: Block | null,
    block: Block,
    activeBlocks: Block[],
    matches: HighlightRange[],
    useCache?: boolean,
  ): VNode

  // ---- Mixin methods from renderInlines ----

  backlash: InlineRenderMethod
  highlight(h: typeof hFn, block: Block, rStart: number, rEnd: number, token: Token): (string | VNode)[]
  header: InlineRenderMethod
  link: InlineRenderMethod
  htmlTag: InlineRenderMethod
  hr: InlineRenderMethod
  tailHeader: InlineRenderMethod
  hardLineBreak: InlineRenderMethod
  softLineBreak: InlineRenderMethod
  codeFense: InlineRenderMethod
  inlineMath: InlineRenderMethod
  autoLink: InlineRenderMethod
  autoLinkExtension: InlineRenderMethod

  loadImageAsync(
    imageInfo: { src: string; isUnknownType?: boolean; [k: string]: unknown },
    attrs: {
      alt?: string
      title?: string
      width?: number
      height?: number
      [k: string]: unknown
    },
    className?: string,
    imageClass?: string,
  ): {
    id: string | undefined
    isSuccess: boolean | undefined
    domsrc: string | undefined
    width: number | undefined
    height: number | undefined
  }

  image: InlineRenderMethod
  emoji: InlineRenderMethod
  inlineCode: InlineRenderMethod
  text: InlineRenderMethod
  del: InlineRenderMethod
  em: InlineRenderMethod
  strong: InlineRenderMethod
  htmlEscape: InlineRenderMethod
  multipleMath: InlineRenderMethod
  referenceDefinition: InlineRenderMethod
  htmlRuby: InlineRenderMethod
  referenceLink: InlineRenderMethod
  referenceImage: InlineRenderMethod
  superSubScript: InlineRenderMethod
  footnoteIdentifier: InlineRenderMethod

  backlashInToken(
    h: typeof hFn,
    backlashes: string,
    outerClass: string,
    start: number,
    token: Token,
  ): (string | VNode)[]

  delEmStrongFac(
    type: string,
    h: typeof hFn,
    cursor: unknown,
    block: Block,
    token: Token,
    outerClass: string,
  ): (string | VNode)[]

  // Index signature for dynamic dispatch via snakeToCamel(token.type)
  [key: string]: unknown
}
