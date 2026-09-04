import { describe, expect, it } from 'vitest'
import { tokenizer } from '../../../src/muya/lib/parser'

const collectTypes = (tokens, output = []) => {
  for (const token of tokens) {
    output.push(token.type)
    if (Array.isArray(token.children)) collectTypes(token.children, output)
  }
  return output
}

describe('strong emphasis with CJK boundaries', () => {
  const examples = [
    '例子例子**"加粗"**例子例子',
    '日本語**(強調)**日本語',
    '한국어**[강조]**한국어',
    '𠀀𠀁**"加粗"**𠀀𠀁',
    'before **"normal"** after',
    'before**normal**after',
    '中文**加粗**中文',
  ]

  for (const markdown of examples) {
    it(`recognizes strong in: ${markdown}`, () => {
      expect(collectTypes(tokenizer(markdown))).toContain('strong')
    })
  }
})
