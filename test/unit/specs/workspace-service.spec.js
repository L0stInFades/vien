/**
 * WorkspaceService integration tests (PLAN.md WORKSPACE-001): real temp
 * filesystem through the full guard + path policy + service stack, with
 * electron mocked at the module boundary.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, it, expect, vi, beforeEach, beforeAll, afterAll } from 'vitest'

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
const { WorkspaceService } = await import('../../../src/main/services/workspace')
const { WorkspaceChannels } = await import('../../../src/common/contracts/workspace')
const { ErrorCodes } = await import('../../../src/common/contracts/errors')

let sandbox
let workspaceRoot

const WINDOW_ID = 7
const event = () => ({ sender: {}, senderFrame: { parent: null } })
const invoke = (channel, payload) => handlers.get(channel)(event(), payload)

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-workspace-service-'))
  workspaceRoot = path.join(sandbox, 'workspace')
  fs.mkdirSync(workspaceRoot, { recursive: true })

  fromWebContentsMock.mockReturnValue({ id: WINDOW_ID })
  setWindowRegistry({ get: (id) => (id === WINDOW_ID ? { id } : undefined) })

  const windowManager = {
    get: (id) =>
      id === WINDOW_ID ? { openedRootDirectory: workspaceRoot, openedFiles: [] } : undefined,
  }
  new WorkspaceService(windowManager)
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

beforeEach(() => {
  fromWebContentsMock.mockReturnValue({ id: WINDOW_ID })
})

describe('WorkspaceService.create', () => {
  it('creates a file on the real filesystem', async () => {
    const target = path.join(workspaceRoot, 'notes/new-file.md')
    const result = await invoke(WorkspaceChannels.create, { pathname: target, kind: 'file' })
    expect(result.ok).toBe(true)
    expect(fs.existsSync(target)).toBe(true)
    expect(fs.readFileSync(target, 'utf8')).toBe('')
  })

  it('creates a directory', async () => {
    const target = path.join(workspaceRoot, 'new-dir/nested')
    const result = await invoke(WorkspaceChannels.create, { pathname: target, kind: 'directory' })
    expect(result.ok).toBe(true)
    expect(fs.statSync(target).isDirectory()).toBe(true)
  })

  it('never truncates an existing file (legacy outputFile bug)', async () => {
    const target = path.join(workspaceRoot, 'existing.md')
    fs.writeFileSync(target, 'precious content')
    const result = await invoke(WorkspaceChannels.create, { pathname: target, kind: 'file' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.ALREADY_EXISTS)
    expect(fs.readFileSync(target, 'utf8')).toBe('precious content')
  })

  it('denies paths outside the workspace', async () => {
    const outside = path.join(sandbox, 'escape.md')
    const result = await invoke(WorkspaceChannels.create, { pathname: outside, kind: 'file' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.PATH_DENIED)
    expect(fs.existsSync(outside)).toBe(false)
  })

  it('denies .. traversal escapes', async () => {
    const sneaky = path.join(workspaceRoot, '..', 'traversal.md')
    const result = await invoke(WorkspaceChannels.create, { pathname: sneaky, kind: 'file' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.PATH_DENIED)
  })
})

describe('WorkspaceService.paste', () => {
  it('copies files without clobbering existing destinations', async () => {
    const src = path.join(workspaceRoot, 'copy-src.md')
    const dest = path.join(workspaceRoot, 'copy-dest.md')
    fs.writeFileSync(src, 'copy me')

    const okResult = await invoke(WorkspaceChannels.paste, { src, dest, kind: 'copy' })
    expect(okResult.ok).toBe(true)
    expect(fs.readFileSync(dest, 'utf8')).toBe('copy me')

    fs.writeFileSync(dest, 'already here')
    const conflict = await invoke(WorkspaceChannels.paste, { src, dest, kind: 'copy' })
    expect(conflict.ok).toBe(false)
    expect(fs.readFileSync(dest, 'utf8')).toBe('already here')
  })

  it('moves files with kind=cut', async () => {
    const src = path.join(workspaceRoot, 'cut-src.md')
    const dest = path.join(workspaceRoot, 'cut-dest.md')
    fs.writeFileSync(src, 'move me')
    const result = await invoke(WorkspaceChannels.paste, { src, dest, kind: 'cut' })
    expect(result.ok).toBe(true)
    expect(fs.existsSync(src)).toBe(false)
    expect(fs.readFileSync(dest, 'utf8')).toBe('move me')
  })

  it('rejects same source and destination', async () => {
    const src = path.join(workspaceRoot, 'same.md')
    fs.writeFileSync(src, 'x')
    const result = await invoke(WorkspaceChannels.paste, { src, dest: src, kind: 'copy' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.VALIDATION_FAILED)
  })
})

describe('WorkspaceService.rename', () => {
  it('renames within the workspace', async () => {
    const src = path.join(workspaceRoot, 'old-name.md')
    const dest = path.join(workspaceRoot, 'new-name.md')
    fs.writeFileSync(src, 'content')
    const result = await invoke(WorkspaceChannels.rename, { src, dest })
    expect(result.ok).toBe(true)
    expect(fs.existsSync(src)).toBe(false)
    expect(fs.readFileSync(dest, 'utf8')).toBe('content')
  })

  it('refuses to overwrite an existing destination', async () => {
    const src = path.join(workspaceRoot, 'rn-src.md')
    const dest = path.join(workspaceRoot, 'rn-dest.md')
    fs.writeFileSync(src, 'source')
    fs.writeFileSync(dest, 'destination untouched')
    const result = await invoke(WorkspaceChannels.rename, { src, dest })
    expect(result.ok).toBe(false)
    expect(fs.readFileSync(dest, 'utf8')).toBe('destination untouched')
  })
})

describe('WorkspaceService.isExecutable', () => {
  it('reports executables and non-executables', async () => {
    const script = path.join(workspaceRoot, 'tool.sh')
    fs.writeFileSync(script, '#!/bin/sh\necho hi\n')
    fs.chmodSync(script, 0o755)
    const yes = await invoke(WorkspaceChannels.isExecutable, { pathname: script })
    expect(yes).toEqual({ ok: true, value: { executable: true } })

    const plain = path.join(workspaceRoot, 'plain.txt')
    fs.writeFileSync(plain, 'not a script')
    fs.chmodSync(plain, 0o644)
    const no = await invoke(WorkspaceChannels.isExecutable, { pathname: plain })
    expect(no).toEqual({ ok: true, value: { executable: false } })

    const missing = await invoke(WorkspaceChannels.isExecutable, {
      pathname: path.join(workspaceRoot, 'missing'),
    })
    expect(missing).toEqual({ ok: true, value: { executable: false } })
  })
})
