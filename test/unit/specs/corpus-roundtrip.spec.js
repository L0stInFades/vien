/**
 * Lossless corpus round-trip baseline (PLAN.md BASE-003 / §8.2).
 *
 * Replicates the full "open → save without editing" pipeline:
 *   load side  (src/main/filesystem/markdown.js loadMarkdownFile):
 *     BOM strip → EOL detect → normalize to LF → trailing-newline mode detect
 *   editor     (src/muya): ContentState.importMarkdown → ExportMarkdown
 *   save side  (src/renderer/store/editor.js + writeMarkdownFile):
 *     adjustTrailingNewlines → convert EOL back → re-add BOM
 * and asserts byte identity against test/corpus/lossless fixtures.
 *
 * Two-way ratchet: fixtures listed in test/corpus/known-lossy.json are
 * EXPECTED to fail identity today (Muya normalizes their source — the P0
 * risk PLAN.md documents). If one of them becomes lossless, this test fails
 * and tells you to remove it from the manifest so progress is locked in.
 * If a fixture NOT in the manifest regresses, this test fails loudly.
 *
 * Regenerate the manifest after intentional engine changes:
 *   UPDATE_LOSSY_MANIFEST=1 pnpm run unit -- corpus-roundtrip
 *
 * The Phase 3 exit criterion (PLAN.md §5.5) is an EMPTY manifest.
 */
import fs from 'node:fs'
import path from 'node:path'
import { describe, it, expect, afterAll } from 'vitest'
import ContentState from '../../../src/muya/lib/contentState'
import EventCenter from '../../../src/muya/lib/eventHandler/event'
import ExportMarkdown from '../../../src/muya/lib/utils/exportMarkdown'
import { MUYA_DEFAULT_OPTION } from '../../../src/muya/lib/config'

const CORPUS_ROOT = path.join(__dirname, '../../corpus/lossless')
const MANIFEST_PATH = path.join(__dirname, '../../corpus/known-lossy.json')
const UPDATE_MODE = !!process.env.UPDATE_LOSSY_MANIFEST

// Mirrors src/main/config.js
const LINE_ENDING_REG = /(?:\r\n|\n)/g
const LF_LINE_ENDING_REG = /(?:[^\r]\n)|(?:^\n$)/
const CRLF_LINE_ENDING_REG = /\r\n/

const collectFixtures = (dir, prefix = '') => {
  const out = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const rel = prefix ? `${prefix}/${entry.name}` : entry.name
    if (entry.isDirectory()) {
      out.push(...collectFixtures(path.join(dir, entry.name), rel))
    } else if (entry.name.endsWith('.md')) {
      out.push(rel)
    }
  }
  return out
}

const createMuyaContext = (options) => {
  const ctx = {}
  ctx.options = Object.assign({}, MUYA_DEFAULT_OPTION, options)
  ctx.eventCenter = new EventCenter()
  ctx.contentState = new ContentState(ctx, ctx.options)
  return ctx
}

// Mirrors trimTrailingNewlines/adjustTrailingNewlines in src/renderer/store/editor.js.
const trimTrailingNewlines = (text) => text.replace(/[\r\n]+$/, '')
const adjustTrailingNewlines = (markdown, mode) => {
  if (!markdown) {
    return ''
  }
  switch (mode) {
    case 0:
      return trimTrailingNewlines(markdown)
    case 1: {
      const lastIndex = markdown.length - 1
      if (markdown[lastIndex] === '\n') {
        if (markdown.length === 1) {
          return ''
        } else if (markdown[lastIndex - 1] !== '\n') {
          return markdown
        }
      }
      markdown = trimTrailingNewlines(markdown)
      if (markdown.length === 0) {
        return ''
      }
      return `${markdown}\n`
    }
    default:
      return markdown
  }
}

/**
 * Full open→save-without-editing pipeline for a UTF-8 buffer.
 * Mirrors loadMarkdownFile (main), Muya import/export, and the save path.
 */
