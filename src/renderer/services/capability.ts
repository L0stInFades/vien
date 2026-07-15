/**
 * Renderer-side unwrapping for capability IPC envelopes (ADR-003).
 *
 * Preload returns ServiceResult envelopes as plain data because
 * contextBridge strips thrown custom errors down to bare messages.
 * This helper restores typed ServiceError instances so callers can
 * branch on error.code (E_PATH_DENIED, E_CONFLICT, ...).
 */
import { ServiceError, isSerializedServiceError } from 'common/contracts'
import type { CapabilityResult } from 'common/types/preload'

export const unwrapCapability = async <T>(resultPromise: Promise<CapabilityResult<T>>): Promise<T> => {
  const result = await resultPromise
  if (result && result.ok === true) {
    return result.value
  }
  if (result && result.ok === false && isSerializedServiceError(result.error)) {
    throw ServiceError.deserialize(result.error)
  }
  throw new ServiceError('E_INTERNAL', 'Malformed capability response.')
}
