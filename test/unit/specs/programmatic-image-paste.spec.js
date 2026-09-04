import { describe, expect, it, vi } from 'vitest'
import pasteCtrl from '../../../src/muya/lib/contentState/pasteCtrl'

class TestContentState {}
pasteCtrl(TestContentState)

describe('programmatic image paste', () => {
  it('routes a screenshot path through imageAction and replaces the placeholder', async () => {
    const container = document.createElement('div')
    const paragraph = document.createElement('p')
    paragraph.classList.add('ag-paragraph')
    paragraph.id = 'block-1'
    container.appendChild(paragraph)

    const state = new TestContentState()
    state.selectedImage = null
    state.stateRender = { urlMap: new Map() }
    state.insertImage = vi.fn(({ alt, src }) => {
      const wrapper = document.createElement('span')
      wrapper.dataset.id = alt
      wrapper.dataset.raw = `![${alt}](${src})`
      paragraph.appendChild(wrapper)
    })
    state.replaceImage = vi.fn()
    state.muya = {
      container,
      options: { imageAction: vi.fn().mockResolvedValue('assets/capture.png') },
    }

    await expect(state.pasteImageSrc('/tmp/capture.png')).resolves.toBe('/tmp/capture.png')
    expect(state.muya.options.imageAction).toHaveBeenCalledWith('/tmp/capture.png', expect.stringMatching(/^loading-/))
    expect(state.replaceImage).toHaveBeenCalledWith(expect.objectContaining({ key: 'block-1' }), {
      src: 'assets/capture.png',
    })
  })

  it('does nothing for an empty path', async () => {
    const state = new TestContentState()
    state.insertImage = vi.fn()

    await expect(state.pasteImageSrc('')).resolves.toBeNull()
    expect(state.insertImage).not.toHaveBeenCalled()
  })
})
