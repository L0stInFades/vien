/**
 * DocumentSession revision invariants (PLAN.md SAFE-001, Phase 2 exit
 * criterion: "保存 N 后编辑 N+1，N 的 ack 永远不能清掉 dirty").
 */
import { describe, it, expect } from 'vitest'
import {
  initialSessionFields,
  markEdited,
  saveSnapshotFields,
  applySaveAck,
} from '../../../src/renderer/store/documentSession'

const makeTab = () => ({ isSaved: true, ...initialSessionFields() })

describe('DocumentSession revision state machine', () => {
  it('markEdited bumps revision monotonically and dirties the tab', () => {
    const tab = makeTab()
    markEdited(tab)
    expect(tab.revision).toBe(1)
    expect(tab.isSaved).toBe(false)
    markEdited(tab)
    markEdited(tab)
    expect(tab.revision).toBe(3)
  })

  it('ack for the current revision cleans the tab', () => {
    const tab = makeTab()
    markEdited(tab) // revision 1
    const snapshot = saveSnapshotFields(tab)
    const outcome = applySaveAck(tab, {
      savedRevision: snapshot.revision,
      diskVersion: { mtimeMs: 111, size: 10 },
    })
    expect(outcome).toBe('clean')
    expect(tab.isSaved).toBe(true)
    expect(tab.savedRevision).toBe(1)
    expect(tab.diskVersion).toEqual({ mtimeMs: 111, size: 10 })
  })

  it('THE P0 INVARIANT: a stale ack never clears dirty state', () => {
    const tab = makeTab()
    markEdited(tab) // revision 1
    const snapshot = saveSnapshotFields(tab) // save starts serializing rev 1

    markEdited(tab) // user keeps typing: revision 2

    const outcome = applySaveAck(tab, {
      savedRevision: snapshot.revision, // ack for rev 1 arrives late
      diskVersion: { mtimeMs: 222, size: 20 },
    })
    expect(outcome).toBe('stale')
    expect(tab.isSaved).toBe(false) // rev 2 is NOT on disk
    expect(tab.savedRevision).toBe(1)
    // diskVersion still updates — rev 1 IS what's on disk now.
    expect(tab.diskVersion).toEqual({ mtimeMs: 222, size: 20 })
  })

  it('out-of-order acks never regress savedRevision', () => {
    const tab = makeTab()
    markEdited(tab) // 1
    markEdited(tab) // 2
    applySaveAck(tab, { savedRevision: 2, diskVersion: { mtimeMs: 2, size: 2 } })
    expect(tab.isSaved).toBe(true)
    // A very late ack for revision 1 arrives afterwards.
    const outcome = applySaveAck(tab, { savedRevision: 1, diskVersion: { mtimeMs: 1, size: 1 } })
    expect(outcome).toBe('stale')
    expect(tab.savedRevision).toBe(2)
  })

  it('legacy acks without revision info keep the old behavior', () => {
    const tab = makeTab()
    markEdited(tab)
    const outcome = applySaveAck(tab, undefined)
    expect(outcome).toBe('legacy')
    expect(tab.isSaved).toBe(true)
  })

  it('saveSnapshotFields carries revision and diskVersion', () => {
    const tab = makeTab()
    tab.diskVersion = { mtimeMs: 5, size: 50 }
    markEdited(tab)
    expect(saveSnapshotFields(tab)).toEqual({ revision: 1, diskVersion: { mtimeMs: 5, size: 50 } })
  })

  it('tolerates tabs created before the session fields existed', () => {
    const tab = { isSaved: true } // legacy tab shape
    markEdited(tab)
    expect(tab.revision).toBe(1)
    expect(saveSnapshotFields(tab)).toEqual({ revision: 1, diskVersion: null })
  })
})
