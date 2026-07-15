import loadRenderer from '../../renderers'
import { CLASS_OR_ID } from '../../config'
import { conflict, mixins, camelToSnake } from '../../utils'
import { patch, toVNode, toHTML, h } from './snabbdom'
import { beginRules } from '../rules'
import renderInlines from './renderInlines'
import renderBlock from './renderBlock'
import type { Block } from '../types'
import type { SearchMatch as HighlightRange } from '../../types'

interface Cursor {
  start: { key: string; offset: number }
  end: { key: string; offset: number }
}

interface TokenRange {
  start: number
  end: number
}

interface ImageInfo {
  id?: string
  isSuccess?: boolean
  width?: number
  height?: number
  dispMsec?: number
  touchMsec?: number
  domsrc?: string
}

interface MuyaInstance {
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

interface MermaidRenderResult {
  svg: string
  bindFunctions?: (element: Element) => void
}

class StateRender {
  codeCache: Map<string, string>
  container: HTMLElement | null
  diagramCache: Map<string, { code: string; functionType: string }>
  eventCenter: unknown
  labels: Map<string, { href: string; title: string }>
  loadImageMap: Map<string, ImageInfo>
  loadMathMap: Map<string, unknown>
  mermaidCache: Map<string, { code: string; functionType: string }>
  muya: MuyaInstance
  renderBlock!: (
    parent: Block | null,
    block: Block,
    activeBlocks: Block[],
    matches: HighlightRange[],
    useCache?: boolean,
  ) => import('snabbdom').VNode
  renderingRowContainer: Block | null
  renderingTable: Block | null
  tokenCache: Map<string, Record<string, unknown>[]>
  urlMap: Map<string, string>
  constructor(muya: MuyaInstance) {
    this.muya = muya
    this.eventCenter = muya.contentState
    this.codeCache = new Map()
    this.loadImageMap = new Map()
    this.loadMathMap = new Map()
    this.mermaidCache = new Map()
    this.diagramCache = new Map()
    this.tokenCache = new Map()
    this.labels = new Map()
    this.urlMap = new Map()
    this.renderingTable = null
    this.renderingRowContainer = null
    this.container = null
  }

  setContainer(container: HTMLElement) {
    this.container = container
  }

  // collect link reference definition
  collectLabels(blocks: Block[]) {
    this.labels.clear()

    const travel = (block: Block) => {
      const { text, children } = block
      if (children?.length) {
        children.forEach((c: Block) => {
          travel(c)
        })
      } else if (text) {
        const tokens = beginRules.reference_definition.exec(text)
        if (tokens) {
          const key = (tokens[2] + tokens[3]).toLowerCase()
          if (!this.labels.has(key)) {
            this.labels.set(key, {
              href: tokens[6],
              title: tokens[10] || '',
            })
          }
        }
      }
    }

    blocks.forEach((b: Block) => {
      travel(b)
    })
  }

  checkConflicted(block: Block, token: { range: TokenRange }, cursor: Cursor) {
    const { start, end } = cursor
    const key = block.key
    const { start: tokenStart, end: tokenEnd } = token.range

    if (key !== start.key && key !== end.key) {
      return false
    } else if (key === start.key && key !== end.key) {
      return conflict([tokenStart, tokenEnd], [start.offset, start.offset])
    } else if (key !== start.key && key === end.key) {
      return conflict([tokenStart, tokenEnd], [end.offset, end.offset])
    } else {
      return (
        conflict([tokenStart, tokenEnd], [start.offset, start.offset]) ||
        conflict([tokenStart, tokenEnd], [end.offset, end.offset])
      )
    }
  }

  getClassName(outerClass: string, block: Block, token: { range: TokenRange }, cursor: Cursor) {
    return outerClass || (this.checkConflicted(block, token, cursor) ? CLASS_OR_ID.AG_GRAY : CLASS_OR_ID.AG_HIDE)
  }

  getHighlightClassName(active: boolean) {
    return active ? CLASS_OR_ID.AG_HIGHLIGHT : CLASS_OR_ID.AG_SELECTION
  }

