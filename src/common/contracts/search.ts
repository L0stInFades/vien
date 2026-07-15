/**
 * SearchService contract (PLAN.md SEARCH-001): main-process ripgrep with
 * streaming results and cancellation.
 *
 * Protocol:
 *   invoke  mt::search-start        -> { searchId } begins a content search
 *   invoke  mt::search-files-start  -> { searchId } begins a file listing
 *   receive mt::search-result-batch <- { searchId, matches | paths }
 *   receive mt::search-done         <- { searchId, ok, hitCount, error? }
 *   invoke  mt::search-cancel       -> stops a running search
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
  noIgnore: s.optional(s.boolean()),
  followSymlinks: s.optional(s.boolean()),
  includeHidden: s.optional(s.boolean()),
  leadingContextLineCount: s.optional(s.number({ integer: true, min: 0, max: 8 })),
  trailingContextLineCount: s.optional(s.number({ integer: true, min: 0, max: 8 })),
  maxSearchDepth: s.optional(s.number({ integer: true, min: 0, max: 128 })),
})

export const ContentSearchRequestSchema = s.object({
  searchId: searchIdSchema,
  rootPath: s.absolutePath(),
  pattern: s.string({ minLength: 1, maxLength: 2048 }),
  options: s.optional(ContentSearchOptionsSchema),
})
export type ContentSearchRequest = Infer<typeof ContentSearchRequestSchema>

export const FileSearchRequestSchema = s.object({
  searchId: searchIdSchema,
  rootPath: s.absolutePath(),
  options: s.optional(
    s.object({
      inclusions: s.optional(s.array(s.string({ maxLength: 512 }), { maxItems: 128 })),
      noIgnore: s.optional(s.boolean()),
      followSymlinks: s.optional(s.boolean()),
      includeHidden: s.optional(s.boolean()),
    }),
  ),
})
export type FileSearchRequest = Infer<typeof FileSearchRequestSchema>

export const SearchCancelRequestSchema = s.object({
  searchId: searchIdSchema,
})
export type SearchCancelRequest = Infer<typeof SearchCancelRequestSchema>

/** One ripgrep match line delivered to the renderer. */
export interface SearchMatch {
  filePath: string
  lineNumber: number
  matchOffsets: [number, number][]
  lineText: string
}

export interface SearchResultBatch {
  searchId: string
  /** Content search: matches grouped as delivered. */
  matches?: SearchMatch[]
  /** File search: discovered paths. */
  paths?: string[]
}

export interface SearchDoneEvent {
  searchId: string
  ok: boolean
  hitCount: number
  error?: { code: string; message: string }
}
