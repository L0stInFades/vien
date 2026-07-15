/**
 * Minimal runtime schema validation for IPC payloads (ADR-003).
 *
 * Deliberately dependency-free: IPC payloads are small structured values,
 * and the supply-chain budget for the security boundary is zero. The
 * combinator surface mirrors what we need — if requirements outgrow this,
 * swap the implementation, keep the schema-first principle.
 */

export interface ValidationIssue {
  path: string
  message: string
}

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; issues: ValidationIssue[] }

export interface Schema<T> {
  validate(value: unknown, path?: string): ValidationResult<T>
}

// Infer the TypeScript type from a schema.
export type Infer<S> = S extends Schema<infer T> ? T : never

const fail = (path: string, message: string): { ok: false; issues: ValidationIssue[] } => ({
  ok: false,
  issues: [{ path, message }],
})

const ok = <T>(value: T): { ok: true; value: T } => ({ ok: true, value })

export interface StringOptions {
  minLength?: number
  maxLength?: number
  pattern?: RegExp
  patternName?: string
}

const string = (options: StringOptions = {}): Schema<string> => ({
  validate(value, path = '$') {
    if (typeof value !== 'string') {
      return fail(path, `expected string, got ${typeof value}`)
    }
    const { minLength, maxLength = 65536, pattern, patternName } = options
    if (minLength !== undefined && value.length < minLength) {
      return fail(path, `string shorter than ${minLength}`)
    }
    if (value.length > maxLength) {
      return fail(path, `string longer than ${maxLength}`)
    }
    if (pattern && !pattern.test(value)) {
      return fail(path, `string does not match ${patternName ?? pattern.source}`)
    }
    return ok(value)
  },
})

export interface NumberOptions {
  min?: number
  max?: number
  integer?: boolean
}

const number = (options: NumberOptions = {}): Schema<number> => ({
  validate(value, path = '$') {
    if (typeof value !== 'number' || Number.isNaN(value) || !Number.isFinite(value)) {
      return fail(path, `expected finite number, got ${typeof value}`)
    }
    if (options.integer && !Number.isInteger(value)) {
      return fail(path, 'expected integer')
    }
    if (options.min !== undefined && value < options.min) {
      return fail(path, `number below ${options.min}`)
    }
    if (options.max !== undefined && value > options.max) {
      return fail(path, `number above ${options.max}`)
    }
    return ok(value)
  },
})

const boolean = (): Schema<boolean> => ({
  validate(value, path = '$') {
    if (typeof value !== 'boolean') {
      return fail(path, `expected boolean, got ${typeof value}`)
    }
    return ok(value)
  },
})

const literal = <const V extends readonly (string | number | boolean)[]>(...values: V): Schema<V[number]> => ({
  validate(value, path = '$') {
    for (const candidate of values) {
      if (value === candidate) {
        return ok(value as V[number])
      }
    }
    return fail(path, `expected one of ${values.map((v) => JSON.stringify(v)).join(', ')}`)
  },
})

const optional = <T>(schema: Schema<T>): Schema<T | undefined> => ({
  validate(value, path = '$') {
    if (value === undefined) {
      return ok(undefined)
    }
    return schema.validate(value, path)
  },
})

const nullable = <T>(schema: Schema<T>): Schema<T | null> => ({
  validate(value, path = '$') {
    if (value === null) {
      return ok(null)
    }
    return schema.validate(value, path)
  },
})

type ObjectShape = Record<string, Schema<unknown>>
// Keys whose schema accepts undefined (s.optional) become optional keys in
// the output type, so `{}` is assignable when every field is optional.
type UndefinedKeys<S extends ObjectShape> = {
  [K in keyof S]: undefined extends Infer<S[K]> ? K : never
}[keyof S]
type ObjectOutput<S extends ObjectShape> = { [K in Exclude<keyof S, UndefinedKeys<S>>]: Infer<S[K]> } & {
  [K in UndefinedKeys<S>]?: Infer<S[K]>
}

