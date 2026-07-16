/**
 * Import/export performance baseline (PLAN.md QUALITY-001 / §8.6).
 *
 * Measures Muya's markdown import (markdownToState) and export
 * (ExportMarkdown.generate) on deterministic 100KB and 1MB documents,
 * writes perf-results.json for nightly artifacts, and asserts GENEROUS
 * regression ceilings — these are alarms for order-of-magnitude
 * regressions, not the §2.2 product budgets (which are measured in the
 * real app via Chromium traces, not jsdom).
 *
 * Results carry commit/platform metadata per §8.6 (no user content).
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execSync } from 'node:child_process'
import { performance } from 'node:perf_hooks'
import { describe, it, expect } from 'vitest'
import ContentState from '../../src/muya/lib/contentState'
import EventCenter from '../../src/muya/lib/eventHandler/event'
import ExportMarkdown from '../../src/muya/lib/utils/exportMarkdown'
import { MUYA_DEFAULT_OPTION } from '../../src/muya/lib/config'

const RESULTS_PATH = path.join(__dirname, '../../perf-results.json')

// Deterministic document generator (mirrors test/corpus/tools/generate-large.mjs).
const mulberry32 = (seed) => () => {
  seed |= 0
  seed = (seed + 0x6d2b79f5) | 0
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

const WORDS =
  'markdown editor calm writing document paragraph heading emphasis table list quote code fence link image footnote math diagram workspace search theme export'.split(
    ' ',
  )

const buildDocument = (targetBytes, seed) => {
  const rand = mulberry32(seed)
  const pick = (arr) => arr[Math.floor(rand() * arr.length)]
  const sentence = (n) => Array.from({ length: n }, () => pick(WORDS)).join(' ')
  const parts = ['# Perf document\n']
  let bytes = parts[0].length
  let section = 0
  while (bytes < targetBytes) {
    const kind = Math.floor(rand() * 6)
    let chunk
    switch (kind) {
      case 0:
        chunk = `\n## Section ${++section}: ${sentence(3)}\n`
        break
      case 1:
        chunk = `\n${sentence(30)}.\n`
        break
      case 2:
        chunk = `\n- ${sentence(6)}\n- ${sentence(5)}\n- **${sentence(2)}**\n`
        break
      case 3:
        chunk = `\n> ${sentence(14)}\n`
        break
      case 4:
        chunk = `\n\`\`\`js\nconst v${section} = ${Math.floor(rand() * 100000)}\n\`\`\`\n`
        break
      default:
        chunk = `\n| a | b |\n|---|---|\n| ${sentence(2)} | ${Math.floor(rand() * 1000)} |\n`
        break
    }
    parts.push(chunk)
    bytes += Buffer.byteLength(chunk)
  }
  return parts.join('')
}

const createMuyaContext = () => {
  const ctx = {}
  ctx.options = Object.assign({}, MUYA_DEFAULT_OPTION, { endOfLine: 'lf' })
  ctx.eventCenter = new EventCenter()
  ctx.contentState = new ContentState(ctx, ctx.options)
  return ctx
}

const median = (values) => {
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]
}

const bench = (label, sizeBytes, seed, rounds) => {
  const markdown = buildDocument(sizeBytes, seed)
  const importTimes = []
  const exportTimes = []
  const lookupTimes = []

  for (let round = 0; round < rounds; round++) {
    const ctx = createMuyaContext()
    const t0 = performance.now()
    ctx.contentState.importMarkdown(markdown)
    const t1 = performance.now()
    importTimes.push(t1 - t0)

    // Warm block-index lookups over every block key (CORE-003 hot path).
    const keys = []
    const collect = (blocks) => {
      for (const b of blocks) {
        keys.push(b.key)
        if (b.children.length) collect(b.children)
      }
    }
    collect(ctx.contentState.blocks)
    const t2 = performance.now()
    for (const key of keys) {
      ctx.contentState.getBlock(key)
    }
    const t3 = performance.now()
    lookupTimes.push(t3 - t2)

    const t4 = performance.now()
    new ExportMarkdown(ctx.contentState.getBlocks()).generate()
    const t5 = performance.now()
    exportTimes.push(t5 - t4)
  }

  return {
    label,
    bytes: Buffer.byteLength(buildDocument(sizeBytes, seed)),
    rounds,
    importMsMedian: Math.round(median(importTimes) * 10) / 10,
    exportMsMedian: Math.round(median(exportTimes) * 10) / 10,
    blockLookupAllMsMedian: Math.round(median(lookupTimes) * 10) / 10,
  }
}

describe('import/export performance baseline', () => {
  it('measures 100KB and 1MB documents and writes perf-results.json', () => {
    const results = [bench('100KB', 100 * 1024, 202, 5), bench('1MB', 1024 * 1024, 303, 3)]

    let commit = 'unknown'
    try {
      commit = execSync('git rev-parse --short HEAD', { cwd: path.join(__dirname, '../..') })
        .toString()
        .trim()
    } catch (_error) {}

    const doc = {
      generatedAt: new Date().toISOString(),
      commit,
      node: process.version,
      platform: `${os.platform()}-${os.arch()}`,
      cpus: os.cpus()?.[0]?.model ?? 'unknown',
      note: 'jsdom-based engine baseline; product budgets (PLAN.md 2.2) are measured in the real app.',
      results,
    }
    fs.writeFileSync(RESULTS_PATH, `${JSON.stringify(doc, null, 2)}\n`)
    // eslint-disable-next-line no-console
    console.table(results)

    // Order-of-magnitude alarms (>10x headroom over current numbers).
    const oneHundredKb = results[0]
    const oneMb = results[1]
    expect(oneHundredKb.importMsMedian).toBeLessThan(10_000)
    expect(oneHundredKb.exportMsMedian).toBeLessThan(5_000)
    expect(oneMb.importMsMedian).toBeLessThan(60_000)
    expect(oneMb.exportMsMedian).toBeLessThan(30_000)
    expect(oneMb.blockLookupAllMsMedian).toBeLessThan(10_000)
  })
})
