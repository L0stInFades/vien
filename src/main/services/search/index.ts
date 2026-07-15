/**
 * SearchService (PLAN.md SEARCH-001): main-process ripgrep with streaming
 * results and cancellation. The renderer never spawns processes; it starts
 * a search over a validated capability channel, receives result batches as
 * window-targeted events, and can cancel only its own searches.
 */
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process'
import log from 'electron-log'
import { ErrorCodes, ServiceError } from 'common/contracts'
import {
  ContentSearchRequestSchema,
  FileSearchRequestSchema,
  SearchCancelRequestSchema,
  SearchChannels,
  type ContentSearchRequest,
  type FileSearchRequest,
  type SearchDoneEvent,
  type SearchResultBatch,
} from 'common/contracts/search'
import { handleCapability, type GuardedContext } from '../../security/ipcGuard'
import { assertPathInScope, type WorkspaceScope } from '../../security/pathPolicy'
import { RipgrepJsonParser, isMultilineRegexp, prepareGlobs, prepareRegexp } from './ripgrepParser'

interface EditorWindowLike {
  openedRootDirectory?: string | null
  openedFiles?: readonly string[]
}

interface WindowManagerLike {
  get(windowId: number): EditorWindowLike | undefined
}

interface ActiveSearch {
  child: ChildProcessWithoutNullStreams
  windowId: number
  cancelled: boolean
}

const resolveRipgrepPath = (): string => {
  if (process.env.MARKTEXT_RIPGREP_PATH) {
    // NOTE: Binary must be a compatible version, otherwise the searcher may fail.
    return process.env.MARKTEXT_RIPGREP_PATH
  }
  // vscode-ripgrep is unpacked out of asar because of the binary.
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { rgPath } = require('vscode-ripgrep') as { rgPath: string }
  return rgPath.replace(/\bapp\.asar\b/, 'app.asar.unpacked')
}

export class SearchService {
  private readonly _windowManager: WindowManagerLike
  private readonly _active = new Map<string, ActiveSearch>()
  private _rgPath: string | null = null

  constructor(windowManager: WindowManagerLike) {
    this._windowManager = windowManager
    this._registerHandlers()
  }

  private _scopeFor(windowId: number): WorkspaceScope {
    const window = this._windowManager.get(windowId)
    return {
      rootDirectory: window?.openedRootDirectory ?? null,
      openedFiles: window?.openedFiles ?? [],
    }
  }

  private _key(windowId: number, searchId: string): string {
    return `${windowId}:${searchId}`
  }

  private _ripgrepPath(): string {
    if (!this._rgPath) {
      this._rgPath = resolveRipgrepPath()
    }
    return this._rgPath
  }

  private _registerHandlers(): void {
    handleCapability(SearchChannels.contentStart, ContentSearchRequestSchema, (request, context) => {
      return this._startContentSearch(request, context)
    })

    handleCapability(SearchChannels.filesStart, FileSearchRequestSchema, (request, context) => {
      return this._startFileSearch(request, context)
    })

    handleCapability(SearchChannels.cancel, SearchCancelRequestSchema, (request, context) => {
      const key = this._key(context.windowId, request.searchId)
      const active = this._active.get(key)
      if (active) {
        active.cancelled = true
        active.child.kill()
      }
      return { cancelled: !!active }
    })
  }

  private _buildContentArgs(request: ContentSearchRequest): string[] {
    const options = request.options ?? {}
    const args = ['--json']

    let regexpStr: string | null = null
    if (options.isRegexp) {
      regexpStr = prepareRegexp(request.pattern)
      args.push('--regexp', regexpStr)
    } else {
      args.push('--fixed-strings')
    }
    if (regexpStr && isMultilineRegexp(regexpStr)) {
      args.push('--multiline')
    }
    args.push(options.isCaseSensitive ? '--case-sensitive' : '--ignore-case')
    if (options.isWholeWord) {
      args.push('--word-regexp')
    }
    if (options.followSymlinks) {
      args.push('--follow')
    }
    if (options.maxFileSize) {
      args.push('--max-filesize', `${options.maxFileSize}`)
    }
    if (options.includeHidden) {
      args.push('--hidden')
    }
    if (options.noIgnore) {
      args.push('--no-ignore')
    }
    if (options.leadingContextLineCount) {
      args.push('--before-context', `${options.leadingContextLineCount}`)
    }
    if (options.trailingContextLineCount) {
      args.push('--after-context', `${options.trailingContextLineCount}`)
    }
    for (const inclusion of prepareGlobs(options.inclusions, request.rootPath)) {
      args.push('--iglob', inclusion)
    }
    for (const exclusion of prepareGlobs(options.exclusions, request.rootPath)) {
      args.push('--iglob', `!${exclusion}`)
    }
    args.push('--')
    if (!options.isRegexp) {
      args.push(request.pattern)
    }
    args.push(request.rootPath)
    return args
  }

