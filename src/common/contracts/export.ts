/**
 * ExportService contract (PLAN.md EXPORT-001): custom export theme access.
 * Themes live under <userData>/themes/export; the renderer never reads the
 * disk itself.
 */
import { s, type Infer } from './schema'

export const ExportChannels = {
  listThemes: 'mt::fs-list-export-themes',
  readTheme: 'mt::fs-read-export-theme',
} as const

export const ListExportThemesRequestSchema = s.object({})
export type ListExportThemesRequest = Infer<typeof ListExportThemesRequestSchema>

export interface ExportThemeEntry {
  /** Filename under themes/export, e.g. "my-theme.css". */
  name: string
}

/** Theme name is a bare css filename — never a path. */
export const ReadExportThemeRequestSchema = s.object({
  name: s.string({
    minLength: 1,
    maxLength: 255,
    pattern: /^[^/\\\0]+\.css$/,
    patternName: 'a plain .css filename without path separators',
  }),
})
export type ReadExportThemeRequest = Infer<typeof ReadExportThemeRequestSchema>
