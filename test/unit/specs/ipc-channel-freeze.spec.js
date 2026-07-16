/**
 * Legacy IPC channel freeze (ADR-003 first-stage lockdown).
 *
 * The generic window.api.ipc bridge accepts exactly the channels in
 * src/common/ipcChannels.ts. This test pins the SIZE and shape of those
 * lists so any growth is a deliberate, reviewed change:
 *
 * - New capabilities must use narrow schema-validated methods
 *   (src/common/contracts + ipcGuard), never new legacy channels.
 * - Shrinking the lists (migrating a channel to a capability) requires
 *   updating the counts here — visible progress.
 */
import { describe, it, expect } from 'vitest'
import {
  LEGACY_SEND_CHANNELS,
  LEGACY_RECEIVE_CHANNELS,
  LEGACY_INVOKE_CHANNELS,
} from '../../../src/common/ipcChannels'

// Frozen baseline (2026-07-16). DO NOT increase — decrease as channels
// migrate to capability contracts.
const FROZEN_SEND_COUNT = 50
const FROZEN_RECEIVE_COUNT = 60
const FROZEN_INVOKE_COUNT = 18

describe('legacy IPC channel freeze', () => {
  it('send list never grows', () => {
    expect(LEGACY_SEND_CHANNELS.length).toBeLessThanOrEqual(FROZEN_SEND_COUNT)
  })

  it('receive list never grows', () => {
    expect(LEGACY_RECEIVE_CHANNELS.length).toBeLessThanOrEqual(FROZEN_RECEIVE_COUNT)
  })

  it('invoke list never grows', () => {
    expect(LEGACY_INVOKE_CHANNELS.length).toBeLessThanOrEqual(FROZEN_INVOKE_COUNT)
  })

  it('lists contain no duplicates', () => {
    for (const list of [LEGACY_SEND_CHANNELS, LEGACY_RECEIVE_CHANNELS, LEGACY_INVOKE_CHANNELS]) {
      expect(new Set(list).size).toBe(list.length)
    }
  })

  it('every channel follows the namespace convention', () => {
    for (const list of [LEGACY_SEND_CHANNELS, LEGACY_RECEIVE_CHANNELS, LEGACY_INVOKE_CHANNELS]) {
      for (const channel of list) {
        expect(channel).toMatch(/^(mt|settings)::[a-zA-Z0-9-_$:]+$/)
      }
    }
  })

  it('no dynamic/prefix channels exist (the escape hatch stays dead)', () => {
    for (const list of [LEGACY_SEND_CHANNELS, LEGACY_RECEIVE_CHANNELS, LEGACY_INVOKE_CHANNELS]) {
      for (const channel of list) {
        expect(channel).not.toContain('response-of-image-path')
      }
    }
  })
})
