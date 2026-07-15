/**
 * Structured error codes for the capability IPC boundary (ADR-003).
 * Every service failure crossing preload must be one of these — no raw
 * exceptions, no failures dressed up as success.
 */

export const ErrorCodes = {
  VALIDATION_FAILED: 'E_VALIDATION_FAILED',
  SENDER_REJECTED: 'E_SENDER_REJECTED',
  PATH_DENIED: 'E_PATH_DENIED',
  NOT_FOUND: 'E_NOT_FOUND',
  ALREADY_EXISTS: 'E_ALREADY_EXISTS',
  CONFLICT: 'E_CONFLICT',
  CANCELLED: 'E_CANCELLED',
  IO_ERROR: 'E_IO',
  CAPABILITY_UNAVAILABLE: 'E_CAPABILITY_UNAVAILABLE',
  INTERNAL: 'E_INTERNAL',
} as const

export type ErrorCode = (typeof ErrorCodes)[keyof typeof ErrorCodes]

export interface SerializedServiceError {
  code: ErrorCode
  message: string
  details?: Record<string, unknown>
}

export class ServiceError extends Error {
  readonly code: ErrorCode
  readonly details?: Record<string, unknown>

  constructor(code: ErrorCode, message: string, details?: Record<string, unknown>) {
    super(message)
    this.name = 'ServiceError'
    this.code = code
    this.details = details
  }

  serialize(): SerializedServiceError {
    return { code: this.code, message: this.message, details: this.details }
  }

  static from(error: unknown): ServiceError {
    if (error instanceof ServiceError) {
      return error
    }
    if (error instanceof Error) {
      const nodeCode = (error as NodeJS.ErrnoException).code
      switch (nodeCode) {
        case 'ENOENT':
          return new ServiceError(ErrorCodes.NOT_FOUND, error.message, { nodeCode })
        case 'EEXIST':
          return new ServiceError(ErrorCodes.ALREADY_EXISTS, error.message, { nodeCode })
        case 'EACCES':
        case 'EPERM':
          return new ServiceError(ErrorCodes.PATH_DENIED, error.message, { nodeCode })
        case 'ENOSPC':
        case 'EROFS':
        case 'EBUSY':
        case 'EMFILE':
        case 'ENOTDIR':
        case 'EISDIR':
          return new ServiceError(ErrorCodes.IO_ERROR, error.message, { nodeCode })
        default:
          return new ServiceError(ErrorCodes.INTERNAL, error.message, nodeCode ? { nodeCode } : undefined)
      }
    }
    return new ServiceError(ErrorCodes.INTERNAL, String(error))
  }

  static deserialize(serialized: SerializedServiceError): ServiceError {
    return new ServiceError(serialized.code, serialized.message, serialized.details)
  }
}

export const isSerializedServiceError = (value: unknown): value is SerializedServiceError => {
  if (typeof value !== 'object' || value === null) {
    return false
  }
  const candidate = value as { code?: unknown; message?: unknown }
  return typeof candidate.code === 'string' && candidate.code.startsWith('E_') && typeof candidate.message === 'string'
}
