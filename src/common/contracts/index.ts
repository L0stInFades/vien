/**
 * Capability IPC contracts (ADR-003).
 *
 * The renderer, preload and main all import request/response shapes and
 * runtime schemas from here — this directory is the single interface
 * source of truth for the process boundary.
 */

export { s, formatIssues } from './schema'
export type { Schema, Infer, ValidationResult, ValidationIssue } from './schema'
export { ErrorCodes, ServiceError, isSerializedServiceError } from './errors'
export type { ErrorCode, SerializedServiceError } from './errors'

import type { SerializedServiceError } from './errors'

/** Bumped on breaking contract changes; preload and main verify compatibility. */
export const CONTRACTS_VERSION = 1

/**
 * Every capability invoke resolves to this envelope — never a bare value,
 * never a rejected promise carrying an unstructured Error. The renderer-side
 * bridge unwraps it and rethrows a typed ServiceError on failure.
 */
export type ServiceResult<T> = { ok: true; value: T } | { ok: false; error: SerializedServiceError }

export const serviceOk = <T>(value: T): ServiceResult<T> => ({ ok: true, value })
export const serviceErr = <T = never>(error: SerializedServiceError): ServiceResult<T> => ({ ok: false, error })
