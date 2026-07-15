/**
 * ContentState block index (PLAN.md CORE-003): getBlock must behave
 * exactly like the old full-tree recursive scan — O(1) is an optimization,
 * never a semantic change. The index self-heals across wholesale tree
 * replacement (history undo/redo) and direct children splices
 * (enterCtrl/updateCtrl move blocks without the primitives).
 */
import { describe, it, expect } from 'vitest'
import ContentState from '../../../src/muya/lib/contentState'
import EventCenter from '../../../src/muya/lib/eventHandler/event'
import { MUYA_DEFAULT_OPTION } from '../../../src/muya/lib/config'
import { deepClone } from '../../../src/muya/lib/utils'

const createMuyaContext = () => {
  const ctx = {}
  ctx.options = Object.assign({}, MUYA_DEFAULT_OPTION, { endOfLine: 'lf' })
  ctx.eventCenter = new EventCenter()
  ctx.contentState = new ContentState(ctx, ctx.options)
  return ctx
}

const SAMPLE = `# Heading

paragraph one

- item a
- item b
  - nested item

> quoted

\`\`\`js
code
\`\`\`

| a | b |
|---|---|
| 1 | 2 |
`

const collectKeys = (blocks, out = []) => {
  for (const block of blocks) {
    out.push(block.key)
    if (block.children.length) {
      collectKeys(block.children, out)
    }
  }
  return out
}

const recursiveScan = (blocks, key) => {
  for (const block of blocks) {
    if (block.key === key) return block
    const found = recursiveScan(block.children, key)
    if (found) return found
  }
  return null
}

describe('ContentState block index (CORE-003)', () => {
  it('returns the identical object as a recursive scan for every key', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    const keys = collectKeys(contentState.blocks)
    expect(keys.length).toBeGreaterThan(10)
    for (const key of keys) {
      expect(contentState.getBlock(key)).toBe(recursiveScan(contentState.blocks, key))
    }
  })

  it('returns null for unknown and empty keys', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    expect(contentState.getBlock('no-such-key')).toBeNull()
    expect(contentState.getBlock(null)).toBeNull()
    expect(contentState.getBlock(undefined)).toBeNull()
    expect(contentState.getBlock('')).toBeNull()
  })

  it('never returns stale objects after history-style wholesale replacement', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    const keys = collectKeys(contentState.blocks)
    // Warm the index with old objects.
    const oldBlock = contentState.getBlock(keys[3])
    expect(oldBlock).not.toBeNull()

    // history.undo/redo replaces the whole tree with deep clones (same keys).
    contentState.blocks = deepClone(contentState.blocks)

    const fresh = contentState.getBlock(keys[3])
    expect(fresh).not.toBeNull()
    expect(fresh.key).toBe(keys[3])
    expect(fresh).not.toBe(oldBlock) // must be the NEW object
    expect(fresh).toBe(recursiveScan(contentState.blocks, keys[3]))
  })

  it('self-heals when children are spliced directly (enterCtrl-style move)', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    // Find a block with at least 2 children to splice from.
    const donor = contentState.blocks.find((b) => b.children.length >= 2)
    expect(donor).toBeTruthy()
    const moved = donor.children[donor.children.length - 1]
    // Warm index.
    expect(contentState.getBlock(moved.key)).toBe(moved)

    // Splice it out directly, bypassing removeBlock (like enterCtrl does).
    donor.children.splice(donor.children.indexOf(moved), 1)

    // Detached block must NOT be returned.
    expect(contentState.getBlock(moved.key)).toBeNull()

    // Re-attach elsewhere via the primitive and it is found again.
    contentState.appendChild(contentState.blocks[0], moved)
    expect(contentState.getBlock(moved.key)).toBe(moved)
  })

  it('reflects removeBlock immediately', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    const target = contentState.blocks[1]
    expect(contentState.getBlock(target.key)).toBe(target)
    contentState.removeBlock(target)
    expect(contentState.getBlock(target.key)).toBeNull()
  })

  it('keeps per-instance render throttles isolated between editors', () => {
    const a = createMuyaContext().contentState
    const b = createMuyaContext().contentState
    a._renderCodeBlockTimer = setTimeout(() => {}, 1000)
    expect(b._renderCodeBlockTimer).toBeNull()
    clearTimeout(a._renderCodeBlockTimer)
  })
})
