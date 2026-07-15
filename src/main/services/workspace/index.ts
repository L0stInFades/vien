/**
 * WorkspaceService (PLAN.md WORKSPACE-001): file tree operations owned by
 * the main process. The renderer calls narrow capability methods; every
 * request is schema-validated (ipcGuard) and path-scoped (pathPolicy) to
 * the sender window's workspace.
 *
 * Safety improvements over the legacy renderer implementation:
 * - create never truncates an existing file (legacy outputFile('') wiped it);
 * - copy never silently overwrites the destination (legacy fs.copy default);
 * - every failure surfaces as a structured ServiceError, never fake success.
 */
import path from 'node:path'
import fs from 'fs-extra'
import { ErrorCodes, ServiceError } from 'common/contracts'
import {
  FsCreateRequestSchema,
  FsIsExecutableRequestSchema,
  FsPasteRequestSchema,
  FsRenameRequestSchema,
  WorkspaceChannels,
} from 'common/contracts/workspace'
import { handleCapability } from '../../security/ipcGuard'
import { assertPathInScope, normalizeRequestPath, type WorkspaceScope } from '../../security/pathPolicy'

interface EditorWindowLike {
  openedRootDirectory?: string | null
  openedFiles?: readonly string[]
}

interface WindowManagerLike {
  get(windowId: number): EditorWindowLike | undefined
}

export class WorkspaceService {
  private readonly _windowManager: WindowManagerLike

  constructor(windowManager: WindowManagerLike) {
    this._windowManager = windowManager
    this._registerHandlers()
  }

  scopeFor(windowId: number): WorkspaceScope {
    const window = this._windowManager.get(windowId)
    return {
      rootDirectory: window?.openedRootDirectory ?? null,
      openedFiles: window?.openedFiles ?? [],
    }
  }

  private _registerHandlers(): void {
    handleCapability(WorkspaceChannels.create, FsCreateRequestSchema, async (request, context) => {
      const scope = this.scopeFor(context.windowId)
      const target = assertPathInScope(request.pathname, scope, 'create')
      if (request.kind === 'directory') {
        await fs.ensureDir(target)
      } else {
        await fs.ensureDir(path.dirname(target))
        // 'wx' — fail instead of truncating an existing file.
        await fs.writeFile(target, '', { flag: 'wx' })
      }
      return { pathname: target }
    })

    handleCapability(WorkspaceChannels.paste, FsPasteRequestSchema, async (request, context) => {
      const scope = this.scopeFor(context.windowId)
      const src = assertPathInScope(request.src, scope, 'paste source')
      const dest = assertPathInScope(request.dest, scope, 'paste destination')
      if (src === dest) {
        throw new ServiceError(ErrorCodes.VALIDATION_FAILED, 'Source and destination must not be the same.')
      }
      if (request.kind === 'cut') {
        await fs.move(src, dest, { overwrite: false })
      } else {
        await fs.copy(src, dest, { overwrite: false, errorOnExist: true })
      }
      return { pathname: dest }
    })

    handleCapability(WorkspaceChannels.rename, FsRenameRequestSchema, async (request, context) => {
      const scope = this.scopeFor(context.windowId)
      const src = assertPathInScope(request.src, scope, 'rename source')
      const dest = assertPathInScope(request.dest, scope, 'rename destination')
      if (src === dest) {
        return { pathname: dest }
      }
      await fs.move(src, dest, { overwrite: false })
      return { pathname: dest }
    })

    // Read-only executable check for user-configured uploader scripts.
    // Deliberately not workspace-scoped: the settings UI validates paths the
    // user picked anywhere on disk. Exposes a single permission bit, no content.
    handleCapability(WorkspaceChannels.isExecutable, FsIsExecutableRequestSchema, async (request) => {
      const pathname = normalizeRequestPath(request.pathname)
      try {
        const stat = await fs.stat(pathname)
        const executable = stat.isFile() && (stat.mode & 0o111) !== 0
        return { executable }
      } catch (_error) {
        return { executable: false }
      }
    })
  }
}