const roundtripBuffer = (buffer) => {
  // ---- load side ----
  const hasBom = buffer.length >= 3 && buffer[0] === 0xef && buffer[1] === 0xbb && buffer[2] === 0xbf
  let markdown = buffer.toString('utf8')
  if (hasBom && markdown.charCodeAt(0) === 0xfeff) {
    markdown = markdown.slice(1)
  }

  const isLf = LF_LINE_ENDING_REG.test(markdown)
  const isCrlf = CRLF_LINE_ENDING_REG.test(markdown)
  const isMixedLineEndings = isLf && isCrlf
  const isUnknownEnding = !isLf && !isCrlf
  let lineEnding = 'lf' // default preferredEol
  if (isLf && !isCrlf) {
    lineEnding = 'lf'
  } else if (isCrlf && !isLf) {
    lineEnding = 'crlf'
  }
  let adjustLineEndingOnSave = false
  if (isMixedLineEndings || isUnknownEnding || lineEnding !== 'lf') {
    adjustLineEndingOnSave = lineEnding !== 'lf'
    markdown = markdown.replace(LINE_ENDING_REG, '\n')
  }

  let trimMode = 2
  if (!markdown) {
    trimMode = 3
  } else {
    const lastIndex = markdown.length - 1
    if (lastIndex >= 1 && markdown[lastIndex] === '\n' && markdown[lastIndex - 1] === '\n') {
      trimMode = 2
    } else if (markdown[lastIndex] === '\n') {
      trimMode = 1
    } else {
      trimMode = 0
    }
  }

  // ---- editor (import → export, no edits) ----
  const ctx = createMuyaContext({ endOfLine: 'lf' })
  ctx.contentState.importMarkdown(markdown)
  let output = new ExportMarkdown(ctx.contentState.getBlocks()).generate()

  // ---- save side ----
  output = adjustTrailingNewlines(output, trimMode)
  if (adjustLineEndingOnSave) {
    output = output.replace(LINE_ENDING_REG, '\r\n')
  }
  if (hasBom) {
    output = `﻿${output}`
  }
  return Buffer.from(output, 'utf8')
}

const firstDifference = (a, b) => {
  const max = Math.min(a.length, b.length)
  for (let i = 0; i < max; i++) {
    if (a[i] !== b[i]) return i
  }
  return a.length === b.length ? -1 : max
}

const contextSnippet = (buffer, offset) => {
  const from = Math.max(0, offset - 40)
  const to = Math.min(buffer.length, offset + 40)
  return JSON.stringify(buffer.toString('utf8', from, to))
}

const fixtures = collectFixtures(CORPUS_ROOT)
const manifest = fs.existsSync(MANIFEST_PATH) ? JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8')) : { lossy: [] }
const knownLossy = new Set(manifest.lossy.map((entry) => entry.fixture))
const observed = []

describe('lossless corpus: open → save-without-editing byte identity', () => {
  expect(fixtures.length).toBeGreaterThan(20)

  for (const fixture of fixtures) {
    it(fixture, () => {
      const input = fs.readFileSync(path.join(CORPUS_ROOT, fixture))
      let identical = false
      let detail = ''
      try {
        const output = roundtripBuffer(input)
        identical = input.equals(output)
        if (!identical) {
          const offset = firstDifference(input, output)
          detail =
            `first byte difference at offset ${offset}\n` +
            `  input:  ${contextSnippet(input, offset)}\n` +
            `  output: ${contextSnippet(output, offset)}`
        }
      } catch (error) {
        identical = false
        detail = `roundtrip threw: ${error.message}`
      }

      observed.push({ fixture, identical, detail })

      if (UPDATE_MODE) {
        return // collected in afterAll
      }

      if (knownLossy.has(fixture)) {
        expect(
          identical,
          `${fixture} is listed in known-lossy.json but round-trips byte-identical now.\n` +
            'Progress! Remove it from test/corpus/known-lossy.json to lock this in.',
        ).toBe(false)
      } else {
        expect(identical, `${fixture} REGRESSED to lossy round-trip.\n${detail}`).toBe(true)
      }
    })
  }

  afterAll(() => {
    if (!UPDATE_MODE) {
      return
    }
    const lossy = observed
      .filter((o) => !o.identical)
      .map((o) => ({ fixture: o.fixture, note: o.detail.split('\n')[0] }))
      .sort((a, b) => a.fixture.localeCompare(b.fixture))
    const doc = {
      $comment:
        'Fixtures that do NOT round-trip byte-identical through open→save today. ' +
        'Phase 3 exit criterion (PLAN.md §5.5) is an empty list. ' +
        'Regenerate with UPDATE_LOSSY_MANIFEST=1 pnpm run unit -- corpus-roundtrip',
      generatedBy: 'test/unit/specs/corpus-roundtrip.spec.js',
      lossy,
    }
    fs.writeFileSync(MANIFEST_PATH, `${JSON.stringify(doc, null, 2)}\n`)
    // eslint-disable-next-line no-console
    console.log(`known-lossy manifest updated: ${lossy.length}/${observed.length} fixtures lossy`)
  })
})
