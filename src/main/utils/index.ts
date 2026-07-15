import { app } from 'electron'

const ID_PREFIX = 'mt-'
let id = 0

export const getUniqueId = (): string => {
  return `${ID_PREFIX}${id++}`
}

export const getRecommendTitleFromMarkdownString = (markdown: string): string => {
  const tokens = markdown.match(/#{1,6} {1,}(.*\S.*)(?:\n|$)/g)
  if (!tokens) return ''
  const headers = tokens.map((t) => {
    const matches = t.trim().match(/(#{1,6}) {1,}(.+)/)!
    return {
      level: matches[1].length,
      content: matches[2].trim(),
    }
  })
  return headers.sort((a, b) => a.level - b.level)[0].content
}

export const getPath = (name: string): string => {
  if (name === 'userData') {
    throw new Error('Do not use "getPath" for user data path!')
  }
  return app.getPath(name as Parameters<typeof app.getPath>[0])
}

export const hasSameKeys = (a: Record<string, unknown>, b: Record<string, unknown>): boolean => {
  const aKeys = Object.keys(a).sort()
  const bKeys = Object.keys(b).sort()
  return JSON.stringify(aKeys) === JSON.stringify(bKeys)
}

type LogLevel = 'info' | 'debug' | 'verbose' | 'silly'

export const getLogLevel = (): LogLevel => {
  if (
    !(global as unknown as { MARKTEXT_DEBUG_VERBOSE: unknown }).MARKTEXT_DEBUG_VERBOSE ||
    typeof (global as unknown as { MARKTEXT_DEBUG_VERBOSE: unknown }).MARKTEXT_DEBUG_VERBOSE !== 'number' ||
    (global as unknown as { MARKTEXT_DEBUG_VERBOSE: number }).MARKTEXT_DEBUG_VERBOSE <= 0
  ) {
    return process.env.NODE_ENV === 'development' ? 'debug' : 'info'
  } else if ((global as unknown as { MARKTEXT_DEBUG_VERBOSE: number }).MARKTEXT_DEBUG_VERBOSE === 1) {
    return 'verbose'
  } else if ((global as unknown as { MARKTEXT_DEBUG_VERBOSE: number }).MARKTEXT_DEBUG_VERBOSE === 2) {
    return 'debug'
  }
  return 'silly' // >= 3
}