  getSelector(block: Block, activeBlocks: Block[]) {
    const { cursor, selectedBlock } = this.muya.contentState
    const type = block.type === 'hr' ? 'p' : block.type
    const isActive = activeBlocks.some((b: Block) => b.key === block.key) || block.key === cursor.start.key

    let selector = `${type}#${block.key}.${CLASS_OR_ID.AG_PARAGRAPH}`
    if (isActive) {
      selector += `.${CLASS_OR_ID.AG_ACTIVE}`
    }
    if (type === 'span') {
      selector += `.ag-${camelToSnake(block.functionType as string)}`
    }
    if (!block.parent && selectedBlock && block.key === selectedBlock.key) {
      selector += `.${CLASS_OR_ID.AG_SELECTED}`
    }
    return selector
  }

  getMermaidOffscreenCanvas() {
    let canvas = document.querySelector('#ag-mermaid-canvas') as HTMLDivElement | null
    if (!canvas) {
      canvas = document.createElement('div')
      canvas.id = 'ag-mermaid-canvas'
      Object.assign(canvas.style, {
        position: 'absolute',
        left: '-99999px',
        top: '0',
        opacity: '0',
        pointerEvents: 'none',
        overflow: 'hidden',
        zIndex: '-1',
      })
      document.body.appendChild(canvas)
    }

    canvas.innerHTML = ''
    return canvas
  }

  tightenMermaidSvg(svg: SVGSVGElement) {
    const styleText = svg.getAttribute('style') ?? ''
    const maxWidthMatch = /max-width:\s*([\d.]+)px/.exec(styleText)
    const widthAttr = Number.parseFloat(svg.getAttribute('width') ?? '')
    const heightAttr = Number.parseFloat(svg.getAttribute('height') ?? '')
    const viewBoxValues = (svg.getAttribute('viewBox') ?? '')
      .trim()
      .split(/\s+/)
      .map((value) => Number.parseFloat(value))
    const viewBoxWidth = Number.isFinite(viewBoxValues[2]) ? viewBoxValues[2] : 0
    const viewBoxHeight = Number.isFinite(viewBoxValues[3]) ? viewBoxValues[3] : 0

    let intrinsicWidth = maxWidthMatch ? Math.ceil(Number.parseFloat(maxWidthMatch[1])) : 0
    if (!intrinsicWidth && Number.isFinite(widthAttr) && widthAttr > 0) {
      intrinsicWidth = Math.ceil(widthAttr)
    }
    if (!intrinsicWidth && viewBoxWidth > 0) {
      intrinsicWidth = Math.ceil(viewBoxWidth)
    }

    let intrinsicHeight = Number.isFinite(heightAttr) && heightAttr > 0 ? Math.ceil(heightAttr) : 0
    if (!intrinsicHeight && intrinsicWidth > 0 && viewBoxWidth > 0 && viewBoxHeight > 0) {
      intrinsicHeight = Math.ceil((intrinsicWidth / viewBoxWidth) * viewBoxHeight)
    }

    if ((!intrinsicWidth || !intrinsicHeight) && svg.getBBox) {
      const { x, y, width, height } = svg.getBBox()
      const padding = 24
      intrinsicWidth = Math.ceil(width + padding * 2)
      intrinsicHeight = Math.ceil(height + padding * 2)
      svg.setAttribute('viewBox', `${x - padding} ${y - padding} ${intrinsicWidth} ${intrinsicHeight}`)
    }

    if (!intrinsicWidth || !intrinsicHeight) {
      return null
    }

    svg.setAttribute('width', `${intrinsicWidth}`)
    svg.setAttribute('height', `${intrinsicHeight}`)
    svg.setAttribute('preserveAspectRatio', 'xMinYMin meet')
    svg.style.width = `${intrinsicWidth}px`
    svg.style.maxWidth = 'none'
    svg.style.height = `${intrinsicHeight}px`

    return {
      intrinsicWidth,
      intrinsicHeight,
    }
  }

