import katex from 'katex'
import prism from '../../../prism/runtime'
import { loadedLanguages, transformAliasToOrigin } from '../../../prism/metadata'
import 'katex/dist/contrib/mhchem.min.js'
import { CLASS_OR_ID, DEVICE_MEMORY, PREVIEW_DOMPURIFY_CONFIG, HAS_TEXT_BLOCK_REG } from '../../../config'
import type { Block } from '../../types'
import { tokenizer } from '../../'
import { snakeToCamel, sanitize, escapeHTML, getLongUniqueId, getImageInfo } from '../../../utils'
import { h, htmlToVNode } from '../snabbdom'
import type { StateRenderContext, HighlightRange } from '../renderContext'

// todo@jocs any better solutions?
const MARKER_HASK = {
  '<': `%${getLongUniqueId()}%`,
  '>': `%${getLongUniqueId()}%`,
  '"': `%${getLongUniqueId()}%`,
  "'": `%${getLongUniqueId()}%`,
}

const getHighlightHtml = (
  text: string,
  highlights: { start: number; end: number; active: boolean }[],
  shouldEscape = false,
  handleLineEnding = false,
) => {
  let code = ''
  let pos = 0
  const getEscapeHTML = (className: string, content: string) => {
    return `${MARKER_HASK['<']}span class=${MARKER_HASK['"']}${className}${MARKER_HASK['"']}${MARKER_HASK['>']}${content}${MARKER_HASK['<']}/span${MARKER_HASK['>']}`
  }

  for (const highlight of highlights) {
    const { start, end, active } = highlight
    code += text.substring(pos, start)
    const className = active ? 'ag-highlight' : 'ag-selection'
    let highlightContent = text.substring(start, end)
    if (handleLineEnding && text.endsWith('\n') && end === text.length) {
      highlightContent =
        highlightContent.substring(start, end - 1) +
        (shouldEscape ? getEscapeHTML('ag-line-end', '\n') : '<span class="ag-line-end">\n</span>')
    }
    code += shouldEscape
      ? getEscapeHTML(className, highlightContent)
      : `<span class="${className}">${highlightContent}</span>`
    pos = end
  }
  if (pos !== text.length) {
    if (handleLineEnding && text.endsWith('\n')) {
      code +=
        text.substring(pos, text.length - 1) +
        (shouldEscape ? getEscapeHTML('ag-line-end', '\n') : '<span class="ag-line-end">\n</span>')
    } else {
      code += text.substring(pos)
    }
  }
  return escapeHTML(code)
}

const hasReferenceToken = (tokens: Record<string, unknown>[]) => {
  let result = false
  const travel = (tokens: Record<string, unknown>[]) => {
    for (const token of tokens) {
      if (/reference_image|reference_link/.test(token.type as string)) {
        result = true
        break
      }
      if (Array.isArray(token.children) && token.children.length) {
        travel(token.children)
      }
    }
  }
  travel(tokens)
  return result
}

