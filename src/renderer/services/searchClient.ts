/**
 * Renderer search client (PLAN.md SEARCH-001): keeps the Atom-style
 * searcher facade (`search(directories, pattern, options)` returning a
 * thenable with `.cancel()`, streaming via `didMatch`/`didSearchPaths`)
 * while the actual ripgrep processes run in the main-process SearchService.
 */
import { unwrapCapability } from '@/services/capability'
import type { SearchBatchPayload, SearchDonePayload } from 'common/types/preload'

export interface ContentSearcherOptions {
  didMatch?: (result: { filePath: string; matches: unknown[] }) => void
  didSearchPaths?: (count: number) => void
  inclusions?: string[]
  exclusions?: string[]
  noIgnore?: boolean
  followSymlinks?: boolean
  includeHidden?: boolean
  isWholeWord?: boolean
  isRegexp?: boolean
  isCaseSensitive?: boolean
  maxFileSize?: number | string | null
  leadingContextLineCount?: number
  trailingContextLineCount?: number
}

export interface CancellableSearch extends Promise<void> {
  cancel?: () => void
}

let searchCounter = 0
const nextSearchId = (prefix: string): string => {
  searchCounter = (searchCounter + 1) % Number.MAX_SAFE_INTEGER
  return `${prefix}-${Date.now().toString(36)}-${searchCounter}`
}

type StartFn = (searchId: string, rootPath: string) => Promise<unknown>

const runSearch = (
  prefix: string,
  directories: string[],
  onBatch: (batch: SearchBatchPayload) => void,
  start: StartFn,
): CancellableSearch => {
  const searchIds = new Set<string>()
  let cancelled = false
  let unsubscribeBatch: (() => void) | null = null
  let unsubscribeDone: (() => void) | null = null

  const cleanup = () => {
    unsubscribeBatch?.()
    unsubscribeDone?.()
    unsubscribeBatch = null
    unsubscribeDone = null
  }

  const promise = new Promise<void>((resolve, reject) => {
    const pending = new Set<string>()
    let failure: Error | null = null

    unsubscribeBatch = window.api.search.onResultBatch((batch) => {
      if (cancelled || !searchIds.has(batch.searchId)) {
        return
      }
      onBatch(batch)
    })

    unsubscribeDone = window.api.search.onDone((done: SearchDonePayload) => {
      if (!searchIds.has(done.searchId)) {
        return
      }
      pending.delete(done.searchId)
      if (!done.ok && !failure) {
        failure = new Error(done.error?.message || 'Search failed.')
      }
      if (pending.size === 0) {
        cleanup()
        if (failure && !cancelled) {
          reject(failure)
        } else {
          resolve()
        }
      }
    })

    Promise.all(
      directories.map((rootPath) => {
        const searchId = nextSearchId(prefix)
        searchIds.add(searchId)
        pending.add(searchId)
        return start(searchId, rootPath)
      }),
    ).catch((error) => {
      cleanup()
      reject(error)
    })
  })

  const cancellable = promise as CancellableSearch
  cancellable.cancel = () => {
    cancelled = true
    for (const searchId of searchIds) {
      window.api.search.cancel(searchId)
    }
  }
  return cancellable
}

export class RipgrepDirectorySearcher {
  search(directories: string[], pattern: string, options: ContentSearcherOptions): CancellableSearch {
    const didMatch = options.didMatch ?? (() => {})
    const didSearchPaths = options.didSearchPaths ?? (() => {})
    const {
      inclusions,
      exclusions,
      noIgnore,
      followSymlinks,
      includeHidden,
      isWholeWord,
      isRegexp,
      isCaseSensitive,
      maxFileSize,
      leadingContextLineCount,
      trailingContextLineCount,
    } = options

    return runSearch(
      'content',
      directories,
      (batch) => {
        for (const result of batch.results ?? []) {
          didMatch(result)
        }
        didSearchPaths(batch.pathCount)
      },
      (searchId, rootPath) =>
        unwrapCapability(
          window.api.search.startContentSearch({
            searchId,
            rootPath,
            pattern,
            // Values must be plain JSON-safe data: reactive proxies or frozen
            // arrays cannot cross the contextBridge ("An object could not be cloned").
            options: {
              inclusions: Array.isArray(inclusions) ? [...inclusions] : undefined,
              exclusions: Array.isArray(exclusions) ? [...exclusions] : undefined,
              noIgnore: !!noIgnore,
              followSymlinks: !!followSymlinks,
              includeHidden: !!includeHidden,
              isWholeWord: !!isWholeWord,
              isRegexp: !!isRegexp,
              isCaseSensitive: !!isCaseSensitive,
              maxFileSize: maxFileSize ?? undefined,
              leadingContextLineCount,
              trailingContextLineCount,
            },
          }),
        ),
    )
  }
}

export interface FileSearcherOptions {
  didMatch?: (pathname: string) => void
  didSearchPaths?: (count: number) => void
  inclusions?: string[]
  noIgnore?: boolean
  followSymlinks?: boolean
  includeHidden?: boolean
}

export class FileSearcher {
  search(directories: string[], _pattern: string, options: FileSearcherOptions): CancellableSearch {
    const didMatch = options.didMatch ?? (() => {})
    const didSearchPaths = options.didSearchPaths ?? (() => {})
    const { inclusions, noIgnore, followSymlinks, includeHidden } = options

    return runSearch(
      'files',
      directories,
      (batch) => {
        for (const pathname of batch.paths ?? []) {
          didMatch(pathname)
        }
        didSearchPaths(batch.pathCount)
      },
      (searchId, rootPath) =>
        unwrapCapability(
          window.api.search.startFileSearch({
            searchId,
            rootPath,
            options: {
              inclusions: Array.isArray(inclusions) ? [...inclusions] : undefined,
              noIgnore: !!noIgnore,
              followSymlinks: !!followSymlinks,
              includeHidden: !!includeHidden,
            },
          }),
        ),
    )
  }
}
