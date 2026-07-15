// Ripgrep JSON output processing, ported from the renderer implementation,
// itself a modified version of
// https://github.com/atom/atom/blob/master/src/ripgrep-directory-searcher.js
//
// Copyright (c) 2011-2019 GitHub Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
import path from 'node:path'
import type { ContentSearchMatch } from 'common/contracts/search'

interface RgText {
  text?: string
  bytes?: string
}

interface RgSubmatch {
  match: RgText
  start: number
  end: number
}

interface RgMatchData {
  path: RgText
  lines: RgText
  line_number: number
  submatches: RgSubmatch[]
}

export const getText = (input: RgText): string => {
  return input.text !== undefined ? input.text : Buffer.from(input.bytes ?? '', 'base64').toString()
}

const cleanResultLine = (resultLine: RgText): string => {
  const text = getText(resultLine)
  return text[text.length - 1] === '\n' ? text.slice(0, -1) : text
}

const getPositionFromColumn = (lines: string[], column: number): [number, number] => {
  let currentLength = 0
  let currentLine = 0
  let previousLength = 0

  while (column >= currentLength) {
    previousLength = currentLength
    currentLength += lines[currentLine].length + 1
    currentLine++
  }

  return [currentLine - 1, column - previousLength]
}

/**
 * Convert byte offsets from ripgrep into character positions for lines
 * containing multi-byte characters. Mutates the submatches in place.
 */
export const processUnicodeMatch = (match: RgMatchData): void => {
  const text = getText(match.lines)
  if (text.length === Buffer.byteLength(text)) {
    return
  }

  let remainingBuffer = Buffer.from(text)
  let currentLength = 0
  let previousPosition = 0

  const convertPosition = (position: number): number => {
    const currentBuffer = remainingBuffer.slice(0, position - previousPosition)
    currentLength = currentBuffer.toString().length + currentLength
    remainingBuffer = remainingBuffer.slice(position - previousPosition)
    previousPosition = position
    return currentLength
  }

  for (const submatch of match.submatches) {
    submatch.start = convertPosition(submatch.start)
    submatch.end = convertPosition(submatch.end)
  }
}

/**
 * Build the range/lineText pair for one submatch (handles multi-line
 * matches by offsetting rows).
 */
export const processSubmatch = (
  submatch: RgSubmatch,
  lineText: string,
  offsetRow: number,
): { range: [[number, number], [number, number]]; lineText: string } => {
  const lineParts = lineText.split('\n')

  const start = getPositionFromColumn(lineParts, submatch.start)
  const end = getPositionFromColumn(lineParts, submatch.end)

  for (let i = start[0]; i > 0; i--) {
    lineParts.shift()
  }
  while (end[0] < lineParts.length - 1) {
    lineParts.pop()
  }

  start[0] += offsetRow
  end[0] += offsetRow

  return {
    range: [start, end],
    lineText: cleanResultLine({ text: lineParts.join('\n') }),
  }
}

export interface ParsedFileResult {
  filePath: string
  matches: ContentSearchMatch[]
}

/**
 * Incremental parser for `rg --json` stdout. Feed chunks, receive complete
 * per-file results through the callback.
 */
export class RipgrepJsonParser {
  private _buffer = ''
  private _pendingEvent: ParsedFileResult | null = null
  private _pendingLeadingContext: string[] = []
  private readonly _onFileResult: (result: ParsedFileResult) => void

  constructor(onFileResult: (result: ParsedFileResult) => void) {
    this._onFileResult = onFileResult
  }

  push(chunk: string): void {
    this._buffer += chunk
    const lines = this._buffer.split('\n')
    this._buffer = lines.pop() ?? ''
    for (const line of lines) {
      if (!line) {
        continue
      }
      let message: { type: string; data: RgMatchData }
      try {
        message = JSON.parse(line)
      } catch (_error) {
        continue // tolerate partial/garbage lines rather than dropping the search
      }
      if (message.type === 'begin') {
        this._pendingEvent = {
          filePath: getText(message.data.path),
          matches: [],
        }
        this._pendingLeadingContext = []
      } else if (message.type === 'match' && this._pendingEvent) {
        processUnicodeMatch(message.data)
        for (const submatch of message.data.submatches) {
          const { lineText, range } = processSubmatch(
            submatch,
            getText(message.data.lines),
            message.data.line_number - 1,
          )
          this._pendingEvent.matches.push({
            matchText: getText(submatch.match),
            lineText,
            range,
            leadingContextLines: [...this._pendingLeadingContext],
            trailingContextLines: [],
          })
        }
      } else if (message.type === 'end' && this._pendingEvent) {
        this._onFileResult(this._pendingEvent)
        this._pendingEvent = null
      }
    }
  }
}

/**
 * Normalize user-supplied globs the way the Atom searcher did (e.g. `src/`
 * means `**​/src/**`).
 */
export const prepareGlobs = (globs: readonly string[] | undefined, projectRootPath: string): string[] => {
  const output: string[] = []

  for (let pattern of globs ?? []) {
    pattern = pattern.replace(new RegExp(`\\${path.sep}`, 'g'), '/')
    if (pattern.length === 0) {
      continue
    }

    const projectName = path.basename(projectRootPath)
    if (pattern === projectName) {
      output.push('**/*')
      continue
    }
    if (pattern.startsWith(`${projectName}/`)) {
      pattern = pattern.slice(projectName.length + 1)
    }
    if (pattern.endsWith('/')) {
      pattern = pattern.slice(0, -1)
    }
    pattern = pattern.startsWith('**/') ? pattern : `**/${pattern}`
    output.push(pattern)
    output.push(pattern.endsWith('/**') ? pattern : `${pattern}/**`)
  }

  return output
}

export const prepareRegexp = (regexpStr: string): string => {
  if (regexpStr === '--') {
    return '\\-\\-'
  }
  // ripgrep rejects unnecessarily escaped sequences:
  // https://github.com/BurntSushi/ripgrep/issues/434
  return regexpStr.replace(/\\\//g, '/')
}

export const isMultilineRegexp = (regexpStr: string): boolean => {
  return regexpStr.includes('\\n')
}
