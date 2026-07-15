/**
 * SearchService integration tests (PLAN.md SEARCH-001): real ripgrep
 * binary from vscode-ripgrep against a real temp workspace, streaming
 * batches to a mocked webContents, with cancellation and path scoping.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest'

const handlers = new Map()
const fromWebContentsMock = vi.fn()

vi.mock('electron', () => ({
  ipcMain: {
    handle: (channel, fn) => handlers.set(channel, fn),
    removeHandler: (channel) => handlers.delete(channel),
  },
  BrowserWindow: { fromWebContents: (...args) => fromWebContentsMock(...args) },
}))
vi.mock('electron-log', () => ({ default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }))

const { setWindowRegistry } = await import('../../../src/main/security/ipcGuard')
const { SearchService } = await import('../../../src/main/services/search')
const { SearchChannels } = await import('../../../src/common/contracts/search')
const { ErrorCodes } = await import('../../../src/common/contracts/errors')
const {
  RipgrepJsonParser,
  prepareGlobs,
  processUnicodeMatch,
} = await import('../../../src/main/services/search/ripgrepParser')

let sandbox
let workspaceRoot
let sentEvents

const WINDOW_ID = 31

const makeWindow = () => ({
  id: WINDOW_ID,
  webContents: {
    isDestroyed: () => false,
    send: (channel, payload) => {
      sentEvents.push({ channel, payload })
    },
  },
})

const event = () => ({ sender: {}, senderFrame: { parent: null } })
const invoke = (channel, payload) => handlers.get(channel)(event(), payload)

const waitForDone = async (searchId, timeoutMs = 10000) => {
  const startedAt = Date.now()
  for (;;) {
    const done = sentEvents.find(
      (e) => e.channel === SearchChannels.done && e.payload.searchId === searchId,
    )
    if (done) {
      return done.payload
    }
    if (Date.now() - startedAt > timeoutMs) {
      throw new Error(`timed out waiting for search ${searchId}`)
    }
    await new Promise((resolve) => setTimeout(resolve, 25))
  }
}

const batchesFor = (searchId) =>
  sentEvents.filter((e) => e.channel === SearchChannels.resultBatch && e.payload.searchId === searchId)

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-search-service-'))
  workspaceRoot = path.join(sandbox, 'workspace')
  fs.mkdirSync(path.join(workspaceRoot, 'nested'), { recursive: true })
  fs.writeFileSync(path.join(workspaceRoot, 'alpha.md'), '# Alpha\n\nfindme in alpha\n')
  fs.writeFileSync(path.join(workspaceRoot, 'nested/beta.md'), 'nothing here\nfindme in beta\nfindme twice\n')
  fs.writeFileSync(path.join(workspaceRoot, 'gamma.txt'), 'findme in gamma but txt\n')
  fs.writeFileSync(path.join(sandbox, 'outside.md'), 'findme outside\n')
  fs.writeFileSync(path.join(workspaceRoot, 'unicode.md'), '中文 findme 之后\n')

  sentEvents = []
  fromWebContentsMock.mockImplementation(() => makeWindow())
  setWindowRegistry({ get: (id) => (id === WINDOW_ID ? { id } : undefined) })

  const windowManager = {
    get: (id) => (id === WINDOW_ID ? { openedRootDirectory: workspaceRoot, openedFiles: [] } : undefined),
  }
  new SearchService(windowManager)
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

describe('SearchService content search', () => {
  it('streams per-file results with atom-style match structure', async () => {
    const searchId = 'content-test-1'
    const start = await invoke(SearchChannels.contentStart, {
      searchId,
      rootPath: workspaceRoot,
      pattern: 'findme',
      options: { inclusions: ['*.md'] },
    })
    expect(start).toEqual({ ok: true, value: { searchId } })

    const done = await waitForDone(searchId)
    expect(done.ok).toBe(true)
    expect(done.pathCount).toBe(3) // alpha.md, nested/beta.md, unicode.md — not gamma.txt

    const results = batchesFor(searchId).flatMap((b) => b.payload.results ?? [])
    const byFile = Object.fromEntries(results.map((r) => [path.basename(r.filePath), r]))

    expect(byFile['alpha.md'].matches).toHaveLength(1)
    expect(byFile['alpha.md'].matches[0].matchText).toBe('findme')
    expect(byFile['alpha.md'].matches[0].lineText).toBe('findme in alpha')
    expect(byFile['alpha.md'].matches[0].range).toEqual([
      [2, 0],
      [2, 6],
    ])

    expect(byFile['beta.md'].matches).toHaveLength(2)
    expect(byFile['gamma.txt']).toBeUndefined()
  })

  it('converts byte offsets to character positions for CJK lines', async () => {
    const searchId = 'content-unicode'
    await invoke(SearchChannels.contentStart, {
      searchId,
      rootPath: workspaceRoot,
      pattern: 'findme',
      options: { inclusions: ['unicode.md'] },
    })
    await waitForDone(searchId)
    const results = batchesFor(searchId).flatMap((b) => b.payload.results ?? [])
    const match = results[0].matches[0]
    // '中文 ' is 3 characters (not 7 bytes) before the match.
    expect(match.range).toEqual([
      [0, 3],
      [0, 9],
    ])
  })

  it('denies search roots outside the workspace scope', async () => {
    const result = await invoke(SearchChannels.contentStart, {
      searchId: 'content-escape',
      rootPath: sandbox,
      pattern: 'findme',
    })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.PATH_DENIED)
  })

  it('reports invalid regex as a structured failure event', async () => {
    const searchId = 'content-bad-regex'
    const start = await invoke(SearchChannels.contentStart, {
      searchId,
      rootPath: workspaceRoot,
      pattern: '([unclosed',
      options: { isRegexp: true },
    })
    expect(start.ok).toBe(true)
    const done = await waitForDone(searchId)
    expect(done.ok).toBe(false)
    expect(done.error.code).toBe(ErrorCodes.IO_ERROR)
    expect(done.error.message.length).toBeGreaterThan(0)
  })
})

describe('SearchService file search', () => {
  it('streams matching file paths', async () => {
    const searchId = 'files-test-1'
    await invoke(SearchChannels.filesStart, {
      searchId,
      rootPath: workspaceRoot,
      options: { inclusions: ['*.md'] },
    })
    const done = await waitForDone(searchId)
    expect(done.ok).toBe(true)

    const paths = batchesFor(searchId).flatMap((b) => b.payload.paths ?? [])
    const names = paths.map((p) => path.basename(p)).sort()
    expect(names).toEqual(['alpha.md', 'beta.md', 'unicode.md'])
  })
})

describe('SearchService cancellation', () => {
  it('kills a running search and completes with ok', async () => {
    const searchId = 'cancel-test'
    await invoke(SearchChannels.filesStart, {
      searchId,
      rootPath: workspaceRoot,
    })
    const cancelResult = await invoke(SearchChannels.cancel, { searchId })
    expect(cancelResult.ok).toBe(true)
    const done = await waitForDone(searchId)
    expect(done.ok).toBe(true)
  })

  it('cannot cancel a search from a different window', async () => {
    const searchId = 'cancel-foreign'
    await invoke(SearchChannels.filesStart, { searchId, rootPath: workspaceRoot })

    // Same channel, different (untracked-for-this-search) window id.
    fromWebContentsMock.mockImplementationOnce(() => ({ ...makeWindow(), id: 999 }))
    setWindowRegistry({ get: (id) => ({ id }) }) // pretend both windows are tracked
    const foreign = await invoke(SearchChannels.cancel, { searchId })
    expect(foreign.ok).toBe(true)
    expect(foreign.value.cancelled).toBe(false) // not owned by window 999

    setWindowRegistry({ get: (id) => (id === WINDOW_ID ? { id } : undefined) })
    await invoke(SearchChannels.cancel, { searchId })
    await waitForDone(searchId)
  })
})

describe('RipgrepJsonParser unit behavior', () => {
  it('parses begin/match/end sequences split across chunks', () => {
    const results = []
    const parser = new RipgrepJsonParser((r) => results.push(r))
    const lines = [
      JSON.stringify({ type: 'begin', data: { path: { text: '/x/a.md' } } }),
      JSON.stringify({
        type: 'match',
        data: {
          path: { text: '/x/a.md' },
          lines: { text: 'hello world\n' },
          line_number: 3,
          submatches: [{ match: { text: 'world' }, start: 6, end: 11 }],
        },
      }),
      JSON.stringify({ type: 'end', data: { path: { text: '/x/a.md' } } }),
    ].join('\n')

    // Feed in two arbitrary chunks to exercise buffering.
    parser.push(lines.slice(0, 40))
    parser.push(`${lines.slice(40)}\n`)

    expect(results).toHaveLength(1)
    expect(results[0].filePath).toBe('/x/a.md')
    expect(results[0].matches[0].matchText).toBe('world')
    expect(results[0].matches[0].range).toEqual([
      [2, 6],
      [2, 11],
    ])
  })

  it('tolerates garbage lines without dropping the search', () => {
    const results = []
    const parser = new RipgrepJsonParser((r) => results.push(r))
    parser.push('not json at all\n')
    parser.push(`${JSON.stringify({ type: 'begin', data: { path: { text: '/x/b.md' } } })}\n`)
    parser.push(`${JSON.stringify({ type: 'end', data: { path: { text: '/x/b.md' } } })}\n`)
    expect(results).toHaveLength(1)
  })

  it('prepareGlobs expands directory-style patterns', () => {
    expect(prepareGlobs(['src/'], '/proj')).toEqual(['**/src', '**/src/**'])
    expect(prepareGlobs(['proj'], '/proj')).toEqual(['**/*'])
    expect(prepareGlobs(['*.md'], '/proj')).toEqual(['**/*.md', '**/*.md/**'])
  })

  it('processUnicodeMatch converts byte offsets to character offsets', () => {
    const match = {
      path: { text: '/x' },
      lines: { text: '中文 findme\n' },
      line_number: 1,
      submatches: [{ match: { text: 'findme' }, start: 7, end: 13 }],
    }
    processUnicodeMatch(match)
    expect(match.submatches[0].start).toBe(3)
    expect(match.submatches[0].end).toBe(9)
  })
})