const object = <S extends ObjectShape>(shape: S): Schema<ObjectOutput<S>> => ({
  validate(value, path = '$') {
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return fail(path, `expected object, got ${Array.isArray(value) ? 'array' : typeof value}`)
    }
    const input = value as Record<string, unknown>
    const output: Record<string, unknown> = {}
    const issues: ValidationIssue[] = []
    for (const key of Object.keys(shape)) {
      const result = shape[key].validate(input[key], `${path}.${key}`)
      if (result.ok) {
        if (result.value !== undefined) {
          output[key] = result.value
        }
      } else {
        issues.push(...result.issues)
      }
    }
    // Reject unknown keys: prevents smuggling extra data through the boundary.
    for (const key of Object.keys(input)) {
      if (!(key in shape)) {
        issues.push({ path: `${path}.${key}`, message: 'unknown key' })
      }
    }
    if (issues.length > 0) {
      return { ok: false, issues }
    }
    return ok(output as ObjectOutput<S>)
  },
})

export interface ArrayOptions {
  maxItems?: number
}

const array = <T>(item: Schema<T>, options: ArrayOptions = {}): Schema<T[]> => ({
  validate(value, path = '$') {
    if (!Array.isArray(value)) {
      return fail(path, `expected array, got ${typeof value}`)
    }
    const { maxItems = 4096 } = options
    if (value.length > maxItems) {
      return fail(path, `array longer than ${maxItems}`)
    }
    const output: T[] = []
    const issues: ValidationIssue[] = []
    for (let i = 0; i < value.length; i++) {
      const result = item.validate(value[i], `${path}[${i}]`)
      if (result.ok) {
        output.push(result.value)
      } else {
        issues.push(...result.issues)
      }
    }
    if (issues.length > 0) {
      return { ok: false, issues }
    }
    return ok(output)
  },
})

const union = <T extends readonly Schema<unknown>[]>(...schemas: T): Schema<Infer<T[number]>> => ({
  validate(value, path = '$') {
    const issues: ValidationIssue[] = []
    for (const schema of schemas) {
      const result = schema.validate(value, path)
      if (result.ok) {
        return ok(result.value as Infer<T[number]>)
      }
      issues.push(...result.issues)
    }
    return { ok: false, issues: [{ path, message: `no union variant matched (${issues.length} issues)` }] }
  },
})

/**
 * An absolute filesystem path string. Rejects null bytes outright; deeper
 * policy (roots, symlinks) is enforced by main/security/pathPolicy.
 */
const absolutePath = (): Schema<string> => ({
  validate(value, path = '$') {
    const base = string({ minLength: 1, maxLength: 4096 }).validate(value, path)
    if (!base.ok) {
      return base
    }
    if (base.value.includes('\0')) {
      return fail(path, 'path contains null byte')
    }
    const isAbsolute = base.value.startsWith('/') || /^[a-zA-Z]:[\\/]/.test(base.value) || base.value.startsWith('\\\\')
    if (!isAbsolute) {
      return fail(path, 'expected absolute path')
    }
    return ok(base.value)
  },
})

export interface BytesOptions {
  maxBytes?: number
}

/** Binary payload (pasted images etc.). Electron structured clone delivers Uint8Array. */
const bytes = (options: BytesOptions = {}): Schema<Uint8Array> => ({
  validate(value, path = '$') {
    if (!(value instanceof Uint8Array)) {
      return fail(path, 'expected binary data (Uint8Array)')
    }
    const { maxBytes = 64 * 1024 * 1024 } = options
    if (value.byteLength > maxBytes) {
      return fail(path, `binary payload larger than ${maxBytes} bytes`)
    }
    return ok(value)
  },
})

export const s = {
  string,
  number,
  boolean,
  literal,
  optional,
  nullable,
  object,
  array,
  union,
  absolutePath,
  bytes,
}

export const formatIssues = (issues: ValidationIssue[]): string => {
  return issues.map((issue) => `${issue.path}: ${issue.message}`).join('; ')
}
