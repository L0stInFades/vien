import type { StateRenderContext, Cursor, InlineRenderMethod } from '../renderContext'
import { CLASS_OR_ID } from '../../../config'
import { snakeToCamel } from '../../../utils'
import { sanitizeHyperlink } from '../../../utils/url'
import type { Block, Token } from '../../types'

export default function referenceLink(
  this: StateRenderContext,
  h: typeof import('snabbdom').h,
  cursor: Cursor,
  block: Block,
  token: Token,
  outerClass: string,
) {
  const className = this.getClassName(outerClass, block, token, cursor)
  const labelClass = className === CLASS_OR_ID.AG_GRAY ? CLASS_OR_ID.AG_REFERENCE_LABEL : className

  const { start, end } = token.range
  const { anchor, children, backlash, isFullLink, label } = token
  const MARKER = '['
  const key = (label + backlash.second).toLowerCase()
  const backlashStart = start + MARKER.length + anchor.length
  const content = children.reduce((acc: unknown[], to: Record<string, unknown>) => {
    const method = this[snakeToCamel(to.type as string)] as InlineRenderMethod
    const chunk = method.call(this, h, cursor, block, to as unknown as Token, className)
    if (Array.isArray(chunk)) {
      acc.push(...chunk)
    } else {
      acc.push(chunk)
    }
    return acc
  }, [])
  content.push(...this.backlashInToken(h, backlash.first, className, backlashStart, token))

  const labelResult = this.labels.get(key)
  const href = labelResult?.href ?? ''
  const title = labelResult?.title ?? ''
  const startMarker = this.highlight(h, block, start, start + MARKER.length, token)
  const endMarker = this.highlight(h, block, start + MARKER.length + anchor.length + backlash.first.length, end, token)
  const anchorSelector = href
    ? `a.${CLASS_OR_ID.AG_INLINE_RULE}.${CLASS_OR_ID.AG_REFERENCE_LINK}`
    : `span.${CLASS_OR_ID.AG_REFERENCE_LINK}`
  const data = {
    attrs: {
      spellcheck: 'false',
    },
    props: {
      title,
    },
    dataset: {
      start: String(start),
      end: String(end),
      raw: token.raw,
    },
  }
  if (href) {
    Object.assign(data.props, { href: sanitizeHyperlink(href) })
  }

  if (isFullLink) {
    const labelContent = this.highlight(
      h,
      block,
      start + 3 * MARKER.length + anchor.length + backlash.first.length,
      end - MARKER.length - backlash.second.length,
      token,
    )
    const middleMarker = this.highlight(
      h,
      block,
      start + MARKER.length + anchor.length + backlash.first.length,
      start + 3 * MARKER.length + anchor.length + backlash.first.length,
      token,
    )
    const lastMarker = this.highlight(h, block, end - MARKER.length, end, token)
    const secondBacklashStart = end - MARKER.length - backlash.second.length

    return [
      h(`span.${className}`, startMarker),
      h(anchorSelector, data, content),
      h(`span.${className}`, middleMarker),
      h(`span.${labelClass}`, labelContent),
      ...this.backlashInToken(h, backlash.second, className, secondBacklashStart, token),
      h(`span.${className}`, lastMarker),
    ]
  } else {
    return [h(`span.${className}`, startMarker), h(anchorSelector, data, content), h(`span.${className}`, endMarker)]
  }
}
