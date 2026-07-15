/**
 * Deterministic generator for large performance-corpus documents
 * (PLAN.md §8.2: 1 KB / 100 KB / 1 MB / 10 MB). Files are NOT committed —
 * they are reproducible from this script (seeded PRNG, no Date/Math.random):
 *
 *   node test/corpus/tools/generate-large.mjs [outDir]
 *
 * Default output: test/corpus/generated/ (gitignored).
 */
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const outDir = process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..', 'generated')
mkdirSync(outDir, { recursive: true })

// Mulberry32 — deterministic PRNG.
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
const CJK = '编辑器文档段落标题强调表格列表引用代码围栏链接图片脚注数学图表工作区搜索主题导出'.split('')

const buildDocument = (targetBytes, seed) => {
  const rand = mulberry32(seed)
  const pick = (arr) => arr[Math.floor(rand() * arr.length)]
  const sentence = (n) => Array.from({ length: n }, () => pick(WORDS)).join(' ')
  const cjkRun = (n) => Array.from({ length: n }, () => pick(CJK)).join('')

  const parts = ['# Generated performance document\n']
  let bytes = parts[0].length
  let section = 0
  while (bytes < targetBytes) {
    let chunk
    const kind = Math.floor(rand() * 8)
    switch (kind) {
      case 0:
        chunk = `\n## Section ${++section}: ${sentence(3)}\n`
        break
      case 1:
        chunk = `\n${sentence(25)}. ${cjkRun(12)}。${sentence(15)}.\n`
        break
      case 2:
        chunk = `\n- ${sentence(6)}\n- ${sentence(5)}\n- **${sentence(2)}** and *${sentence(3)}*\n`
        break
      case 3:
        chunk = `\n> ${sentence(14)}\n> ${cjkRun(20)}\n`
        break
      case 4:
        chunk = `\n\`\`\`js\nconst v${section} = ${Math.floor(rand() * 100000)}\nfunction f${section}() { return '${pick(WORDS)}' }\n\`\`\`\n`
        break
      case 5:
        chunk = `\n| ${pick(WORDS)} | ${pick(WORDS)} | value |\n|---|---|---|\n| ${sentence(2)} | ${cjkRun(4)} | ${Math.floor(rand() * 1000)} |\n`
        break
      case 6:
        chunk = `\n[${sentence(2)}](https://example.com/${pick(WORDS)}) and \`${pick(WORDS)}()\` inline.\n`
        break
      default:
        chunk = `\n${sentence(40)}.\n`
        break
    }
    parts.push(chunk)
    bytes += Buffer.byteLength(chunk)
  }
  return parts.join('')
}

const targets = [
  ['perf-1kb.md', 1024, 101],
  ['perf-100kb.md', 100 * 1024, 202],
  ['perf-1mb.md', 1024 * 1024, 303],
  ['perf-10mb.md', 10 * 1024 * 1024, 404],
]

for (const [name, size, seed] of targets) {
  const doc = buildDocument(size, seed)
  writeFileSync(join(outDir, name), doc)
  console.log(`wrote ${name} (${Buffer.byteLength(doc)} bytes)`)
}
