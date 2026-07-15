import { CLASS_OR_ID, BLOCK_TYPE6 } from '../../../config'
import { snakeToCamel } from '../../../utils'
import sanitize, { isValidAttribute } from '../../../utils/dompurify'
import type { Block, Token } from '../../types'
import type { Cursor, InlineRenderMethod, StateRenderContext } from '../renderContext'
import type { VNodeChildElement, VNodeChildren } from 'snabbdom'

export default function htmlTag(
  this: StateRenderContext,
  h: typeof import('snabbdom').h,
  cursor: Cursor,
  block: Block,
  token: Token,
  outerClass: string,
) {
  const { tag, openTag, closeTag, children, attrs } = token
  const className = children ? this.getClassName(outerClass, block, token, cursor) : CLASS_OR_ID.AG_GRAY
  const tagClassName = className === CLASS_OR_ID.AG_HIDE ? className : CLASS_OR_ID.AG_HTML_TAG
  const { start, end } = token.range
  const openContent = this.highlight(h, block, start, start + openTag.length, token)
  const closeContent = closeTag ? this.highlight(h, block, end - closeTag.length, end, token) : ''

  let anchor: VNodeChildren = ''
  if (Array.isArray(children) && tag !== 'ruby') {
    const renderedChildren: VNodeChildElement[] = []
    for (const to of children) {
      const chunk = (this[snakeToCamel(to.type)] as InlineRenderMethod).call(this, h, cursor, block, to, className)
      renderedChildren.push(...chunk)
    }
    anchor = renderedChildren
  }

  switch (tag) {
    // Handle html img.
    case 'img': {
      return this.image(h, cursor, block, token, outerClass)
    }
    case 'br': {
      return [h(`span.${CLASS_OR_ID.AG_HTML_TAG}`, [...openContent, h(tag)])]
    }
    default:
      // handle void html tag
      if (!closeTag) {
        return [h(`span.${CLASS_OR_ID.AG_HTML_TAG}`, openContent)]
      } else if (tag === 'ruby') {
        return this.htmlRuby(h, cursor, block, token, outerClass)
      } else {
        // if  tag is a block level element, use a inline element `span` to instead.
        // Because we can not nest a block level element in span element(line is span element)
        // we also recommand user not use block level element in paragraph. use block element in html block.
        // Use code !sanitize(`<${tag}>`) to filter some malicious tags. for example: <embed>.
        let selector = BLOCK_TYPE6.includes(tag) || !sanitize(`<${tag}>`) ? 'span' : tag
        selector += `.${CLASS_OR_ID.AG_INLINE_RULE}.${CLASS_OR_ID.AG_RAW_HTML}`
        const data = {
          attrs: {} as Record<string, string>,
          dataset: {
            start: String(start),
            end: String(end),
            raw: token.raw,
          },
        }

        // Disable spell checking for these tags
        if (tag === 'code' || tag === 'kbd') {
          Object.assign(data.attrs, { spellcheck: 'false' })
        }

        if (attrs.id) {
          selector += `#${attrs.id}`
        }
        if (attrs.class && /\S/.test(attrs.class)) {
          const classNames = attrs.class.split(/\s+/)
          for (const className of classNames) {
            selector += `.${className}`
          }
        }

        for (const attr of Object.keys(attrs)) {
          if (attr !== 'id' && attr !== 'class') {
            const attrData = attrs[attr]
            if (isValidAttribute(tag, attr, attrData)) {
              data.attrs[attr] = attrData
            }
          }
        }

        return [
          h(
            `span.${tagClassName}.${CLASS_OR_ID.AG_OUTPUT_REMOVE}`,
            {
              attrs: {
                spellcheck: 'false',
              },
            },
            openContent,
          ),
          h(`${selector}`, data, anchor),
          h(
            `span.${tagClassName}.${CLASS_OR_ID.AG_OUTPUT_REMOVE}`,
            {
              attrs: {
                spellcheck: 'false',
              },
            },
            closeContent,
          ),
        ]
      }
  }
}
