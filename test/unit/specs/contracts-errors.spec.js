/**
 * ServiceError normalization (ADR-003 / BOUNDARY-001).
 */
import { describe, it, expect } from 'vitest'
import { ErrorCodes, ServiceError, isSerializedServiceError } from '../../../src/common/contracts/errors'

describe('ServiceError', () => {
  it('maps Node fs error codes to structured codes', () => {
    const enoent = Object.assign(new Error('no such file'), { code: 'ENOENT' })
    expect(ServiceError.from(enoent).code).toBe(ErrorCodes.NOT_FOUND)

    const eexist = Object.assign(new Error('exists'), { code: 'EEXIST' })
    expect(ServiceError.from(eexist).code).toBe(ErrorCodes.ALREADY_EXISTS)

    const eacces = Object.assign(new Error('denied'), { code: 'EACCES' })
    expect(ServiceError.from(eacces).code).toBe(ErrorCodes.PATH_DENIED)

    const enospc = Object.assign(new Error('disk full'), { code: 'ENOSPC' })
    expect(ServiceError.from(enospc).code).toBe(ErrorCodes.IO_ERROR)
  })

  it('passes ServiceError through unchanged', () => {
    const original = new ServiceError(ErrorCodes.CONFLICT, 'disk version changed')
    expect(ServiceError.from(original)).toBe(original)
  })

  it('wraps arbitrary values as INTERNAL', () => {
    expect(ServiceError.from('boom').code).toBe(ErrorCodes.INTERNAL)
    expect(ServiceError.from(new Error('plain')).code).toBe(ErrorCodes.INTERNAL)
  })

  it('serialize/deserialize round-trips code, message and details', () => {
    const error = new ServiceError(ErrorCodes.PATH_DENIED, 'outside scope', { pathname: '/x' })
    const wire = error.serialize()
    expect(isSerializedServiceError(wire)).toBe(true)
    const back = ServiceError.deserialize(wire)
    expect(back.code).toBe(ErrorCodes.PATH_DENIED)
    expect(back.message).toBe('outside scope')
    expect(back.details).toEqual({ pathname: '/x' })
  })

  it('isSerializedServiceError rejects non-error shapes', () => {
    expect(isSerializedServiceError(null)).toBe(false)
    expect(isSerializedServiceError({ code: 'nope', message: 'x' })).toBe(false)
    expect(isSerializedServiceError({ ok: true })).toBe(false)
  })
})
