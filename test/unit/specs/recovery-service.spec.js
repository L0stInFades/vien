/**
 * RecoveryService integration tests (PLAN.md SAFE-004): crash-recovery
 * snapshots on a real temp filesystem through the guarded channels.
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
const { RecoveryService } = await import('../../../src/main/services/recovery')
const { RecoveryChannels } = await import('../../../src/common/contracts/recovery')

let sandbox
let service

const WINDOW_ID = 51
const event = () => ({ sender: {}, senderFrame: { parent: null } })
const invoke = (channel, payload) => handlers.get(channel)(event(), payload)

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-recovery-'))
  fromWebContentsMock.mockReturnValue({ id: WINDOW_ID })
  setWindowRegistry({ get: (id) => (id === WINDOW_ID ? { id } : undefined) })
  service = new RecoveryService({ userDataPath: sandbox })
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

const snapshotRequest = (tabId, markdown = '# recovered\n') => ({
  tabId,
  pathname: null,
  filename: 'Untitled-1',
  markdown,
  revision: 3,
})

describe('RecoveryService (SAFE-004)', () => {
  it('persists snapshots and lists them back', async () => {
    const write = await invoke(RecoveryChannels.snapshot, snapshotRequest('tab-a', 'unsaved words\n'))
    expect(write.ok).toBe(true)

    const list = await invoke(RecoveryChannels.list, {})
    expect(list.ok).toBe(true)
    const entry = list.value.snapshots.find((s) => s.tabId === 'tab-a')
    expect(entry.markdown).toBe('unsaved words\n')
    expect(entry.revision).toBe(3)
    expect(entry.schemaVersion).toBe(1)
  })

  it('overwrites the snapshot for the same tab (latest content wins)', async () => {
    await invoke(RecoveryChannels.snapshot, snapshotRequest('tab-b', 'v1\n'))
    await invoke(RecoveryChannels.snapshot, snapshotRequest('tab-b', 'v2 newer\n'))
    const list = await invoke(RecoveryChannels.list, {})
    const entries = list.value.snapshots.filter((s) => s.tabId === 'tab-b')
    expect(entries).toHaveLength(1)
    expect(entries[0].markdown).toBe('v2 newer\n')
  })

  it('discard removes the snapshot and is idempotent', async () => {
    await invoke(RecoveryChannels.snapshot, snapshotRequest('tab-c'))
    const first = await invoke(RecoveryChannels.discard, { tabId: 'tab-c' })
    expect(first.ok).toBe(true)
    const second = await invoke(RecoveryChannels.discard, { tabId: 'tab-c' })
    expect(second.ok).toBe(true)
    const list = await invoke(RecoveryChannels.list, {})
    expect(list.value.snapshots.find((s) => s.tabId === 'tab-c')).toBeUndefined()
  })

  it('rejects filename-unsafe tab ids at the schema layer', async () => {
    const result = await invoke(RecoveryChannels.snapshot, snapshotRequest('../escape'))
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe('E_VALIDATION_FAILED')
  })

  it('corrupt snapshots are counted, never thrown, and never block listing', async () => {
    const dir = service.recoveryDir
    fs.writeFileSync(path.join(dir, 'tab-corrupt1.json'), '{ not json')
    fs.writeFileSync(path.join(dir, 'tab-corrupt2.json'), JSON.stringify({ nope: true }))
    fs.writeFileSync(path.join(dir, 'unrelated.txt'), 'ignored')

    await invoke(RecoveryChannels.snapshot, snapshotRequest('tab-good', 'still fine\n'))
    const list = await invoke(RecoveryChannels.list, {})
    expect(list.ok).toBe(true)
    expect(list.value.corrupt).toBeGreaterThanOrEqual(2)
    expect(list.value.snapshots.some((s) => s.tabId === 'tab-good')).toBe(true)
  })

  it('skips snapshots written by a newer schema version', async () => {
    const dir = service.recoveryDir
    fs.writeFileSync(
      path.join(dir, 'tab-future.json'),
      JSON.stringify({ schemaVersion: 999, tabId: 'tab-future', markdown: 'from the future', savedAt: 1 }),
    )
    const list = await invoke(RecoveryChannels.list, {})
    expect(list.value.snapshots.find((s) => s.tabId === 'tab-future')).toBeUndefined()
  })

  it('returns an empty listing when the recovery dir does not exist', async () => {
    const fresh = new RecoveryService({ userDataPath: path.join(sandbox, 'never-created') })
    const result = await fresh.listSnapshots()
    expect(result).toEqual({ snapshots: [], corrupt: 0 })
  })
})
