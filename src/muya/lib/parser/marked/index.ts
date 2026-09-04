import Renderer from './renderer'
import Lexer from './lexer'
import Parser from './parser'
import options from './options'
// biome-ignore lint/suspicious/noShadowRestrictedNames: intentional import naming
import { escape } from './utils'

/**
 * Marked
 */

function marked(src: string, opt: Record<string, unknown> = {}) {
  // throw error in case of non string input
  if (typeof src === 'undefined' || src === null) {
    throw new Error('marked(): input parameter is undefined or null')
  }
  if (typeof src !== 'string') {
    throw new Error(`marked(): input parameter is of type ${Object.prototype.toString.call(src)}, string expected`)
  }

  try {
    opt = Object.assign({}, options, opt)
    return new (Parser as unknown as new (opt: Record<string, unknown>) => { parse(src: unknown): string })(opt).parse(
      new (Lexer as unknown as new (opt: Record<string, unknown>) => { lex(src: string): unknown })(opt).lex(src),
    )
  } catch (e) {
    ;(e as Error).message += '\nPlease report this to https://github.com/L0stInFades/vien/issues.'
    if (opt.silent) {
      return `<p>An error occurred:</p><pre>${escape(`${(e as Error).message}`, true)}</pre>`
    }
    throw e
  }
}

export { Renderer, Lexer, Parser }

export default marked