export default function renderLeafBlock(
  this: StateRenderContext,
  _parent: Block | null,
  block: Block,
  activeBlocks: Block[],
  matches: HighlightRange[],
  useCache = false,
) {
  const { loadMathMap } = this
  const { cursor } = this.muya.contentState
  let selector = this.getSelector(block, activeBlocks)
  // highlight search key in block
  const highlights = matches.filter((m) => m.key === block.key)
  const { text, type, checked, key, lang, functionType, editable } = block

  const data = {
    props: {},
    attrs: {},
    dataset: {},
    style: {},
  }

  // biome-ignore lint/suspicious/noExplicitAny: children is reassigned to arrays/strings/VNodes throughout
  let children: any = ''

  if (text) {
    let tokens: Record<string, unknown>[] = []
    if (highlights.length === 0 && this.tokenCache.has(text)) {
      tokens = this.tokenCache.get(text) ?? []
    } else if (HAS_TEXT_BLOCK_REG.test(type) && functionType !== 'codeContent' && functionType !== 'languageInput') {
      const hasBeginRules = /paragraphContent|atxLine/.test(functionType as string)

      tokens = tokenizer(text, {
        highlights,
        hasBeginRules,
        labels: this.labels,
        options: this.muya.options,
      })
      const hasReferenceTokens = hasReferenceToken(tokens)
      if (highlights.length === 0 && useCache && DEVICE_MEMORY >= 4 && !hasReferenceTokens) {
        this.tokenCache.set(text, tokens)
      }
    }
    children = []
    for (const token of tokens) {
      const renderer = this[snakeToCamel(token.type as string)]
      if (typeof renderer !== 'function') {
        continue
      }
      const result = renderer.call(this, h, cursor, block, token)
      if (Array.isArray(result)) {
        children.push(...result)
      } else {
        children.push(result)
      }
    }
  }

  if (editable === false) {
    Object.assign(data.attrs, {
      spellcheck: 'false',
      contenteditable: 'false',
    })
  }

  if (type === 'div') {
    const code = this.codeCache.get(block.preSibling as string) ?? ''
    switch (functionType) {
      case 'html': {
        selector += `.${CLASS_OR_ID.AG_HTML_PREVIEW}`
        Object.assign(data.attrs, { spellcheck: 'false' })

        const disableHtml = (this.muya.options.disableHtml ?? false) as boolean
        const htmlContent = sanitize(code, PREVIEW_DOMPURIFY_CONFIG, disableHtml)

        // handle empty html bock
        if (/^<([a-z][a-z\d]*)[^>]*?>(\s*)<\/\1>$/.test(htmlContent.trim())) {
          children = htmlToVNode('<div class="ag-empty">&lt;Empty HTML Block&gt;</div>')
        } else {
          const parser = new DOMParser()
          const doc = parser.parseFromString(htmlContent, 'text/html')
          const imgs = doc.documentElement.querySelectorAll('img')
          for (const img of imgs) {
            const src = img.getAttribute('src') ?? ''
            const imageInfo = getImageInfo(src)
            img.setAttribute('src', imageInfo.src)
          }

          children = htmlToVNode(doc.documentElement.querySelector('body')!.innerHTML)
        }
        break
      }
      case 'multiplemath': {
        const key = `${code}_display_math`
        selector += `.${CLASS_OR_ID.AG_CONTAINER_PREVIEW}`
        Object.assign(data.attrs, { spellcheck: 'false' })
        if (code === '') {
          children = '< Empty Mathematical Formula >'
          selector += `.${CLASS_OR_ID.AG_EMPTY}`
        } else if (loadMathMap.has(key)) {
          children = loadMathMap.get(key) as string
        } else {
          try {
            const html = katex.renderToString(code, {
              displayMode: true,
            })

            children = htmlToVNode(html)
            loadMathMap.set(key, children)
          } catch (_err) {
            children = '< Invalid Mathematical Formula >'
            selector += `.${CLASS_OR_ID.AG_MATH_ERROR}`
          }
        }
        break
      }
      case 'mermaid': {
        selector += `.${CLASS_OR_ID.AG_CONTAINER_PREVIEW}`
        Object.assign(data.attrs, { spellcheck: 'false' })
        if (code === '') {
          children = '< Empty Mermaid Block >'
          selector += `.${CLASS_OR_ID.AG_EMPTY}`
        } else {
          children = 'Loading...'
          this.mermaidCache.set(`#${block.key}`, {
            code,
            functionType: functionType as string,
          })
        }
        break
      }
      case 'flowchart':
      case 'sequence':
      case 'plantuml':
      case 'vega-lite': {
        selector += `.${CLASS_OR_ID.AG_CONTAINER_PREVIEW}`
        Object.assign(data.attrs, { spellcheck: 'false' })
        if (code === '') {
          children = '< Empty Diagram Block >'
          selector += `.${CLASS_OR_ID.AG_EMPTY}`
        } else {
          children = 'Loading...'
          this.diagramCache.set(`#${block.key}`, {
            code,
            functionType: functionType as string,
          })
        }
        break
      }
    }
  } else if (type === 'input') {
    const fontSize = this.muya.options.fontSize as number
    const lineHeight = this.muya.options.lineHeight as number

    Object.assign(data.attrs, {
      type: 'checkbox',
      style: `top: ${((fontSize * lineHeight) / 2 - 8).toFixed(2)}px`,
    })

    selector = `${type}#${key}.${CLASS_OR_ID.AG_TASK_LIST_ITEM_CHECKBOX}`
    if (checked) {
      Object.assign(data.attrs, {
        checked: true,
      })
      selector += `.${CLASS_OR_ID.AG_CHECKBOX_CHECKED}`
    }
    children = ''
  } else if (type === 'span' && functionType === 'codeContent') {
    const code = getHighlightHtml(text, highlights, true, true)
      .replace(new RegExp(MARKER_HASK['<'], 'g'), '<')
      .replace(new RegExp(MARKER_HASK['>'], 'g'), '>')
      .replace(new RegExp(MARKER_HASK['"'], 'g'), '"')
      .replace(new RegExp(MARKER_HASK["'"], 'g'), "'")

    // transform alias to original language
    const transformedLang = transformAliasToOrigin([lang as string])[0]
    if (transformedLang && /\S/.test(code) && loadedLanguages.has(transformedLang)) {
      const wrapper = document.createElement('div')
      wrapper.classList.add(`language-${transformedLang}`)
      wrapper.innerHTML = code
      prism.highlightElement(wrapper, false, function (this: Element) {
        const highlightedCode = this.innerHTML
        selector += `.language-${transformedLang}`
        children = htmlToVNode(highlightedCode)
      })
    } else {
      children = htmlToVNode(code)
    }
  } else if (type === 'span' && functionType === 'languageInput') {
    const escapedText = sanitize(text, PREVIEW_DOMPURIFY_CONFIG, true)
    const html = getHighlightHtml(escapedText, highlights, true)
    children = htmlToVNode(html)
  } else if (type === 'span' && functionType === 'footnoteInput') {
    Object.assign(data.attrs, { spellcheck: 'false' })
  }

  return h(selector, data, children)
}
