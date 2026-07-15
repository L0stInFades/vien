/**
 * SearchService contract (PLAN.md SEARCH-001): main-process ripgrep with
 * streaming results and cancellation.
 *
 * Protocol:
 *   invoke  mt::search-start        -> begins a content search
 *   invoke  mt::search-files-start  -> begins a file-name listing
 *   receive mt::search-result-batch <- { searchId, results?, paths?, pathCount }
 *   receive mt::search-done         <- { searchId, ok, pathCount, error? }
 *   invoke  mt::search-cancel       -> stops a running search (sender-owned only)
 *
 * Result shapes preserve the Atom ripgrep searcher structure the sidebar
 * UI consumes (filePath + matches with lineText/matchText/range/context).
 */
import { s, type Infer } from './schema'

export const SearchChannels = {
  contentStart: 'mt::search-start',
  filesStart: 'mt::search-files-start',
  cancel: 'mt::search-cancel',
  resultBatch: 'mt::search-result-batch',
  done: 'mt::search-done',
} as const

const searchIdSchema = s.string({ minLength: 4, maxLength: 128 })

export const ContentSearchOptionsSchema = s.object({
  isRegexp: s.optional(s.boolean()),
  isCaseSensitive: s.optional(s.boolean()),
  isWholeWord: s.optional(s.boolean()),
  inclusions: s.optional(s.array(s.string({ maxLength: 512 }), { maxItems: 128 })),
  exclusions: s.optional(s.array(s.string({ maxLength: 512 }), { maxItems: 128 })),
  noIgnore: s.optional(s.boolean()),
  followSymlinks: s.optional(s.boolean()),
  includeHidden: s.optional(s.boolean()),
  maxFileSize: s.optional(s.nullable(s.union(s.number({ min: 1 }), s.string({ maxLength: 32 })))),
  leadingContextLineCount: s.optional(s.number({ integer: true, min: 0, max: 8 })),
  trailingContextLineCount: s.optional(s.number({ integer: true, min: 0, max: 8 })),
})

export const ContentSearchRequestSchema = s.object({
  searchId: searchIdSchema,
  rootPath: s.absolutePath(),
  pattern: s.string({ minLength: 1, maxLength: 2048 }),
  options: s.optional(ContentSearchOptionsSchema),
})
export type ContentSearchRequest = Infer<typeof ContentSearchRequestSchema>

export const FileSearchOptionsSchema = s.object({
  inclusions: s.optional(s.array(s.string({ maxLength: 512 }), { maxItems: 128 })),
  noIgnore: s.optional(s.boolean()),
  followSymlinks: s.optional(s.boolean()),
  includeHidden: s.optional(s.boolean()),
})

export const FileSearchRequestSchema = s.object({
  searchId: searchIdSchema,
  rootPath: s.absolutePath(),
  options: s.optional(FileSearchOptionsSchema),
})
export type FileSearchRequest = Infer<typeof FileSearchRequestSchema>

export const SearchCancelRequestSchema = s.object({
  searchId: searchIdSchema,
})
export type SearchCancelRequest = Infer<typeof SearchCancelRequestSchema>

/** Atom-style match delivered to the sidebar search UI. */
export interface ContentSearchMatch {
  matchText: string
  lineText: string
  range: [[number, number], [number, number]]
  leadingContextLines: string[]
  trailingContextLines: string[]
}

export interface ContentSearchFileResult {
  filePath: string
  matches: ContentSearchMatch[]
}

export interface SearchResultBatch {
  searchId: string
  /** Content search: per-file results. */
  results?: ContentSearchFileResult[]
  /** File search: discovered paths. */
  paths?: string[]
  /** Cumulative count of matched files/paths so far. */
  pathCount: number
}

export interface SearchDoneEvent {
  searchId: string
  ok: boolean
  pathCount: number
  error?: { code: string; message: string }
}
