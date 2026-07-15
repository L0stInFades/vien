import fsPromises from 'node:fs/promises'
import path from 'node:path'
import log from 'electron-log'
import iconv from 'iconv-lite'
import { LINE_ENDING_REG, LF_LINE_ENDING_REG, CRLF_LINE_ENDING_REG } from '../config'
import { isDirectory2 } from 'common/filesystem'
import { isMarkdownFile } from 'common/filesystem/paths'
import { normalizeAndResolvePath } from '../filesystem'
import { atomicWriteFile, getDiskVersion, isSameDiskVersion } from './atomicWrite'
import { guessEncoding } from './encoding'

const getLineEnding = (lineEnding) => {
  if (lineEnding === 'lf') {
    return '\n'
  } else if (lineEnding === 'crlf') {
    return '\r\n'
  }

  // This should not happend but use fallback value.
  log.error(`Invalid end of line character: expected "lf" or "crlf" but got "${lineEnding}".`)
  return '\n'
}

const convertLineEndings = (text, lineEnding) => {
  return text.replace(LINE_ENDING_REG, getLineEnding(lineEnding))
}

/**
 * Special function to normalize directory and markdown file paths.
 *
 * @param {string} pathname The path to the file or directory.
 * @returns {{isDir: boolean, path: string}?} Returns the normalize path and a
 * directory hint or null if it's not a directory or markdown file.
 */
export const normalizeMarkdownPath = (pathname) => {
  const isDir = isDirectory2(pathname)
  if (isDir || isMarkdownFile(pathname)) {
    // Normalize and resolve the path or link target.
    const resolved = normalizeAndResolvePath(pathname)
    if (resolved) {
      return { isDir, path: resolved }
    } else {
      console.error(`[ERROR] Cannot resolve "${pathname}".`)
    }
  }
  return null
}

/**
 * Error thrown when the on-disk version changed since the renderer last
 * loaded/saved the document (SAFE-003). The caller must surface a conflict,
 * never overwrite silently.
 */
export class DiskVersionConflictError extends Error {
  constructor(pathname, expectedDiskVersion, actualDiskVersion) {
    super(`The file on disk changed since it was loaded: ${pathname}`)
    this.name = 'DiskVersionConflictError'
    this.code = 'E_CONFLICT'
    this.pathname = pathname
    this.expectedDiskVersion = expectedDiskVersion
    this.actualDiskVersion = actualDiskVersion
  }
}

/**
 * Write the content into a file (atomic replace, SAFE-002).
 *
 * @param {string} pathname The path to the file.
 * @param {string} content The buffer to save.
 * @param {IMarkdownDocumentOptions} options The markdown document options
 * @param {{mtimeMs: number, size: number}|null} [expectedDiskVersion] When
 * given and the file exists with a different version, the write is refused
 * with DiskVersionConflictError (SAFE-003 compare-and-swap).
 * @returns {Promise<{mtimeMs: number, size: number}>} The new disk version.
 */
export const writeMarkdownFile = async (pathname, content, options, expectedDiskVersion = null) => {
  const { adjustLineEndingOnSave, lineEnding } = options
  const { encoding, isBom } = options.encoding
  const extension = path.extname(pathname) || '.md'
  if (!pathname.endsWith(extension)) {
    pathname = `${pathname}${extension}`
  }

  if (expectedDiskVersion) {
    const actualDiskVersion = await getDiskVersion(pathname)
    if (actualDiskVersion && !isSameDiskVersion(expectedDiskVersion, actualDiskVersion)) {
      throw new DiskVersionConflictError(pathname, expectedDiskVersion, actualDiskVersion)
    }
  }

  if (adjustLineEndingOnSave) {
    content = convertLineEndings(content, lineEnding)
  }

  const buffer = iconv.encode(content, encoding, { addBOM: isBom })
  return atomicWriteFile(pathname, buffer)
}

/**
 * Reads the contents of a markdown file.
 *
 * @param {string} pathname The path to the markdown file.
 * @param {string} preferredEol The preferred EOL.
 * @param {boolean} autoGuessEncoding Whether we should try to auto guess encoding.
 * @param {*} trimTrailingNewline The trim trailing newline option.
 * @returns {IMarkdownDocumentRaw} Returns a raw markdown document.
 */
export const loadMarkdownFile = async (pathname, preferredEol, autoGuessEncoding = true, trimTrailingNewline = 2) => {
  // TODO: Use streams to not buffer the file multiple times and only guess
  //       encoding on the first 256/512 bytes.

  const buffer = await fsPromises.readFile(path.resolve(pathname))
  const diskVersion = await getDiskVersion(path.resolve(pathname))

  const encoding = guessEncoding(buffer, autoGuessEncoding)
  const supported = iconv.encodingExists(encoding.encoding)
  if (!supported) {
    throw new Error(`"${encoding.encoding}" encoding is not supported.`)
  }

  let markdown = iconv.decode(buffer, encoding.encoding)

  // Detect line ending
  const isLf = LF_LINE_ENDING_REG.test(markdown)
  const isCrlf = CRLF_LINE_ENDING_REG.test(markdown)
  const isMixedLineEndings = isLf && isCrlf
  const isUnknownEnding = !isLf && !isCrlf
  let lineEnding = preferredEol
  if (isLf && !isCrlf) {
    lineEnding = 'lf'
  } else if (isCrlf && !isLf) {
    lineEnding = 'crlf'
  }

  let adjustLineEndingOnSave = false
  if (isMixedLineEndings || isUnknownEnding || lineEnding !== 'lf') {
    adjustLineEndingOnSave = lineEnding !== 'lf'
    // Convert to LF for internal use.
    markdown = convertLineEndings(markdown, 'lf')
  }

  // Detect final newline
  if (trimTrailingNewline === 2) {
    if (!markdown) {
      // Use default value
      trimTrailingNewline = 3
    } else {
      const lastIndex = markdown.length - 1
      if (lastIndex >= 1 && markdown[lastIndex] === '\n' && markdown[lastIndex - 1] === '\n') {
        // Disabled
        trimTrailingNewline = 2
      } else if (markdown[lastIndex] === '\n') {
        // Ensure single trailing newline
        trimTrailingNewline = 1
      } else {
        // Trim trailing newlines
        trimTrailingNewline = 0
      }
    }
  }

  const filename = path.basename(pathname)
  return {
    // document information
    markdown,
    filename,
    pathname,

    // options
    encoding,
    lineEnding,
    adjustLineEndingOnSave,
    trimTrailingNewline,

    // raw file information
    isMixedLineEndings,
    diskVersion,
  }
}
