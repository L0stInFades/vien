/**
 * DocumentSession revision helpers (PLAN.md SAFE-001 / §5.2).
 *
 * Pure functions over tab/file state objects so the invariants are unit
 * testable outside Vuex:
 *
 * - `revision` increments monotonically on every edit;
 * - a save request snapshots the revision it serializes;
 * - a save ack only cleans the tab when the acked revision is still the
 *   CURRENT revision — a stale ack (user kept typing) must never clear
 *   dirty state;
 * - `diskVersion` tracks what we believe is on disk; the main process
 *   refuses to overwrite a different on-disk version (SAFE-003 CAS).
 */

/** Session fields merged into every tab/file state. */
export const initialSessionFields = () => ({
  // Monotonic edit counter (content or save-relevant option changes).
  revision: 0,
  // Highest revision known to be safely on disk.
  savedRevision: 0,
  // Disk version {mtimeMs, size} from the last load/save, or null.
  diskVersion: null,
})

/**
 * Record an edit: bump the revision and mark unsaved.
 * Call for every content change and save-relevant option change.
 */
export const markEdited = (tab) => {
  if (typeof tab.revision !== 'number') {
    tab.revision = 0
  }
  tab.revision += 1
  tab.isSaved = false
}

/**
 * Build the save request fields snapshotting the current revision.
 */
export const saveSnapshotFields = (tab) => ({
  revision: typeof tab.revision === 'number' ? tab.revision : 0,
  diskVersion: tab.diskVersion ?? null,
})

/**
 * Apply a save acknowledgement from the main process.
 *
 * @param {object} tab The tab/file state.
 * @param {{savedRevision?: number|null, diskVersion?: object|null}|undefined} ack
 * @returns {'clean'|'stale'|'legacy'} What the ack did:
 *   'clean'  — acked revision is current; tab marked saved;
 *   'stale'  — user edited after the snapshot; tab stays dirty;
 *   'legacy' — no revision info in the ack; tab marked saved (old protocol).
 */
export const applySaveAck = (tab, ack) => {
  if (ack && typeof ack.savedRevision === 'number') {
    tab.savedRevision = Math.max(tab.savedRevision ?? 0, ack.savedRevision)
    if (ack.diskVersion) {
      tab.diskVersion = ack.diskVersion
    }
    if ((tab.revision ?? 0) === ack.savedRevision) {
      tab.isSaved = true
      return 'clean'
    }
    // Stale ack: edits happened after the snapshot was serialized.
    return 'stale'
  }
  // Legacy ack without revision info (or ack for a legacy request).
  if (ack?.diskVersion) {
    tab.diskVersion = ack.diskVersion
  }
  tab.isSaved = true
  return 'legacy'
}
