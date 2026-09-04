// @vitest-environment jsdom

import { resolve } from 'node:path'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const exportHtmlModuleId = resolve(process.cwd(), 'src/muya/lib/utils/exportHtml.ts')
const rendererModuleId = resolve(process.cwd(), 'src/muya/lib/renderers/index.ts')
const mermaidInitialize = vi.fn()
const mermaidRun = vi.fn()

vi.doUnmock(exportHtmlModuleId)
vi.doMock(rendererModuleId, () => ({
  default: vi.fn(async (name) => {
    if (name !== 'mermaid') throw new Error(`Unexpected renderer: ${name}`)
    return {
      initialize: mermaidInitialize,
      run: mermaidRun,
    }
  }),
}))

const { default: ExportHtml } = await import(exportHtmlModuleId)

beforeEach(() => {
  mermaidInitialize.mockReset()
  mermaidRun.mockReset()
})

describe('Mermaid HTML export resilience', () => {
  it('contains an invalid diagram without blocking a later valid diagram', async () => {
    mermaidRun.mockRejectedValueOnce(new Error('Parse error')).mockImplementationOnce(async ({ nodes }) => {
      nodes[0].innerHTML = '<svg data-testid="valid-mermaid"></svg>'
    })

    const markdown = [
      '# Diagrams',
      '',
      '```mermaid',
      'graph LR',
      'A--->',
      '```',
      '',
      '```mermaid',
      'graph TD; A-->B',
      '```',
    ].join('\n')
    const muya = { options: { mermaidTheme: 'dark' } }

    const html = await new ExportHtml(markdown, muya).renderHtml()

    expect(mermaidRun).toHaveBeenCalledTimes(2)
    expect(html).toContain('&lt; Invalid Diagram &gt;')
    expect(html).toContain('data-testid="valid-mermaid"')
    expect(mermaidInitialize).toHaveBeenNthCalledWith(1, {
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'default',
    })
    expect(mermaidInitialize).toHaveBeenLastCalledWith({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'dark',
    })
  })
})
