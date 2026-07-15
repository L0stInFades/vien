/**
 * One-off generator for byte-sensitive corpus fixtures (CRLF, BOM, trailing
 * whitespace, zero-width characters). Run from the repo root:
 *
 *   node test/corpus/tools/build-byte-fixtures.mjs
 *
 * The generated files are committed; this script only exists so the exact
 * bytes are reproducible and reviewable. test/corpus/.gitattributes marks
 * the corpus as `-text` so git never rewrites line endings.
 */
import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..', 'lossless')

const write = (rel, content) => {
  writeFileSync(join(root, rel), Buffer.from(content, 'utf8'))
  console.log(`wrote ${rel}`)
}

// --- whitespace-eol ---------------------------------------------------------

write(
  'whitespace-eol/crlf.md',
  '# CRLF document\r\n\r\nEvery line in this file ends with CRLF.\r\n\r\n- item one\r\n- item two\r\n',
)

write(
  'whitespace-eol/mixed-eol.md',
  '# Mixed EOL\n\nThis line ends with LF.\nThis line ends with CRLF.\r\nBack to LF.\n\r\nCRLF blank line above.\n',
)

write('whitespace-eol/bom.md', '﻿# BOM document\n\nThis file starts with a UTF-8 BOM.\n')

write('whitespace-eol/no-trailing-newline.md', '# No trailing newline\n\nThe file ends right after this period.')

write('whitespace-eol/multiple-trailing-newlines.md', '# Multiple trailing newlines\n\nThree blank lines follow.\n\n\n\n')

write(
  'whitespace-eol/trailing-spaces.md',
  '# Trailing spaces\n\nThis line has two trailing spaces (hard break)  \nnext line.\n\nThis line has one trailing space \nand continues.\n',
)

write(
  'whitespace-eol/tabs.md',
  '# Tabs\n\n\tindented code block via tab\n\n- list\n\twith tab continuation\n\n|\tcol\t|\tcol2\t|\n|---|---|\n|\ta\t|\tb\t|\n',
)

// --- unicode ----------------------------------------------------------------

write(
  'unicode/zero-width.md',
  '# Zero-width characters\n\nzero​width​space between words\n\nzero‌width‍non-joiner and joiner\n\nword﻿joiner (BOM char mid-text)\n',
)

write(
  'unicode/rtl-bidi.md',
  '# RTL and bidi\n\nעברית: שלום עולם\n\nالعربية: مرحبا بالعالم\n\nMixed: The word שלום means hello, and مرحبا too.\n\nRLM‏ and LRM‎ marks embedded.\n',
)

write(
  'unicode/combining.md',
  '# Combining marks\n\nñ (n + combining tilde) vs ñ (precomposed)\n\náéí combining acutes\n\nZalgo-lite: h̵e̶l̷l̸o̴\n',
)

console.log('done')
