/**
 * Export theme access (PLAN.md EXPORT-001, first slice): the renderer
 * lists and reads custom export themes through the main process instead
 * of touching <userData>/themes/export itself.
 */
import path from 'node:path'
import fs from 'fs-extra'
import { ErrorCodes, ServiceError } from 'common/contracts'
import { ExportChannels, ListExportThemesRequestSchema, ReadExportThemeRequestSchema } from 'common/contracts/export'
import { handleCapability } from '../../security/ipcGuard'

const MAX_THEME_BYTES = 5 * 1024 * 1024

interface ExportThemePaths {
  userDataPath: string
}

export interface ExportThemeListEntry {
  /** css filename under themes/export. */
  name: string
  /** Human label from the first-line comment, falling back to the filename. */
  label: string
}

export class ExportThemeService {
  private readonly _themeDir: string

  constructor(paths: ExportThemePaths) {
    this._themeDir = path.join(paths.userDataPath, 'themes', 'export')
    this._registerHandlers()
  }

  get themeDir(): string {
    return this._themeDir
  }

  private _registerHandlers(): void {
    handleCapability(ExportChannels.listThemes, ListExportThemesRequestSchema, async () => {
      const entries: ExportThemeListEntry[] = []
      let filenames: string[] = []
      try {
        filenames = await fs.readdir(this._themeDir)
      } catch (_error) {
        return { themes: entries } // no custom theme dir yet — empty list
      }
      for (const filename of filenames) {
        if (!/\.css$/i.test(filename)) {
          continue
        }
        const fullname = path.join(this._themeDir, filename)
        try {
          const stat = await fs.stat(fullname)
          if (!stat.isFile() || stat.size > MAX_THEME_BYTES) {
            continue
          }
          const content = await fs.readFile(fullname, 'utf8')
          // Theme name comment on the first line only (legacy format).
          const match = content.match(/^(?:\/\*+[ \t]*([A-Za-z0-9 -]+)[ \t]*(?:\*+\/|[\n\r])?)/)
          entries.push({ name: filename, label: match?.[1]?.trim() || filename })
        } catch (_error) {
          // Skip unreadable entries; the list must never fake success for them.
        }
      }
      return { themes: entries }
    })

    handleCapability(ExportChannels.readTheme, ReadExportThemeRequestSchema, async (request) => {
      // Schema guarantees a bare filename (no separators); join stays inside.
      const fullname = path.join(this._themeDir, request.name)
      const stat = await fs.stat(fullname).catch(() => null)
      if (!stat || !stat.isFile()) {
        throw new ServiceError(ErrorCodes.NOT_FOUND, `Export theme not found: ${request.name}`)
      }
      if (stat.size > MAX_THEME_BYTES) {
        throw new ServiceError(ErrorCodes.IO_ERROR, `Export theme larger than ${MAX_THEME_BYTES} bytes.`)
      }
      const css = await fs.readFile(fullname, 'utf8')
      return { css }
    })
  }
}
