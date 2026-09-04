import { beforeEach, describe, expect, it, vi } from 'vitest'
import bus from '../../../src/renderer/bus'
import editorModule from '../../../src/renderer/store/editor'

const makeTab = (overrides = {}) => ({
  id: 'tab-1',
  filename: 'note.md',
  pathname: '/tmp/note.md',
  markdown: 'stale',
  isSaved: true,
  revision: 0,
  savedRevision: 0,
  diskVersion: null,
  encoding: { encoding: 'utf8', isBom: false },
  lineEnding: 'lf',
  adjustLineEndingOnSave: false,
  trimTrailingNewline: 3,
  notifications: [],
  ...overrides,
})

describe('editor persistence boundaries', () => {
  let handlers
  let send

  beforeEach(() => {
    handlers = new Map()
    send = vi.fn()
    window.api = {
      ipc: {
        on: vi.fn((channel, handler) => handlers.set(channel, handler)),
        send,
      },
    }
  })

  it('flushes the live source buffer before serializing a save', () => {
    const tab = makeTab()
    const state = { currentFile: tab, tabs: [tab] }
    const rootState = { project: { projectTree: null } }
    const flush = vi.fn(() => {
      tab.markdown = 'fresh from CodeMirror'
      tab.isSaved = false
      tab.revision = 1
    })
    bus.on('flush-active-editor', flush)

    try {
      editorModule.actions.LISTEN_FOR_SAVE({ state, rootState })
      handlers.get('mt::editor-ask-file-save')()
    } finally {
      bus.off('flush-active-editor', flush)
    }

    expect(flush).toHaveBeenCalledOnce()
    expect(send).toHaveBeenCalledWith(
      'mt::response-file-save',
      expect.objectContaining({
        id: 'tab-1',
        markdown: 'fresh from CodeMirror',
        revision: 1,
      }),
    )
  })

  it('ignores content-identical watcher events', () => {
    const tab = makeTab({ markdown: 'already current' })
    const state = { currentFile: tab, tabs: [tab] }
    const commit = vi.fn()

    editorModule.actions.LISTEN_FOR_FILE_CHANGE({
      commit,
      state,
      rootState: { preferences: { autoSave: false } },
    })
    handlers.get('mt::update-file')({
      type: 'change',
      change: {
        pathname: tab.pathname,
        data: { markdown: 'already current' },
      },
    })

    expect(commit).not.toHaveBeenCalled()
  })
})