  async renderMermaidToStaticSvg(
    mermaid: {
      render: (id: string, text: string, container?: Element) => MermaidRenderResult | Promise<MermaidRenderResult>
    },
    code: string,
    renderId: string,
  ) {
    const offscreenCanvas = this.getMermaidOffscreenCanvas()
    const tempContainer = document.createElement('div')
    tempContainer.id = renderId
    offscreenCanvas.appendChild(tempContainer)

    const renderResult = await Promise.resolve(mermaid.render(renderId, code))
    const svgMarkup = typeof renderResult === 'string' ? renderResult : renderResult.svg
    tempContainer.innerHTML = svgMarkup

    await new Promise<void>((resolve) => {
      requestAnimationFrame(() => {
        resolve()
      })
    })

    const svg = tempContainer.querySelector('svg')
    if (!(svg instanceof SVGSVGElement)) {
      offscreenCanvas.innerHTML = ''
      return null
    }

    const dimensions = this.tightenMermaidSvg(svg)
    const markup = svg.outerHTML
    offscreenCanvas.innerHTML = ''

    if (!dimensions) {
      return null
    }

    return {
      markup,
      ...dimensions,
    }
  }

  async renderMermaid() {
    if (this.mermaidCache.size) {
      const mermaid = (await loadRenderer('mermaid')) as {
        initialize: (opts: Record<string, unknown>) => void
        parse: (code: string) => void
        render: (id: string, text: string, container?: Element) => MermaidRenderResult | Promise<MermaidRenderResult>
      }
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        theme: this.muya.options.mermaidTheme,
      })
      for (const [key, value] of this.mermaidCache.entries()) {
        const { code } = value
        const target = document.querySelector(key)
        if (!target) {
          continue
        }
        try {
          mermaid.parse(code)
          const renderId = `${key.replace(/^#/, 'ag-mermaid-static-')}-${Date.now().toString(36)}`
          const renderedSvg = await this.renderMermaidToStaticSvg(mermaid, code, renderId)
          if (!renderedSvg) {
            throw new Error('Unable to render Mermaid SVG.')
          }

          target.innerHTML = renderedSvg.markup
          ;(target as HTMLElement).style.setProperty('--ag-mermaid-preview-width', `${renderedSvg.intrinsicWidth}px`)
          ;(target as HTMLElement).style.setProperty('--ag-mermaid-preview-height', `${renderedSvg.intrinsicHeight}px`)
        } catch (_err) {
          target.innerHTML = '< Invalid Mermaid Codes >'
          target.classList.add(CLASS_OR_ID.AG_MATH_ERROR)
        }
      }

