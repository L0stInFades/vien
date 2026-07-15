/**
 * Structured error thrown by renderer-side stubs for capabilities that are
 * not (yet) available in the unprivileged renderer process.
 *
 * PLAN.md Phase 0 contract: a stubbed capability must fail loudly and
 * diagnosably — it must NEVER pretend success (empty result, no-op write,
 * fake process). Every stub call site therefore raises this error until the
 * capability is served by an explicit main-process service over IPC.
 */

export const ERR_CAPABILITY_UNAVAILABLE = 'ERR_CAPABILITY_UNAVAILABLE' as const

export interface CapabilityUnavailableDetails {
  /** Capability domain, e.g. "workspace.file-operations". */
  capability: string
  /** Concrete API that was called, e.g. "fs-extra.move". */
  api: string
  /** Where this capability is planned to live, e.g. "WorkspaceService (PLAN.md WORKSPACE-001)". */
  migration: string
}

export class CapabilityUnavailableError extends Error {
  readonly code = ERR_CAPABILITY_UNAVAILABLE
  readonly capability: string
  readonly api: string
  readonly migration: string

  constructor({ capability, api, migration }: CapabilityUnavailableDetails) {
    super(
      `Capability "${capability}" is unavailable in the renderer process ` +
        `(called "${api}"). It must go through ${migration}.`,
    )
    this.name = 'CapabilityUnavailableError'
    this.capability = capability
    this.api = api
    this.migration = migration
  }
}

export const isCapabilityUnavailable = (error: unknown): error is CapabilityUnavailableError => {
  return (
    error instanceof CapabilityUnavailableError ||
    (typeof error === 'object' && error !== null && (error as { code?: unknown }).code === ERR_CAPABILITY_UNAVAILABLE)
  )
}

/**
 * Helper for building a stub module: returns a function that always throws
 * a CapabilityUnavailableError for the given API.
 */
export const unavailableSync = (details: CapabilityUnavailableDetails): ((...args: unknown[]) => never) => {
  return () => {
    throw new CapabilityUnavailableError(details)
  }
}

/**
 * Async variant — rejects instead of throwing so callback/promise callers
 * receive a structured failure, and Node-style callbacks get the error as
 * their first argument before the promise rejects.
 */
export const unavailableAsync = (details: CapabilityUnavailableDetails): ((...args: unknown[]) => Promise<never>) => {
  return (...args: unknown[]) => {
    const error = new CapabilityUnavailableError(details)
    const maybeCallback = args[args.length - 1]
    if (typeof maybeCallback === 'function') {
      ;(maybeCallback as (err: Error) => void)(error)
    }
    return Promise.reject(error)
  }
}
