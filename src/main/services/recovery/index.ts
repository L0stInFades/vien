/**
 * RecoveryService (PLAN.md SAFE-004): crash-recovery snapshots for dirty
 * documents. Snapshots are atomic full-document JSON files under
 * <userData>/recovery; they exist only while a document is dirty and are
 * discarded after a clean save or deliberate close. Files found at startup
 * are leftovers from a crashed session.
 *
 * A corrupt snapshot never blocks anything: unreadable files are skipped
 * (and reported in the listing as corrupt-count) rather than thrown.
 */
import path from 'node:path'
import fsPromises from 'node:fs/promises'
import log from 'electron-log'
import {
  RECOVERY_SCHEMA_VERSION,
  RecoveryChannels,
  RecoveryDiscardRequestSchema,
  RecoveryListRequestSchema,
  RecoverySnapshotRequestSchema,
  type RecoverySnapshotEntry,
} from 'common/contracts/recovery'
import { handleCapability } from '../../security/ipcGuard'
import { atomicWriteFile } from '../../filesystem/atomicWrite'

interface RecoveryPaths {
  userDataPath: string
}

export class RecoveryService {
  private readonly _recoveryDir: string

  constructor(paths: RecoveryPaths) {
    this._recoveryDir = path.join(paths.userDataPath, 'recovery')
    this._registerHandlers()
  }

  get recoveryDir(): string {
    return this._recoveryDir
  }

  private _snapshotPath(tabId: string): string {
    // tabId is schema-validated to a filename-safe alphabet.
    return path.join(this._recoveryDir, `tab-${tabId}.json`)
  }

  private _registerHandlers(): void {
    handleCapability(RecoveryChannels.snapshot, RecoverySnapshotRequestSchema, async (request) => {
      const entry: RecoverySnapshotEntry = {
        schemaVersion: RECOVERY_SCHEMA_VERSION,
        tabId: request.tabId,
        pathname: request.pathname,
        filename: request.filename,
        markdown: request.markdown,
        revision: request.revision,
        savedAt: Date.now(),
      }
      await fsPromises.mkdir(this._recoveryDir, { recursive: true })
      await atomicWriteFile(this._snapshotPath(request.tabId), Buffer.from(JSON.stringify(entry), 'utf8'))
      return { savedAt: entry.savedAt }
    })

    handleCapability(RecoveryChannels.discard, RecoveryDiscardRequestSchema, async (request) => {
      await fsPromises.unlink(this._snapshotPath(request.tabId)).catch(() => {})
      return { discarded: true }
    })

    handleCapability(RecoveryChannels.list, RecoveryListRequestSchema, async () => {
      return this.listSnapshots()
    })
  }

  /**
   * Enumerate leftover snapshots. Corrupt files are counted but never
   * thrown — recovery data must not block startup (PLAN.md Phase 2 exit).
   */
  async listSnapshots(): Promise<{ snapshots: RecoverySnapshotEntry[]; corrupt: number }> {
    let names: string[] = []
    try {
      names = await fsPromises.readdir(this._recoveryDir)
    } catch (_error) {
      return { snapshots: [], corrupt: 0 }
    }

    const snapshots: RecoverySnapshotEntry[] = []
    let corrupt = 0
    for (const name of names) {
      if (!/^tab-[a-zA-Z0-9_-]+\.json$/.test(name)) {
        continue
      }
      try {
        const raw = await fsPromises.readFile(path.join(this._recoveryDir, name), 'utf8')
        const parsed = JSON.parse(raw) as RecoverySnapshotEntry
        if (
          typeof parsed.markdown !== 'string' ||
          typeof parsed.tabId !== 'string' ||
          typeof parsed.schemaVersion !== 'number'
        ) {
          corrupt += 1
          continue
        }
        if (parsed.schemaVersion > RECOVERY_SCHEMA_VERSION) {
          // Snapshot from a newer app version — skip rather than misread.
          log.warn(`[recovery] Skipping snapshot ${name} with newer schema v${parsed.schemaVersion}.`)
          corrupt += 1
          continue
        }
        snapshots.push(parsed)
      } catch (error) {
        corrupt += 1
        log.warn(`[recovery] Unreadable snapshot ${name}: ${(error as Error).message}`)
      }
    }
    snapshots.sort((a, b) => a.savedAt - b.savedAt)
    return { snapshots, corrupt }
  }
}
