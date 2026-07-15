/**
 * RecoveryService contract (PLAN.md SAFE-004): crash-recovery snapshots.
 *
 * The renderer journals dirty documents (debounced, RPO <= 2s) to the
 * recovery directory; snapshots are discarded after a clean save or a
 * deliberate close. Snapshots surviving to the next startup are leftovers
 * from a crashed/killed session and get restored into tabs.
 */
import { s, type Infer } from './schema'

export const RecoveryChannels = {
  snapshot: 'mt::recovery-snapshot',
  discard: 'mt::recovery-discard',
  list: 'mt::recovery-list',
} as const

export const RECOVERY_SCHEMA_VERSION = 1

/** Cap snapshot content at 64 MiB — larger documents skip the journal. */
export const RECOVERY_MAX_CONTENT_LENGTH = 64 * 1024 * 1024

const tabIdSchema = s.string({
  minLength: 1,
  maxLength: 128,
  pattern: /^[a-zA-Z0-9_-]+$/,
  patternName: 'a filename-safe tab id',
})

export const RecoverySnapshotRequestSchema = s.object({
  tabId: tabIdSchema,
  pathname: s.nullable(s.string({ maxLength: 4096 })),
  filename: s.string({ maxLength: 512 }),
  markdown: s.string({ maxLength: RECOVERY_MAX_CONTENT_LENGTH }),
  revision: s.number({ integer: true, min: 0 }),
})
export type RecoverySnapshotRequest = Infer<typeof RecoverySnapshotRequestSchema>

export const RecoveryDiscardRequestSchema = s.object({
  tabId: tabIdSchema,
})
export type RecoveryDiscardRequest = Infer<typeof RecoveryDiscardRequestSchema>

export const RecoveryListRequestSchema = s.object({})
export type RecoveryListRequest = Infer<typeof RecoveryListRequestSchema>

export interface RecoverySnapshotEntry {
  tabId: string
  pathname: string | null
  filename: string
  markdown: string
  revision: number
  savedAt: number
  schemaVersion: number
}