  private _buildFileArgs(request: FileSearchRequest): string[] {
    const options = request.options ?? {}
    const args = ['--files']
    if (options.followSymlinks) {
      args.push('--follow')
    }
    if (options.includeHidden) {
      args.push('--hidden')
    }
    if (options.noIgnore) {
      args.push('--no-ignore')
    }
    for (const inclusion of prepareGlobs(options.inclusions, request.rootPath)) {
      args.push('--iglob', inclusion)
    }
    args.push('--')
    args.push(request.rootPath)
    return args
  }

  private _spawnSearch(
    searchId: string,
    rootPath: string,
    args: string[],
    context: GuardedContext,
    attach: (child: ChildProcessWithoutNullStreams, emitBatch: (batch: Partial<SearchResultBatch>) => void) => void,
  ): { searchId: string } {
    const scope = this._scopeFor(context.windowId)
    const resolvedRoot = assertPathInScope(rootPath, scope, 'search root')

    const key = this._key(context.windowId, searchId)
    if (this._active.has(key)) {
      throw new ServiceError(ErrorCodes.CONFLICT, `Search "${searchId}" is already running.`)
    }

    let child: ChildProcessWithoutNullStreams
    try {
      child = spawn(this._ripgrepPath(), args, {
        cwd: resolvedRoot,
        stdio: ['pipe', 'pipe', 'pipe'],
      })
    } catch (error) {
      throw ServiceError.from(error)
    }

    const active: ActiveSearch = { child, windowId: context.windowId, cancelled: false }
    this._active.set(key, active)

    const webContents = context.browserWindow.webContents
    let pathCount = 0
    let stderrBuffer = ''

    const emitBatch = (batch: Partial<SearchResultBatch>): void => {
      if (active.cancelled || webContents.isDestroyed()) {
        return
      }
      if (batch.results) {
        pathCount += batch.results.length
      }
      if (batch.paths) {
        pathCount += batch.paths.length
      }
      const payload: SearchResultBatch = { searchId, pathCount, ...batch }
      webContents.send(SearchChannels.resultBatch, payload)
    }

    const emitDone = (ok: boolean, error?: { code: string; message: string }): void => {
      this._active.delete(key)
      if (webContents.isDestroyed()) {
        return
      }
      const payload: SearchDoneEvent = { searchId, ok, pathCount, error }
      webContents.send(SearchChannels.done, payload)
    }

    child.stderr.on('data', (chunk: Buffer) => {
      stderrBuffer += chunk.toString()
    })
    child.on('error', (error) => {
      log.warn(`[search] ${searchId} failed to spawn: ${error.message}`)
      emitDone(false, { code: ErrorCodes.IO_ERROR, message: error.message })
    })
    child.on('close', (code) => {
      // rg exits 1 when no results were found; anything above is an error.
      if (active.cancelled) {
        emitDone(true)
      } else if (code !== null && code > 1) {
        emitDone(false, { code: ErrorCodes.IO_ERROR, message: stderrBuffer.trim() || `ripgrep exited with ${code}` })
      } else {
        emitDone(true)
      }
    })

    attach(child, emitBatch)
    return { searchId }
  }

  private _startContentSearch(request: ContentSearchRequest, context: GuardedContext): { searchId: string } {
    const args = this._buildContentArgs(request)
    return this._spawnSearch(request.searchId, request.rootPath, args, context, (child, emitBatch) => {
      const parser = new RipgrepJsonParser((fileResult) => {
        emitBatch({ results: [fileResult] })
      })
      child.stdout.on('data', (chunk: Buffer) => {
        parser.push(chunk.toString())
      })
    })
  }

  private _startFileSearch(request: FileSearchRequest, context: GuardedContext): { searchId: string } {
    const args = this._buildFileArgs(request)
    return this._spawnSearch(request.searchId, request.rootPath, args, context, (child, emitBatch) => {
      let buffer = ''
      child.stdout.on('data', (chunk: Buffer) => {
        buffer += chunk.toString()
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''
        const paths = lines.filter((line) => line.length > 0)
        if (paths.length > 0) {
          emitBatch({ paths })
        }
      })
    })
  }
}