      this.mermaidCache.clear()
    }
  }

  async renderDiagram() {
    const cache = this.diagramCache
    if (cache.size) {
      // biome-ignore lint/suspicious/noExplicitAny: diagram renderers have heterogeneous APIs
      const RENDER_MAP: Record<string, any> = {
        flowchart: await loadRenderer('flowchart'),
        sequence: await loadRenderer('sequence'),
        plantuml: await loadRenderer('plantuml'),
        'vega-lite': await loadRenderer('vega-lite'),
      }

      for (const [key, value] of cache.entries()) {
        const target = document.querySelector(key)
        if (!target) {
          continue
        }
        const { code, functionType } = value
        const render = RENDER_MAP[functionType]
        const options: Record<string, unknown> = {}
        if (functionType === 'sequence') {
          Object.assign(options, { theme: this.muya.options.sequenceTheme })
        } else if (functionType === 'vega-lite') {
          Object.assign(options, {
            actions: false,
            tooltip: false,
            renderer: 'svg',
            theme: this.muya.options.vegaTheme,
          })
        }
        try {
          if (functionType === 'flowchart' || functionType === 'sequence') {
            const diagram = render.parse(code)
            target.innerHTML = ''
            diagram.drawSVG(target, options)
          } else if (functionType === 'plantuml') {
            const diagram = render.parse(code)
            target.innerHTML = ''
            diagram.insertImgElement(target)
          } else if (functionType === 'vega-lite') {
            await render(key, JSON.parse(code), options)
          }
        } catch (_err) {
          target.innerHTML = `< Invalid ${functionType === 'flowchart' ? 'Flow Chart' : 'Sequence'} Codes >`
          target.classList.add(CLASS_OR_ID.AG_MATH_ERROR)
        }
      }
      this.diagramCache.clear()
    }
  }

  render(blocks: Block[], activeBlocks: Block[], matches: HighlightRange[]) {
    const selector = `div#${CLASS_OR_ID.AG_EDITOR_ID}`
    const children = blocks.map((block: Block) => {
      return this.renderBlock(null, block, activeBlocks, matches, true)
    })
    const newVdom = h(selector, children)
    const rootDom = document.querySelector(selector) || this.container
    const oldVdom = toVNode(rootDom!)

    patch(oldVdom, newVdom)
    this.renderMermaid()
    this.renderDiagram()
    this.codeCache.clear()
  }

  // Only render the blocks which you updated
  partialRender(
    blocks: Block[],
    activeBlocks: Block[],
    matches: HighlightRange[],
    startKey: string | null,
    endKey: string | null,
  ) {
    const cursorOutMostBlock = activeBlocks[activeBlocks.length - 1]
    // If cursor is not in render blocks, need to render cursor block independently
    const needRenderCursorBlock = blocks.indexOf(cursorOutMostBlock) === -1
    const newVnode = h(
      'section',
      blocks.map((block: Block) => this.renderBlock(null, block, activeBlocks, matches)),
    )
    const html = toHTML(newVnode).replace(/^<section>([\s\S]+?)<\/section>$/, '$1')

    const needToRemoved: Element[] = []
    const firstOldDom = startKey
      ? document.querySelector(`#${startKey}`)
      : (document.querySelector(`div#${CLASS_OR_ID.AG_EDITOR_ID}`)?.firstElementChild ?? null)
    if (!firstOldDom) {
      // TODO@Jocs Just for fix #541, Because I'll rewrite block and render method, it will nolonger have this issue.
      return
    }
    needToRemoved.push(firstOldDom)
    let nextSibling = firstOldDom.nextElementSibling
    while (nextSibling && nextSibling.id !== endKey) {
      needToRemoved.push(nextSibling)
      nextSibling = nextSibling.nextElementSibling
    }
    nextSibling && needToRemoved.push(nextSibling)

    firstOldDom.insertAdjacentHTML('beforebegin', html)

    Array.from(needToRemoved).forEach((dom) => {
      dom.remove()
    })

    // Render cursor block independently
    if (needRenderCursorBlock && cursorOutMostBlock) {
      const { key } = cursorOutMostBlock
      if (!key) return
      const cursorDom = document.querySelector(`#${key}`)
      if (cursorDom) {
        const oldCursorVnode = toVNode(cursorDom)
        const newCursorVnode = this.renderBlock(null, cursorOutMostBlock, activeBlocks, matches)
        patch(oldCursorVnode, newCursorVnode)
      }
    }

    this.renderMermaid()
    this.renderDiagram()
    this.codeCache.clear()
  }

  /**
   * Only render one block.
   *
   * @param {object} block
   * @param {array} activeBlocks
   * @param {array} matches
   */
  singleRender(block: Block, activeBlocks: Block[], matches: HighlightRange[]) {
    if (!block.key) return
    const selector = `#${block.key}`
    const newVdom = this.renderBlock(null, block, activeBlocks, matches, true)
    const rootDom = document.querySelector(selector)
    if (!rootDom) return
    const oldVdom = toVNode(rootDom)
    patch(oldVdom, newVdom)
    this.renderMermaid()
    this.renderDiagram()
    this.codeCache.clear()
  }

  invalidateImageCache() {
    this.loadImageMap.forEach((imageInfo: ImageInfo, key: string) => {
      imageInfo.touchMsec = Date.now()
      this.loadImageMap.set(key, imageInfo)
    })
  }
}

mixins(StateRender as unknown as { prototype: Record<string, unknown> }, renderInlines, renderBlock)

export default StateRender
