import { afterEach, describe, expect, test, vi } from 'vitest'

import createCodeMirror, {
  getBeginPosition,
  getEndPosition,
  isCursorAtBegin,
  isCursorAtEnd,
  isCursorAtFirstLine,
  isCursorAtLastLine,
  onlyHaveOneLine,
  setCursorAtFirstLine,
  setCursorAtLastLine,
  setMode,
  setTextDirection,
} from '@/codeMirror'

describe('CodeMirror 6 compatibility facade', () => {
  let editor

  afterEach(() => {
    editor?.destroy()
    editor = null
    document.body.replaceChildren()
  })

  test('preserves the source editor text, cursor and selection contract', () => {
    const parent = document.createElement('div')
    document.body.append(parent)
    editor = createCodeMirror(parent, {
      value: 'first\nsecond',
      autofocus: false,
      lineWrapping: true,
      direction: 'ltr',
    })

    expect(editor.getValue()).toBe('first\nsecond')
    expect(editor.lineCount()).toBe(2)
    expect(editor.lastLine()).toBe(1)
    expect(editor.getLine(0)).toBe('first')
    expect(editor.getLineHandle(1)).toEqual({ text: 'second' })
    expect(editor.getLine(2)).toBeNull()
    expect(getBeginPosition()).toEqual({
      anchor: { line: 0, ch: 0 },
      head: { line: 0, ch: 0 },
    })
    expect(getEndPosition(editor)).toEqual({
      anchor: { line: 1, ch: 6 },
      head: { line: 1, ch: 6 },
    })

    editor.setSelection({ line: 0, ch: 2 }, { line: 1, ch: 3 })
    expect(editor.getCursor('anchor')).toEqual({ line: 0, ch: 2 })
    expect(editor.getCursor('head')).toEqual({ line: 1, ch: 3 })

    setCursorAtFirstLine(editor)
    expect(isCursorAtBegin(editor)).toBe(true)
    expect(isCursorAtFirstLine(editor)).toBe(true)

    setCursorAtLastLine(editor)
    expect(isCursorAtEnd(editor)).toBe(true)
    expect(isCursorAtLastLine(editor)).toBe(true)
    expect(onlyHaveOneLine(editor)).toBe(false)

    editor.setCursor(99, 99)
    expect(editor.getCursor()).toEqual({ line: 1, ch: 6 })
  })

  test('keeps change events, history, commands and direction working', async () => {
    const parent = document.createElement('div')
    document.body.append(parent)
    editor = createCodeMirror(parent, { value: 'before', direction: 'ltr' })
    const onActivity = vi.fn()
    editor.on('cursorActivity', onActivity)

    editor.setValue('after')
    expect(editor.getValue()).toBe('after')
    expect(onActivity).toHaveBeenCalled()
    expect(editor.undo()).toBe(true)
    expect(editor.getValue()).toBe('before')
    expect(editor.redo()).toBe(true)
    expect(editor.getValue()).toBe('after')

    expect(editor.execCommand('selectAll')).toBe(true)
    expect(editor.getCursor('anchor')).toEqual({ line: 0, ch: 0 })
    expect(editor.getCursor('head')).toEqual({ line: 0, ch: 5 })
    expect(editor.execCommand('unknown')).toBe(false)

    setTextDirection(editor, 'rtl')
    expect(editor.view.contentDOM.dir).toBe('rtl')
    setTextDirection(editor, 'invalid')
    expect(editor.view.contentDOM.dir).toBe('ltr')

    await expect(setMode(editor, 'markdown')).resolves.toMatchObject({ name: 'markdown' })
    await expect(setMode(editor, 'javascript')).rejects.toThrow('not a supported source editor mode')
  })
})
