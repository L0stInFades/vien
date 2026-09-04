import { afterEach, describe, expect, it, vi } from 'vitest'
import Keyboard from '../../../src/muya/lib/eventHandler/keyboard'

const cleanups = []

afterEach(() => {
  while (cleanups.length) cleanups.pop()()
})

const bootKeyboard = () => {
  const container = document.createElement('div')
  document.body.appendChild(container)
  const listeners = []
  const contentState = {
    inputHandler: vi.fn(),
    backspaceHandler: vi.fn(),
    deleteHandler: vi.fn(),
    enterHandler: vi.fn(),
    arrowHandler: vi.fn(),
    tabHandler: vi.fn(),
    docEnterHandler: vi.fn(),
    docBackspaceHandler: vi.fn(),
    docDeleteHandler: vi.fn(),
    docArrowHandler: vi.fn(),
  }
  const eventCenter = {
    subscribe: vi.fn(),
    dispatch: vi.fn(),
    attachDOMEvent(target, type, handler) {
      target.addEventListener(type, handler)
      listeners.push(() => target.removeEventListener(type, handler))
    },
  }
  const muya = {
    container,
    contentState,
    eventCenter,
    dispatchChange: vi.fn(),
    dispatchSelectionChange: vi.fn(),
    dispatchSelectionFormats: vi.fn(),
  }
  const keyboard = new Keyboard(muya)
  cleanups.push(() => {
    listeners.forEach((remove) => {
      remove()
    })
    container.remove()
  })
  return { container, contentState, keyboard }
}

const press = (container, key) => {
  const event = new KeyboardEvent('keydown', {
    key,
    code: key,
    bubbles: true,
    cancelable: true,
  })
  container.dispatchEvent(event)
  return event
}

describe('Muya keyboard handling during IME composition', () => {
  it.each([
    ['Backspace', 'backspaceHandler', 'docBackspaceHandler'],
    ['Delete', 'deleteHandler', 'docDeleteHandler'],
    ['Tab', 'tabHandler', null],
  ])('leaves %s to the IME', (key, localHandler, documentHandler) => {
    const { container, contentState, keyboard } = bootKeyboard()
    container.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }))

    const event = press(container, key)

    expect(keyboard.isComposed).toBe(true)
    expect(contentState[localHandler]).not.toHaveBeenCalled()
    if (documentHandler) expect(contentState[documentHandler]).not.toHaveBeenCalled()
    expect(event.defaultPrevented).toBe(false)
  })

  it('keeps normal Backspace handling outside composition', () => {
    const { container, contentState } = bootKeyboard()

    press(container, 'Backspace')

    expect(contentState.backspaceHandler).toHaveBeenCalledOnce()
    expect(contentState.docBackspaceHandler).toHaveBeenCalledOnce()
  })
})
