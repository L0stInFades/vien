/**
 * Contract schema validators (ADR-003 / BOUNDARY-001).
 */
import { describe, it, expect } from 'vitest'
import { s, formatIssues } from '../../../src/common/contracts/schema'

describe('contract schema validators', () => {
  it('string enforces bounds and pattern', () => {
    expect(s.string().validate('hello').ok).toBe(true)
    expect(s.string().validate(42).ok).toBe(false)
    expect(s.string({ minLength: 2 }).validate('a').ok).toBe(false)
    expect(s.string({ maxLength: 3 }).validate('abcd').ok).toBe(false)
    expect(s.string({ pattern: /^[a-z]+$/ }).validate('abc').ok).toBe(true)
    expect(s.string({ pattern: /^[a-z]+$/ }).validate('ABC').ok).toBe(false)
  })

  it('number rejects NaN/Infinity and enforces integer bounds', () => {
    expect(s.number().validate(1.5).ok).toBe(true)
    expect(s.number().validate(Number.NaN).ok).toBe(false)
    expect(s.number().validate(Number.POSITIVE_INFINITY).ok).toBe(false)
    expect(s.number({ integer: true }).validate(1.5).ok).toBe(false)
    expect(s.number({ min: 0, max: 8 }).validate(9).ok).toBe(false)
  })

  it('literal matches exact values only', () => {
    const schema = s.literal('copy', 'cut')
    expect(schema.validate('copy').ok).toBe(true)
    expect(schema.validate('paste').ok).toBe(false)
  })

  it('object rejects unknown keys (no smuggling past the boundary)', () => {
    const schema = s.object({ a: s.string() })
    expect(schema.validate({ a: 'x' }).ok).toBe(true)
    const result = schema.validate({ a: 'x', extra: 1 })
    expect(result.ok).toBe(false)
    expect(formatIssues(result.issues)).toContain('unknown key')
  })

  it('object reports nested paths', () => {
    const schema = s.object({ outer: s.object({ inner: s.number() }) })
    const result = schema.validate({ outer: { inner: 'not a number' } })
    expect(result.ok).toBe(false)
    expect(result.issues[0].path).toBe('$.outer.inner')
  })

  it('optional allows undefined but validates present values', () => {
    const schema = s.object({ flag: s.optional(s.boolean()) })
    expect(schema.validate({}).ok).toBe(true)
    expect(schema.validate({ flag: true }).ok).toBe(true)
    expect(schema.validate({ flag: 'yes' }).ok).toBe(false)
  })

  it('array enforces item schema and maxItems', () => {
    const schema = s.array(s.string(), { maxItems: 2 })
    expect(schema.validate(['a', 'b']).ok).toBe(true)
    expect(schema.validate(['a', 'b', 'c']).ok).toBe(false)
    expect(schema.validate(['a', 1]).ok).toBe(false)
  })

  it('union accepts any variant', () => {
    const schema = s.union(s.string(), s.number())
    expect(schema.validate('x').ok).toBe(true)
    expect(schema.validate(3).ok).toBe(true)
    expect(schema.validate(true).ok).toBe(false)
  })

  it('absolutePath rejects relative paths and null bytes', () => {
    expect(s.absolutePath().validate('/tmp/file.md').ok).toBe(true)
    expect(s.absolutePath().validate('C:\\docs\\file.md').ok).toBe(true)
    expect(s.absolutePath().validate('relative/path.md').ok).toBe(false)
    expect(s.absolutePath().validate('/tmp/\0evil').ok).toBe(false)
    expect(s.absolutePath().validate('').ok).toBe(false)
  })

  it('bytes accepts Uint8Array within limits', () => {
    expect(s.bytes().validate(new Uint8Array([1, 2, 3])).ok).toBe(true)
    expect(s.bytes({ maxBytes: 2 }).validate(new Uint8Array([1, 2, 3])).ok).toBe(false)
    expect(s.bytes().validate('binary string').ok).toBe(false)
  })
})
