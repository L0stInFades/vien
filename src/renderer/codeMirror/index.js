import { redo as redoCommand, selectAll, undo as undoCommand } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { Compartment, EditorSelection } from '@codemirror/state'
import { EditorView, basicSetup } from 'codemirror'

import './index.css'

const normalizeDirection = (direction) => (direction === 'rtl' ? 'rtl' : 'ltr')

const positionFromCursor = (doc, cursor = {}) => {
  const requestedLine = Number.isFinite(cursor.line) ? cursor.line + 1 : 1
  const line = doc.line(Math.max(1, Math.min(doc.lines, requestedLine)))
  const requestedColumn = Number.isFinite(cursor.ch) ? cursor.ch : 0
  return Math.max(line.from, Math.min(line.to, line.from + requestedColumn))
}

const cursorFromPosition = (doc, position) => {
  const line = doc.lineAt(position)
  return { line: line.number - 1, ch: position - line.from }
}

const sourceTheme = EditorView.theme({
  '&': {
    height: 'auto',
    color: 'var(--editorColor)',
    backgroundColor: 'transparent',
  },
  '&.cm-focused': { outline: 'none' },
  '.cm-scroller': {
    overflow: 'visible',
    fontFamily: 'inherit',
    lineHeight: 'inherit',
  },
  '.cm-content': {
    minHeight: 'calc(100vh - var(--titleBarHeight) - 100px)',
    caretColor: 'var(--editorColor)',
  },
  '.cm-cursor, .cm-dropCursor': { borderLeftColor: 'var(--editorColor)' },
  '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection': {
    backgroundColor: 'var(--selectionColor)',
  },
  '.cm-gutters': {
    color: 'var(--editorColor50)',
    backgroundColor: 'transparent',
    borderRight: 'none',
  },
  '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: 'var(--floatHoverColor)' },
})

class CodeMirrorCompat {
  constructor(parent, config = {}) {
    this.listeners = new Map()
    this.domListeners = []
    this.direction = new Compartment()

    const extensions = [
      basicSetup,
      markdown(),
      sourceTheme,
      this.direction.of(EditorView.contentAttributes.of({ dir: normalizeDirection(config.direction) })),
      EditorView.updateListener.of((update) => {
        if (update.docChanged || update.selectionSet) {
          this.emit('cursorActivity')
        }
      }),
    ]
    if (config.lineWrapping !== false) {
      extensions.push(EditorView.lineWrapping)
    }

    this.view = new EditorView({
      doc: config.value ?? '',
      extensions,
      parent,
    })
    this.view.dom.classList.add('CodeMirror', `cm-s-${config.theme || 'default'}`)

    if (config.autofocus) {
      queueMicrotask(() => this.focus())
    }
  }

  emit(event, ...args) {
    for (const listener of this.listeners.get(event) ?? []) {
      listener(this, ...args)
    }
  }

  on(event, listener) {
    if (event === 'contextmenu') {
      const wrapped = (domEvent) => listener(this, domEvent)
      this.view.dom.addEventListener(event, wrapped)
      this.domListeners.push([event, wrapped])
      return
    }
    const listeners = this.listeners.get(event) ?? new Set()
    listeners.add(listener)
    this.listeners.set(event, listeners)
  }

  getValue() {
    return this.view.state.doc.toString()
  }

  setValue(value) {
    const text = String(value ?? '')
    if (text === this.getValue()) return
    this.view.dispatch({
      changes: { from: 0, to: this.view.state.doc.length, insert: text },
      selection: EditorSelection.cursor(0),
    })
  }

  getCursor(which = 'head') {
    const selection = this.view.state.selection.main
    const position = which === 'anchor' ? selection.anchor : selection.head
    return cursorFromPosition(this.view.state.doc, position)
  }

  setSelection(anchor, head = anchor, options = {}) {
    const doc = this.view.state.doc
    const anchorPosition = positionFromCursor(doc, anchor)
    const headPosition = positionFromCursor(doc, head)
    const transaction = {
      selection: EditorSelection.range(anchorPosition, headPosition),
    }
    if (options.scroll) {
      transaction.effects = EditorView.scrollIntoView(headPosition)
    }
    this.view.dispatch(transaction)
  }

  setCursor(lineOrCursor, column = 0) {
    const cursor = typeof lineOrCursor === 'object' ? lineOrCursor : { line: lineOrCursor, ch: column }
    this.setSelection(cursor, cursor, { scroll: true })
  }

  getLine(lineNumber) {
    const doc = this.view.state.doc
    if (lineNumber < 0 || lineNumber >= doc.lines) return null
    return doc.line(lineNumber + 1).text
  }

  getLineHandle(lineNumber) {
    const text = this.getLine(lineNumber)
    return text === null ? null : { text }
  }

  lastLine() {
    return this.view.state.doc.lines - 1
  }

  lineCount() {
    return this.view.state.doc.lines
  }

  focus() {
    this.view.focus()
  }

  hasFocus() {
    return this.view.hasFocus
  }

  undo() {
    return undoCommand(this.view)
  }

  redo() {
    return redoCommand(this.view)
  }

  execCommand(command) {
    if (command === 'selectAll') return selectAll(this.view)
    return false
  }

  setTextDirection(direction) {
    this.view.dispatch({
      effects: this.direction.reconfigure(EditorView.contentAttributes.of({ dir: normalizeDirection(direction) })),
    })
  }

  // Source mode contains no rendered image cache, but this method preserves
  // the editor contract shared with Muya.
  invalidateImageCache() {}

  destroy() {
    for (const [event, listener] of this.domListeners) {
      this.view.dom.removeEventListener(event, listener)
    }
    this.listeners.clear()
    this.view.destroy()
  }
}

const createCodeMirror = (parent, config) => new CodeMirrorCompat(parent, config)

export const setCursorAtLastLine = (cm) => {
  const lastLine = cm.lastLine()
  cm.focus()
  cm.setCursor(lastLine, cm.getLine(lastLine)?.length ?? 0)
}

export const isCursorAtFirstLine = (cm) => {
  const { line, ch } = cm.getCursor()
  return line === 0 && ch === 0
}

export const isCursorAtLastLine = (cm) => {
  const { line } = cm.getCursor()
  return line === cm.lastLine()
}

export const isCursorAtBegin = isCursorAtFirstLine

export const onlyHaveOneLine = (cm) => cm.lineCount() === 1

export const isCursorAtEnd = (cm) => {
  const lastLine = cm.lastLine()
  const { line, ch } = cm.getCursor()
  return line === lastLine && ch === (cm.getLine(lastLine)?.length ?? 0)
}

export const getBeginPosition = () => ({
  anchor: { line: 0, ch: 0 },
  head: { line: 0, ch: 0 },
})

export const getEndPosition = (cm) => {
  const line = cm.lastLine()
  const ch = cm.getLine(line)?.length ?? 0
  return { anchor: { line, ch }, head: { line, ch } }
}

export const setCursorAtFirstLine = (cm) => {
  cm.focus()
  cm.setCursor(0, 0)
}

export const setMode = (_editor, text) =>
  text === 'markdown'
    ? Promise.resolve({ name: 'markdown', mode: { mode: 'markdown', mime: 'text/markdown' } })
    : Promise.reject(new Error(`${text || 'Empty mode'} is not a supported source editor mode.`))

export const setTextDirection = (cm, textDirection) => cm.setTextDirection(textDirection)

export default createCodeMirror
