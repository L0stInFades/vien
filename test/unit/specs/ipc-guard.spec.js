/**
 * Guarded capability IPC registration (ADR-003 / BOUNDARY-001):
 * sender validation + payload validation + structured result envelope.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest'

const handlers = new Map()
const fromWebContentsMock = vi.fn()

vi.mock('electron', () => ({
  ipcMain: {
    handle: (channel, fn) => handlers.set(channel, fn),
    removeHandler: (channel) => handlers.delete(channel),
  },
  BrowserWindow: {
    fromWebContents: (...args) => fromWebContentsMock(...args),
  },
}))

vi.mock('electron-log', () => ({
  default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() },
}))

const { handleCapability, setWindowRegistry } = await import('../../../src/main/security/ipcGuard')
const { s } = await import('../../../src/common/contracts/schema')
const { ErrorCodes, ServiceError } = await import('../../../src/common/contracts/errors')

const topFrameEvent = () => ({
  sender: {},
  senderFrame: { parent: null },
})

describe('handleCapability', () => {
  beforeEach(() => {
    handlers.clear()
    fromWebContentsMock.mockReset()
    fromWebContentsMock.mockReturnValue({ id: 7 })
    setWindowRegistry({ get: (id) => (id === 7 ? { id } : undefined) })
  })

  it('returns ok envelope for valid request from trusted sender', async () => {
    handleCapability('mt::test-echo', s.object({ text: s.string() }), (req) => `echo:${req.text}`)
    const result = await handlers.get('mt::test-echo')(topFrameEvent(), { text: 'hi' })
    expect(result).toEqual({ ok: true, value: 'echo:hi' })
  })

  it('rejects invalid payloads with E_VALIDATION_FAILED', async () => {
    const handler = vi.fn()
    handleCapability('mt::test-strict', s.object({ n: s.number() }), handler)
    const result = await handlers.get('mt::test-strict')(topFrameEvent(), { n: 'NaN' })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.VALIDATION_FAILED)
    expect(handler).not.toHaveBeenCalled()
  })

  it('rejects unknown extra keys in payloads', async () => {
    handleCapability('mt::test-extra', s.object({ a: s.string() }), () => 'never')
    const result = await handlers.get('mt::test-extra')(topFrameEvent(), { a: 'x', evil: true })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.VALIDATION_FAILED)
  })

  it('rejects sub-frame senders', async () => {
    handleCapability('mt::test-frame', s.object({}), () => 'never')
    const event = { sender: {}, senderFrame: { parent: {} } }
    const result = await handlers.get('mt::test-frame')(event, {})
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.SENDER_REJECTED)
  })

  it('rejects senders without a browser window', async () => {
    fromWebContentsMock.mockReturnValue(null)
    handleCapability('mt::test-nowin', s.object({}), () => 'never')
    const result = await handlers.get('mt::test-nowin')(topFrameEvent(), {})
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.SENDER_REJECTED)
  })

  it('rejects windows not tracked by the registry', async () => {
    fromWebContentsMock.mockReturnValue({ id: 999 })
    handleCapability('mt::test-untracked', s.object({}), () => 'never')
    const result = await handlers.get('mt::test-untracked')(topFrameEvent(), {})
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.SENDER_REJECTED)
  })

  it('normalizes handler exceptions into structured errors', async () => {
    handleCapability('mt::test-throw', s.object({}), () => {
      throw Object.assign(new Error('missing'), { code: 'ENOENT' })
    })
    const result = await handlers.get('mt::test-throw')(topFrameEvent(), {})
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.NOT_FOUND)
  })

  it('passes ServiceError codes through to the envelope', async () => {
    handleCapability('mt::test-conflict', s.object({}), () => {
      throw new ServiceError(ErrorCodes.CONFLICT, 'disk changed')
    })
    const result = await handlers.get('mt::test-conflict')(topFrameEvent(), {})
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.CONFLICT)
    expect(result.error.message).toBe('disk changed')
  })
})
