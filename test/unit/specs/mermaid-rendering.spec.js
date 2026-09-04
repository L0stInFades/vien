// @vitest-environment jsdom

import { resolve } from 'node:path'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const rendererModuleId = resolve(process.cwd(), 'src/muya/lib/renderers/index.ts')
const mermaid = {
  initialize: vi.fn(),
  parse: vi.fn(),
  render: vi.fn(),
}

vi.doMock(rendererModuleId, () => ({
  default: vi.fn(async (name) => {
    if (name !== 'mermaid') throw new Error(`Unexpected renderer: ${name}`)
    return mermaid
  }),
}))

const { default: StateRender } = await import('../../../src/muya/lib/parser/render/index.ts')

const createStateRender = () => {
  const stateRender = new StateRender({
    contentState: {
      cursor: { start: { key: '', offset: 0 }, end: { key: '', offset: 0 } },
      selectedBlock: null,
    },
    options: { mermaidTheme: 'default' },
  })
  stateRender.mermaidCache.set('#preview', { code: 'graph TD; A-->B', functionType: 'mermaid' })
  return stateRender
}

beforeEach(() => {
  document.body.innerHTML = '<div id="preview"></div>'
  vi.stubGlobal('requestAnimationFrame', (callback) => callback(0))
  mermaid.initialize.mockReset()
  mermaid.parse.mockReset()
  mermaid.render.mockReset()
})

describe('Mermaid editor rendering', () => {
  it('awaits parse failures and contains them in the preview', async () => {
    mermaid.parse.mockRejectedValue(new Error('Parse error'))

    const stateRender = createStateRender()
    await stateRender.renderMermaid()

    const preview = document.querySelector('#preview')
    expect(mermaid.render).not.toHaveBeenCalled()
    expect(preview.textContent).toBe('< Invalid Mermaid Codes >')
    expect(preview.classList.contains('ag-math-error')).toBe(true)
  })

  it('clears an old error state after a later valid render', async () => {
    const preview = document.querySelector('#preview')
    preview.classList.add('ag-math-error')
    mermaid.parse.mockResolvedValue({ diagramType: 'flowchart-v2' })
    mermaid.render.mockResolvedValue({
      svg: '<svg width="120" height="60" viewBox="0 0 120 60"></svg>',
    })

    const stateRender = createStateRender()
    await stateRender.renderMermaid()

    expect(preview.querySelector('svg')).not.toBeNull()
    expect(preview.classList.contains('ag-math-error')).toBe(false)
    expect(preview.style.getPropertyValue('--ag-mermaid-preview-width')).toBe('120px')
    expect(document.querySelector('#ag-mermaid-canvas').children).toHaveLength(0)
  })

  it('does not let an older async render overwrite newer source', async () => {
    let resolveFirstRender
    let markFirstRenderStarted
    const firstRenderStarted = new Promise((resolve) => {
      markFirstRenderStarted = resolve
    })
    mermaid.parse.mockResolvedValue({ diagramType: 'flowchart-v2' })
    mermaid.render
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirstRender = resolve
            markFirstRenderStarted()
          }),
      )
      .mockResolvedValueOnce({
        svg: '<svg width="200" height="80" data-source="new"></svg>',
      })

    const stateRender = createStateRender()
    const first = stateRender.renderMermaid()
    await firstRenderStarted
    stateRender.mermaidCache.set('#preview', { code: 'graph TD; A-->C', functionType: 'mermaid' })
    const second = stateRender.renderMermaid()
    await Promise.resolve()
    expect(mermaid.render).toHaveBeenCalledTimes(1)
    resolveFirstRender({ svg: '<svg width="100" height="40" data-source="old"></svg>' })

    await Promise.all([first, second])

    expect(document.querySelector('#preview svg').dataset.source).toBe('new')
  })
})
