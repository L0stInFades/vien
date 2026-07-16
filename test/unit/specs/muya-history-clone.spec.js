/**
 * History snapshot clone parity (PLAN.md CORE-004 first slice).
 *
 * cloneHistoryValue replaces JSON.parse(JSON.stringify(...)) for history
 * snapshots. Its output must be indistinguishable from the JSON round-trip
 * for real document trees — this parity is what makes the swap safe.
 */
import { describe, it, expect } from 'vitest'
import ContentState from '../../../src/muya/lib/contentState'
import EventCenter from '../../../src/muya/lib/eventHandler/event'
import { MUYA_DEFAULT_OPTION } from '../../../src/muya/lib/config'
import { cloneHistoryValue, deepClone } from '../../../src/muya/lib/utils'

const createMuyaContext = () => {
  const ctx = {}
  ctx.options = Object.assign({}, MUYA_DEFAULT_OPTION, { endOfLine: 'lf' })
  ctx.eventCenter = new EventCenter()
  ctx.contentState = new ContentState(ctx, ctx.options)
  return ctx
}

const SAMPLE = `# Heading ##

paragraph with **bold** and \`code\`

- item a
- item b
  - nested

1. one
3. three

> quote

\`\`\`js
const x = 1
\`\`\`

| a | b |
|---|---|
| 1 | 2 |

$$
x^2
$$
`

describe('history snapshot clone parity (CORE-004)', () => {
  it('matches JSON round-trip byte-for-byte on a real document tree', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    const state = {
      blocks: contentState.blocks,
      renderRange: contentState.renderRange,
      cursor: { start: { key: 'k1', offset: 3 }, end: { key: 'k1', offset: 3 } },
    }
    const fast = cloneHistoryValue(state)
    const json = deepClone(state)
    expect(JSON.stringify(fast)).toBe(JSON.stringify(json))
  })

  it('produces fully detached copies (no shared references)', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown(SAMPLE)
    const clone = cloneHistoryValue({ blocks: contentState.blocks })
    expect(clone.blocks).not.toBe(contentState.blocks)
    expect(clone.blocks[0]).not.toBe(contentState.blocks[0])
    clone.blocks[0].text = 'mutated'
    expect(contentState.blocks[0].text).not.toBe('mutated')
  })

  it('mirrors JSON semantics for undefined, functions and null', () => {
    const input = {
      keep: 1,
      dropUndefined: undefined,
      dropFn: () => {},
      nul: null,
      arr: [1, undefined, () => {}, null, { nested: undefined, ok: 'yes' }],
    }
    expect(JSON.stringify(cloneHistoryValue(input))).toBe(JSON.stringify(deepClone(input)))
  })

  it('undo/redo through History restores identical content', () => {
    const { contentState } = createMuyaContext()
    contentState.importMarkdown('# One\n\nfirst\n')
    const cursor = { start: { key: contentState.blocks[0].key, offset: 0 }, end: { key: contentState.blocks[0].key, offset: 0 } }
    contentState.history.push({ blocks: contentState.blocks, renderRange: [null, null], cursor })

    const snapshotA = JSON.stringify(contentState.blocks)
    contentState.importMarkdown('# Two\n\nsecond version\n')
    contentState.history.push({ blocks: contentState.blocks, renderRange: [null, null], cursor })

    // Stub render — History.undo calls contentState.render().
    contentState.render = () => {}
    contentState.history.undo()
    expect(JSON.stringify(contentState.blocks)).toBe(snapshotA)
  })
})
