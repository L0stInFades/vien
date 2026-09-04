import { describe, expect, it, vi } from 'vitest'
import imageCtrl from '../../../src/muya/lib/contentState/imageCtrl'

class TestContentState {}
imageCtrl(TestContentState)

const makeContentState = (text) => {
  const block = { text }
  const state = new TestContentState()
  state.getBlock = vi.fn(() => block)
  state.singleRender = vi.fn()
  state.muva = null
  state.muya = { dispatchChange: vi.fn() }
  return { block, state }
}

describe('HTML image attribute serialization', () => {
  it('escapes quotes when updating an attribute', () => {
    const raw = '<img src="safe.png">'
    const { block, state } = makeContentState(raw)

    state.updateImage(
      {
        imageId: 'missing',
        key: 'block-1',
        token: { range: { start: 0, end: raw.length }, attrs: { src: 'safe.png' } },
      },
      'title',
      'caption" onerror="alert(1)',
    )

    expect(block.text).toBe('<img src="safe.png" title="caption&quot; onerror=&quot;alert(1)">')
  })

  it('escapes values when replacing a raw HTML image', () => {
    const raw = '<img src="old.png">'
    const { block, state } = makeContentState(raw)

    state.replaceImage(
      {
        key: 'block-1',
        token: { type: 'html_tag', range: { start: 0, end: raw.length }, attrs: {} },
      },
      { alt: 'x" autofocus="', src: 'new.png', title: '<unsafe>' },
    )

    expect(block.text).toContain('alt="x&quot; autofocus=&quot;"')
    expect(block.text).toContain('title="&lt;unsafe&gt;"')
  })
})
