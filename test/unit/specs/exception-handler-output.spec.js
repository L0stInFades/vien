// @vitest-environment node

import { afterEach, describe, expect, it, vi } from 'vitest'

vi.mock('electron', () => ({
  app: { getVersion: vi.fn(), isReady: vi.fn() },
  clipboard: { writeText: vi.fn() },
  crashReporter: { start: vi.fn() },
  dialog: { showErrorBox: vi.fn(), showMessageBox: vi.fn() },
  ipcMain: { on: vi.fn() },
}))

vi.mock('electron-log', () => ({ default: { error: vi.fn() } }))
vi.mock('../../../src/main/utils/createGitHubIssue.ts', () => ({ createAndOpenGitHubIssueUrl: vi.fn() }))

const { default: setupExceptionHandler } = await import('../../../src/main/exceptionHandler.js')

describe('main process output error handling', () => {
  afterEach(() => vi.restoreAllMocks())

  it('ignores closed-pipe errors without hiding unrelated output failures', () => {
    let stdoutHandler
    vi.spyOn(process.stdout, 'on').mockImplementation((event, listener) => {
      if (event === 'error') stdoutHandler = listener
      return process.stdout
    })
    vi.spyOn(process.stderr, 'on').mockImplementation(() => process.stderr)
    vi.spyOn(process, 'on').mockImplementation(() => process)

    setupExceptionHandler()

    const eio = Object.assign(new Error('write EIO'), { code: 'EIO' })
    const epipe = Object.assign(new Error('write EPIPE'), { code: 'EPIPE' })
    const enospc = Object.assign(new Error('write ENOSPC'), { code: 'ENOSPC' })
    expect(() => stdoutHandler(eio)).not.toThrow()
    expect(() => stdoutHandler(epipe)).not.toThrow()
    expect(() => stdoutHandler(enospc)).toThrow(enospc)
  })
})
