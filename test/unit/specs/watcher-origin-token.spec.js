/**
 * Watcher self-save origin tokens (PLAN.md WATCH-001): the watcher
 * distinguishes our own saves from external modifications by comparing
 * exact disk versions instead of guessing with time windows.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest'

vi.mock('electron-log', () => ({ default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }))
vi.mock('ced', () => ({ default: () => 'utf8' }))
// chokidar is imported by the module but not exercised in these tests.
vi.mock('chokidar', () => ({ default: { watch: vi.fn() } }))

const { default: Watcher, SELF_SAVE_TOKEN_TTL } = await import('../../../src/main/filesystem/watcher')
const { atomicWriteFile, getDiskVersion } = await import('../../../src/main/filesystem/atomicWrite')

let sandbox

const WINDOW_ID = 41

const makeWatcher = () => {
  const preferences = {
    getItem: () => false,
    getPreferredEol: () => 'lf',
    getAll: () => ({ autoGuessEncoding: false, trimTrailingNewline: 2 }),
  }
  return new Watcher(preferences)
}

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-watch-origin-'))
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

describe('watcher self-save origin tokens (WATCH-001)', () => {
  it('suppresses events whose disk version matches our own save', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'self-save.md')
    const version = await atomicWriteFile(target, Buffer.from('saved by vien\n'))

    watcher.expectSelfSave(WINDOW_ID, target, version)
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(true)
    // Idempotent: watchers can emit several events for one write.
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(true)
  })

  it('delivers events when the disk differs from our last write (external change)', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'external.md')
    const version = await atomicWriteFile(target, Buffer.from('ours\n'))
    watcher.expectSelfSave(WINDOW_ID, target, version)

    // External program rewrites the file with different content/size.
    fs.writeFileSync(target, 'external content that is longer\n')

    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(false)
    // Token is consumed — further events for this path stay visible.
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(false)
  })

  it('scopes tokens to the window that saved', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'scoped.md')
    const version = await atomicWriteFile(target, Buffer.from('scoped\n'))
    watcher.expectSelfSave(WINDOW_ID, target, version)

    expect(await watcher._shouldIgnoreEvent(999, target, 'file', true)).toBe(false)
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(true)
  })

  it('treats a vanished file as an external change', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'vanish.md')
    const version = await atomicWriteFile(target, Buffer.from('soon gone\n'))
    watcher.expectSelfSave(WINDOW_ID, target, version)
    fs.unlinkSync(target)
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(false)
  })

  it('expires tokens after the TTL', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'ttl.md')
    const version = await atomicWriteFile(target, Buffer.from('ttl\n'))
    watcher.expectSelfSave(WINDOW_ID, target, version)

    // Age the token artificially.
    const key = `${WINDOW_ID}|${target}`
    const token = watcher._selfSaveTokens.get(key)
    token.registeredAt = Date.now() - SELF_SAVE_TOKEN_TTL - 1000

    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(false)
    expect(watcher._selfSaveTokens.has(key)).toBe(false)
  })

  it('a newer save replaces the token (latest version wins)', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'latest.md')
    const v1 = await atomicWriteFile(target, Buffer.from('v1\n'))
    watcher.expectSelfSave(WINDOW_ID, target, v1)
    const v2 = await atomicWriteFile(target, Buffer.from('v2 longer\n'))
    watcher.expectSelfSave(WINDOW_ID, target, v2)

    // Disk is at v2 = our latest write — suppressed.
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(true)
  })

  it('falls back to the legacy time window when no version is provided', async () => {
    const watcher = makeWatcher()
    const target = path.join(sandbox, 'legacy.md')
    await atomicWriteFile(target, Buffer.from('legacy\n'))
    watcher.expectSelfSave(WINDOW_ID, target, null)
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, target, 'file', true)).toBe(true)
  })

  it('directory events are never suppressed', async () => {
    const watcher = makeWatcher()
    expect(await watcher._shouldIgnoreEvent(WINDOW_ID, '/anywhere', 'dir', true)).toBe(false)
  })
})
