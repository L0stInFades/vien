/**
 * Path policy for capability IPC handlers (ADR-003 / PLAN.md §5.7).
 *
 * Renderer-supplied paths are untrusted. Every handler that touches the
 * filesystem must resolve the request path through this module before use:
 * normalization, null-byte rejection, and workspace scoping (the sender
 * window may only operate inside its opened root directory or next to one
 * of its opened files). Symlink escapes are defeated by realpath-ing the
 * deepest existing ancestor before containment checks.
 */
import fs from 'node:fs'
import path from 'node:path'
import { ErrorCodes, ServiceError } from 'common/contracts'

const isWindows = process.platform === 'win32'

const normalizeForCompare = (p: string): string => {
  const normalized = path.normalize(p)
  return isWindows ? normalized.toLowerCase() : normalized
}

/** Normalize an untrusted request path. Throws PATH_DENIED on garbage. */
export const normalizeRequestPath = (pathname: unknown): string => {
  if (typeof pathname !== 'string' || pathname.length === 0) {
    throw new ServiceError(ErrorCodes.PATH_DENIED, 'Path must be a non-empty string.')
  }
  if (pathname.includes('\0')) {
    throw new ServiceError(ErrorCodes.PATH_DENIED, 'Path contains a null byte.')
  }
  const normalized = path.normalize(pathname)
  if (!path.isAbsolute(normalized)) {
    throw new ServiceError(ErrorCodes.PATH_DENIED, 'Path must be absolute.')
  }
  return normalized
}

/** True if `child` is `parent` or inside it (after normalization only — no fs access). */
export const isPathInside = (child: string, parent: string): boolean => {
  const rel = path.relative(normalizeForCompare(parent), normalizeForCompare(child))
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel))
}

/**
 * Resolve the deepest existing ancestor of `pathname` through realpath so a
 * symlinked directory cannot smuggle operations outside the allowed roots.
 * Returns the fully-resolved equivalent of `pathname`.
 */
export const resolveRealParent = (pathname: string): string => {
  let existing = pathname
  const tail: string[] = []
  // Walk up until we find an existing ancestor (the target itself may not exist yet).
  // eslint-disable-next-line no-constant-condition
  while (true) {
    if (fs.existsSync(existing)) {
      break
    }
    const parent = path.dirname(existing)
    if (parent === existing) {
      break
    }
    tail.unshift(path.basename(existing))
    existing = parent
  }
  let real: string
  try {
    real = fs.realpathSync.native ? fs.realpathSync.native(existing) : fs.realpathSync(existing)
  } catch (_err) {
    real = existing
  }
  return tail.length > 0 ? path.join(real, ...tail) : real
}

export interface WorkspaceScope {
  /** The window's opened root directory ('' or null when no folder is open). */
  rootDirectory?: string | null
  /** Absolute paths of files opened in the window's tabs. */
  openedFiles?: readonly string[]
  /** Extra explicitly-granted roots (e.g. user-picked image output dir). */
  extraRoots?: readonly string[]
}

/**
 * Assert that `pathname` (untrusted) is inside the sender's workspace scope.
 * Allowed roots: the opened root directory, the parent directory of every
 * opened file, and any explicitly granted extra roots.
 * Returns the normalized, symlink-resolved path to use for the operation.
 */
export const assertPathInScope = (pathname: unknown, scope: WorkspaceScope, purpose: string): string => {
  const normalized = normalizeRequestPath(pathname)
  const resolved = resolveRealParent(normalized)

  const roots: string[] = []
  if (scope.rootDirectory) {
    roots.push(resolveRealParent(normalizeRequestPath(scope.rootDirectory)))
  }
  for (const file of scope.openedFiles ?? []) {
    if (typeof file === 'string' && file.length > 0 && path.isAbsolute(file)) {
      roots.push(resolveRealParent(path.dirname(path.normalize(file))))
    }
  }
  for (const extra of scope.extraRoots ?? []) {
    if (typeof extra === 'string' && extra.length > 0 && path.isAbsolute(extra)) {
      roots.push(resolveRealParent(path.normalize(extra)))
    }
  }

  if (roots.length === 0) {
    throw new ServiceError(ErrorCodes.PATH_DENIED, `No workspace scope available for ${purpose}.`, {
      pathname: normalized,
    })
  }
  for (const root of roots) {
    if (isPathInside(resolved, root)) {
      return resolved
    }
  }
  throw new ServiceError(ErrorCodes.PATH_DENIED, `Path is outside the workspace scope for ${purpose}.`, {
    pathname: normalized,
  })
}
