/**
 * ExportThemeService integration tests (PLAN.md EXPORT-001 first slice).
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
const { ExportThemeService } = await import('../../../src/main/services/exportThemes')
const { ExportChannels } = await import('../../../src/common/contracts/export')
const { ErrorCodes } = await import('../../../src/common/contracts/errors')

let sandbox

const WINDOW_ID = 21
const event = () => ({ sender: {}, senderFrame: { parent: null } })
const invoke = (channel, payload) => handlers.get(channel)(event(), payload)

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-export-theme-'))
  const themeDir = path.join(sandbox, 'themes/export')
  fs.mkdirSync(themeDir, { recursive: true })
  fs.writeFileSync(path.join(themeDir, 'labelled.css'), '/* My Fancy Theme */\nbody { color: red; }\n')
  fs.writeFileSync(path.join(themeDir, 'plain.css'), 'body { color: blue; }\n')
  fs.writeFileSync(path.join(themeDir, 'notes.txt'), 'not a theme\n')

  fromWebContentsMock.mockReturnValue({ id: WINDOW_ID })
  setWindowRegistry({ get: (id) => (id === WINDOW_ID ? { id } : undefined) })
  new ExportThemeService({ userDataPath: sandbox })
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

describe('ExportThemeService', () => {
  it('lists css themes with first-line comment labels', async () => {
    const result = await invoke(ExportChannels.listThemes, {})
    expect(result.ok).toBe(true)
    const byName = Object.fromEntries(result.value.themes.map((t) => [t.name, t.label]))
    expect(byName['labelled.css']).toBe('My Fancy Theme')
    expect(byName['plain.css']).toBe('plain.css')
    expect(byName['notes.txt']).toBeUndefined()
  })

  it('reads a theme by bare filename', async () => {
    const result = await invoke(ExportChannels.readTheme, { name: 'plain.css' })
    expect(result.ok).toBe(true)
    expect(result.value.css).toContain('color: blue')
  })

  it('returns E_NOT_FOUND for unknown themes', async () => {
    const result = await invoke(ExportChannels.readTheme, { name: 'missing.css' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.NOT_FOUND)
  })

  it('rejects path traversal in theme names at the schema layer', async () => {
    const result = await invoke(ExportChannels.readTheme, { name: '../../../etc/passwd.css' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.VALIDATION_FAILED)
  })

  it('returns an empty list when the theme directory does not exist', async () => {
    new ExportThemeService({ userDataPath: path.join(sandbox, 'nonexistent') })
    const result = await invoke(ExportChannels.listThemes, {})
    expect(result.ok).toBe(true)
    expect(result.value.themes).toEqual([])
  })
})
