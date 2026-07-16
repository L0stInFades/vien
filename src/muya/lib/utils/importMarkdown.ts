/**
 * translate markdown format to content state used by MarkText
 * there is some difference when parse loose list item and tight lsit item.
 * Both of them add a p block in li block, use the CSS style to distinguish loose and tight.
 */
import { tokenizer } from '../parser'
import { beginRules } from '../parser/rules'
import { getImageInfo } from '../utils'
import { Lexer } from '../parser/marked'
import ExportMarkdown from './exportMarkdown'
import TurndownService, { usePluginAddRules } from './turndownService'
import type { IContentState, Block, CursorPosition } from '../types'

/**
 * Extended content state interface for methods added by mixin files
 * that aren't explicitly typed in the base IContentState interface.
 */
interface ContentStateInstance extends IContentState {
  cursor: { start: CursorPosition; end: CursorPosition; anchor: CursorPosition; focus: CursorPosition }
  isGitlabCompatibilityEnabled: boolean
  listIndentation: number
  createContainerBlock: (type: string, value: string, mathStyle?: string) => Block
  createHtmlBlock: (text: string) => Block
  markdownToState: (markdown: string) => Block[]
  htmlToMarkdown: (html: string, keeps?: string[]) => string
}

// To be disabled rules when parse markdown, Because content state don't need to parse inline rules
import { CURSOR_ANCHOR_DNA, CURSOR_FOCUS_DNA } from '../config'

const languageLoaded = new Set()
let prismModulePromise: Promise<typeof import('../prism/index')> | null = null

const getPrismModule = () => {
  prismModulePromise ??= import('../prism/index')
  return prismModulePromise
}

const collectReferenceLabels = (blocks: Block[]) => {
  const labels = new Map<string, { href: string; title: string }>()

  const travel = (block: Block) => {
    const { text, children } = block
    if (children?.length) {
      children.forEach((child: Block) => {
        travel(child)
      })
      return
    }

    if (!text) {
      return
    }

    const tokens = beginRules.reference_definition.exec(text)
    if (!tokens) {
      return
    }

    const key = (tokens[2] + tokens[3]).toLowerCase()
    if (!labels.has(key)) {
      labels.set(key, {
        href: tokens[6],
        title: tokens[10] || '',
      })
    }
  }

  blocks.forEach((block) => {
    travel(block)
  })

  return labels
}

// Just because turndown change `\n`(soft line break) to space, So we add `span.ag-soft-line-break` to workaround.
const turnSoftBreakToSpan = (html: string) => {
  const parser = new DOMParser()
  const doc = parser.parseFromString(`<x-mt id="turn-root">${html}</x-mt>`, 'text/html')
  const root = doc.querySelector('#turn-root')
  const travel = (childNodes: NodeListOf<ChildNode>) => {
    for (const node of childNodes) {
      if (node.nodeType === 3 && (node.parentNode as HTMLElement).tagName !== 'CODE') {
        let startLen = 0
        let endLen = 0
        const text = node
          .nodeValue!.replace(/^(\n+)/, (_: string, p: string) => {
            startLen = p.length
            return ''
          })
          .replace(/(\n+)$/, (_: string, p: string) => {
            endLen = p.length
            return ''
          })
        if (/\n/.test(text)) {
          const tokens = text.split('\n')
          const params: Node[] = []
          let i = 0
          const len = tokens.length
          for (; i < len; i++) {
            let text = tokens[i]
            if (i === 0 && startLen !== 0) {
              text = '\n'.repeat(startLen) + text
            } else if (i === len - 1 && endLen !== 0) {
              text = text + '\n'.repeat(endLen)
            }
            params.push(document.createTextNode(text))
            if (i !== len - 1) {
              const softBreak = document.createElement('span')
              softBreak.classList.add('ag-soft-line-break')
              params.push(softBreak)
            }
          }
          node.replaceWith(...params)
        }
      } else if (node.nodeType === 1) {
        travel((node as HTMLElement).childNodes)
      }
    }
  }
  travel(root!.childNodes)
  return root!.innerHTML.trim()
}

// biome-ignore lint/suspicious/noExplicitAny: ContentState constructor lacks type declarations; used as mixin target
const importRegister = (ContentState: any) => {
  // turn markdown to blocks
  ContentState.prototype.markdownToState = function (this: ContentStateInstance, markdown: string) {
    // mock a root block...
    const rootState: Block = {
      key: '',
      type: 'root',
      text: '',
      editable: false,
      parent: null,
      preSibling: null,
      nextSibling: null,
      children: [],
    }
    const { footnote, isGitlabCompatibilityEnabled, superSubScript, trimUnnecessaryCodeBlockEmptyLines } =
      this.muya.options

    // biome-ignore lint/suspicious/noExplicitAny: Lexer tokens are dynamically shaped with .type, .text, etc.
    const tokens: any[] = new (
      Lexer as unknown as new (
        opts: Record<string, unknown>,
      ) => { lex(src: string): unknown[] }
    )({
      disableInline: true,
      footnote,
      isGitlabCompatibilityEnabled,
      superSubScript,
    }).lex(markdown)

    // biome-ignore lint/suspicious/noExplicitAny: lexer tokens are dynamically typed
    let token: any
    let block: Block
    let value: string
    const parentList: Block[] = [rootState]

    token = tokens.shift()
    while (token) {
      switch (token.type) {
        case 'frontmatter': {
          const { lang, style } = token
          value = token.text.replace(/^\s+/, '').replace(/\s$/, '')
          block = this.createBlock('pre', {
            functionType: token.type,
            lang,
            style,
          })

          const codeBlock = this.createBlock('code', {
            lang,
          })

          const codeContent = this.createBlock('span', {
            text: value,
            lang,
            functionType: 'codeContent',
          })

          this.appendChild(codeBlock, codeContent)
          this.appendChild(block, codeBlock)
          this.appendChild(parentList[0], block)
          break
        }

        case 'hr': {
          value = token.marker
          block = this.createBlock('hr')
          const thematicBreakContent = this.createBlock('span', {
            text: value,
            functionType: 'thematicBreakLine',
          })
          this.appendChild(block, thematicBreakContent)
          this.appendChild(parentList[0], block)
          break
        }

        case 'heading': {
          const { headingStyle, depth, text, marker } = token
          value = headingStyle === 'atx' ? `${'#'.repeat(+depth)} ${text}` : text
          block = this.createBlock(`h${depth}`, {
            headingStyle,
          })

          const headingContent = this.createBlock('span', {
            text: value,
            functionType: headingStyle === 'atx' ? 'atxLine' : 'paragraphContent',
          })

          this.appendChild(block, headingContent)

          if (marker) {
            block.marker = marker
          }

          if (headingStyle === 'atx' && token.closedAtxSuffix) {
            // Original closing-hash sequence (ADR-001 lossless round-trip).
            block.closedAtxSuffix = token.closedAtxSuffix
          }

          this.appendChild(parentList[0], block)
          break
        }

        case 'multiplemath': {
          value = token.text
          block = this.createContainerBlock(token.type, value, token.mathStyle)
          this.appendChild(parentList[0], block)
          break
        }

        case 'code': {
          const { codeBlockStyle, text, lang: infostring = '' } = token

          // GH#697, markedjs#1387
          const lang = (infostring || '').match(/\S*/)[0]

          value = text
          // Fix: #1265.
          if (trimUnnecessaryCodeBlockEmptyLines && (value.endsWith('\n') || value.startsWith('\n'))) {
            value = value.replace(/\n+$/, '').replace(/^\n+/, '')
          }
          if (/mermaid|flowchart|vega-lite|sequence|plantuml/.test(lang)) {
            block = this.createContainerBlock(lang, value)
            this.appendChild(parentList[0], block)
          } else {
            block = this.createBlock('pre', {
              functionType: codeBlockStyle === 'fenced' ? 'fencecode' : 'indentcode',
              lang,
            })
            if (codeBlockStyle === 'fenced' && token.fenceMarker) {
              // Original fence opener, e.g. "~~~" or "````" (ADR-001).
              block.fenceMarker = token.fenceMarker
            }
            const codeBlock = this.createBlock('code', {
              lang,
            })
            const codeContent = this.createBlock('span', {
              text: value,
              lang,
              functionType: 'codeContent',
            })
            const inputBlock = this.createBlock('span', {
              text: lang,
              functionType: 'languageInput',
            })
            if (lang && !languageLoaded.has(lang)) {
              languageLoaded.add(lang)
              getPrismModule()
                .then(({ loadLanguage }) => loadLanguage(lang))
                .then((infoList) => {
                  if (!Array.isArray(infoList)) return
                  // There are three status `loaded`, `noexist` and `cached`.
                  // if the status is `loaded`, indicated that it's a new loaded language
                  const needRender = infoList.some(({ status }) => status === 'loaded')
                  if (needRender) {
                    this.render()
                  }
                })
                .catch((err) => {
                  // if no parameter provided, will cause error.
                  console.warn(err)
                })
            }

            this.appendChild(codeBlock, codeContent)
            this.appendChild(block, inputBlock)
            this.appendChild(block, codeBlock)
            this.appendChild(parentList[0], block)
          }
          break
        }

        case 'table': {
          const { header, align, cells } = token
          const table = this.createBlock('table')
          const thead = this.createBlock('thead')
          const tbody = this.createBlock('tbody')
          const theadRow = this.createBlock('tr')
          const restoreTableEscapeCharacters = (text: string) => {
            // NOTE: markedjs replaces all escaped "|" ("\|") characters inside a cell with "|".
            //       We have to re-escape the chraracter to not break the table.
            return text.replace(/\|/g, '\\|')
          }
          let i: number
          let j: number
          const headerLen = header.length
          for (i = 0; i < headerLen; i++) {
            const headText = header[i]
            const th = this.createBlock('th', {
              align: align[i] || '',
              column: i,
            })
            const cellContent = this.createBlock('span', {
              text: restoreTableEscapeCharacters(headText),
              functionType: 'cellContent',
            })
            this.appendChild(th, cellContent)
            this.appendChild(theadRow, th)
          }
          const rowLen = cells.length
          for (i = 0; i < rowLen; i++) {
            const rowBlock = this.createBlock('tr')
            const rowContents = cells[i]
            const colLen = rowContents.length
            for (j = 0; j < colLen; j++) {
              const cell = rowContents[j]
              const td = this.createBlock('td', {
                align: align[j] || '',
                column: j,
              })
              const cellContent = this.createBlock('span', {
                text: restoreTableEscapeCharacters(cell),
                functionType: 'cellContent',
              })

              this.appendChild(td, cellContent)
              this.appendChild(rowBlock, td)
            }
            this.appendChild(tbody, rowBlock)
          }

          Object.assign(table, { row: cells.length, column: header.length - 1 }) // set row and column
          block = this.createBlock('figure')
          block.functionType = 'table'
          this.appendChild(thead, theadRow)
          this.appendChild(block, table)
          this.appendChild(table, thead)
          if (tbody.children.length) {
            this.appendChild(table, tbody)
          }
          this.appendChild(parentList[0], block)
          break
        }

        case 'html': {
          const text = token.text.trim()
          // TODO: Treat html block which only contains one img as paragraph, we maybe add image block in the future.
          const isSingleImage = /^<img[^<>]+>$/.test(text)
          if (isSingleImage) {
            block = this.createBlock('p')
            const contentBlock = this.createBlock('span', {
              text,
            })
            this.appendChild(block, contentBlock)
            this.appendChild(parentList[0], block)
          } else {
            block = this.createHtmlBlock(text)
            this.appendChild(parentList[0], block)
          }
          break
        }

        case 'text': {
          value = token.text
          while (tokens[0] && tokens[0].type === 'text') {
            token = tokens.shift()
            value += `\n${token.text}`
          }
          block = this.createBlock('p')
          const contentBlock = this.createBlock('span', {
            text: value,
          })
          this.appendChild(block, contentBlock)
          this.appendChild(parentList[0], block)
          break
        }

        case 'toc':
        case 'paragraph': {
          value = token.text
          block = this.createBlock('p')
          const contentBlock = this.createBlock('span', {
            text: value,
          })
          this.appendChild(block, contentBlock)
          this.appendChild(parentList[0], block)
          break
        }

        case 'blockquote_start': {
          block = this.createBlock('blockquote')
          this.appendChild(parentList[0], block)
          parentList.unshift(block)
          break
        }

        case 'blockquote_end': {
          // Fix #1735 the blockquote maybe empty.
          if (parentList[0].children.length === 0) {
            const paragraphBlock = this.createBlockP()
            this.appendChild(parentList[0], paragraphBlock)
          }
          parentList.shift()
          break
        }

        case 'footnote_start': {
          block = this.createBlock('figure', {
            functionType: 'footnote',
          })
          const identifierInput = this.createBlock('span', {
            text: token.identifier,
            functionType: 'footnoteInput',
          })
          this.appendChild(block, identifierInput)
          this.appendChild(parentList[0], block)
          parentList.unshift(block)
          break
        }

        case 'footnote_end': {
          parentList.shift()
          break
        }

        case 'list_start': {
          const { ordered, listType, start } = token
          block = this.createBlock(ordered === true ? 'ol' : 'ul', {
            listType,
          })
          if (token.blankLineBefore === true) {
            // Original blank-line separation between adjacent lists (ADR-001).
            block.precededByBlankLine = true
          }
          block.listType = listType
          if (listType === 'order') {
            block.start = /^\d+$/.test(start) ? start : 1
          }
          this.appendChild(parentList[0], block)
          parentList.unshift(block)
          break
        }

        case 'list_end': {
          parentList.shift()
          break
        }

        case 'loose_item_start':
        case 'list_item_start': {
          const { listItemType, bulletMarkerOrDelimiter, checked, type } = token
          block = this.createBlock('li', {
            listItemType: checked !== undefined ? 'task' : listItemType,
            bulletMarkerOrDelimiter,
            isLooseListItem: type === 'loose_item_start',
          })
          if (typeof token.blankLineBefore === 'boolean') {
            // Source blank-line placement for lossless export (ADR-001).
            block.blankLineBefore = token.blankLineBefore
          }
          if (typeof token.listItemNumber === 'number' && !Number.isNaN(token.listItemNumber)) {
            // Original ordered number for lossless round-trips (ADR-001).
            block.listItemNumber = token.listItemNumber
          }

          if (checked !== undefined) {
            const input = this.createBlock('input', {
              checked,
            })

            this.appendChild(block, input)
          }
          this.appendChild(parentList[0], block)
          parentList.unshift(block)
          break
        }

        case 'list_item_end': {
          parentList.shift()
          break
        }

        case 'space': {
          break
        }

        default:
          console.warn(`Unknown type ${token.type}`)
          break
      }

      token = tokens.shift()
    }

    return rootState.children.length ? rootState.children : [this.createBlockP()]
  }

  ContentState.prototype.htmlToMarkdown = function (this: ContentStateInstance, html: string, keeps: string[] = []) {
    // turn html to markdown
    const { turndownConfig } = this
    const turndownService = new TurndownService(turndownConfig as Record<string, unknown>)
    usePluginAddRules(turndownService, keeps)

    // fix #752, but I don't know why the &nbsp; vanlished.
    html = html.replace(/<span>&nbsp;<\/span>/g, String.fromCharCode(160))

    html = turnSoftBreakToSpan(html)
    const markdown = turndownService.turndown(html)

    return markdown
  }

  // turn html to blocks
  ContentState.prototype.html2State = function (this: ContentStateInstance, html: string) {
    const markdown = this.htmlToMarkdown(html, ['ruby', 'rt', 'u', 'br'])
    return this.markdownToState(markdown)
  }

  ContentState.prototype.getCodeMirrorCursor = function (this: ContentStateInstance) {
    const blocks = this.getBlocks()
    const { anchor, focus } = this.cursor
    const anchorBlock = this.getBlock(anchor.key)!
    const focusBlock = this.getBlock(focus.key)!
    const { text: anchorText } = anchorBlock
    const { text: focusText } = focusBlock
    if (anchor.key === focus.key) {
      const minOffset = Math.min(anchor.offset, focus.offset)
      const maxOffset = Math.max(anchor.offset, focus.offset)
      const firstTextPart = anchorText.substring(0, minOffset)
      const secondTextPart = anchorText.substring(minOffset, maxOffset)
      const thirdTextPart = anchorText.substring(maxOffset)
      anchorBlock.text =
        firstTextPart +
        (anchor.offset <= focus.offset ? CURSOR_ANCHOR_DNA : CURSOR_FOCUS_DNA) +
        secondTextPart +
        (anchor.offset <= focus.offset ? CURSOR_FOCUS_DNA : CURSOR_ANCHOR_DNA) +
        thirdTextPart
    } else {
      anchorBlock.text =
        anchorText.substring(0, anchor.offset) + CURSOR_ANCHOR_DNA + anchorText.substring(anchor.offset)
      focusBlock.text = focusText.substring(0, focus.offset) + CURSOR_FOCUS_DNA + focusText.substring(focus.offset)
    }

    const { isGitlabCompatibilityEnabled, listIndentation } = this
    const markdown = new ExportMarkdown(blocks, listIndentation, isGitlabCompatibilityEnabled).generate()
    const cmCursor = markdown.split('\n').reduce(
      (
        acc: { anchor: { line: number; ch: number }; focus: { line: number; ch: number } },
        line: string,
        index: number,
      ) => {
        const ach = line.indexOf(CURSOR_ANCHOR_DNA)
        const fch = line.indexOf(CURSOR_FOCUS_DNA)
        if (ach > -1 && fch > -1) {
          if (ach <= fch) {
            Object.assign(acc.anchor, { line: index, ch: ach })
            Object.assign(acc.focus, { line: index, ch: fch - CURSOR_ANCHOR_DNA.length })
          } else {
            Object.assign(acc.focus, { line: index, ch: fch })
            Object.assign(acc.anchor, { line: index, ch: ach - CURSOR_FOCUS_DNA.length })
          }
        } else if (ach > -1) {
          Object.assign(acc.anchor, { line: index, ch: ach })
        } else if (fch > -1) {
          Object.assign(acc.focus, { line: index, ch: fch })
        }
        return acc
      },
      {
        anchor: {
          line: 0,
          ch: 0,
        },
        focus: {
          line: 0,
          ch: 0,
        },
      },
    )
    // remove CURSOR_FOCUS_DNA and CURSOR_ANCHOR_DNA
    anchorBlock.text = anchorText
    focusBlock.text = focusText
    return cmCursor
  }

  ContentState.prototype.addCursorToMarkdown = (
    markdown: string,
    cmCursorArg: { anchor: { line: number; ch: number }; focus: { line: number; ch: number } },
  ) => {
    const { anchor, focus } = cmCursorArg
    if (!anchor || !focus) {
      return
    }
    const lines = markdown.split('\n')
    const anchorText = lines[anchor.line]
    const focusText = lines[focus.line]
    if (!anchorText || !focusText) {
      return {
        markdown: lines.join('\n'),
        isValid: false,
      }
    }
    if (anchor.line === focus.line) {
      const minOffset = Math.min(anchor.ch, focus.ch)
      const maxOffset = Math.max(anchor.ch, focus.ch)
      const firstTextPart = anchorText.substring(0, minOffset)
      const secondTextPart = anchorText.substring(minOffset, maxOffset)
      const thirdTextPart = anchorText.substring(maxOffset)
      lines[anchor.line] =
        firstTextPart +
        (anchor.ch <= focus.ch ? CURSOR_ANCHOR_DNA : CURSOR_FOCUS_DNA) +
        secondTextPart +
        (anchor.ch <= focus.ch ? CURSOR_FOCUS_DNA : CURSOR_ANCHOR_DNA) +
        thirdTextPart
    } else {
      lines[anchor.line] = anchorText.substring(0, anchor.ch) + CURSOR_ANCHOR_DNA + anchorText.substring(anchor.ch)
      lines[focus.line] = focusText.substring(0, focus.ch) + CURSOR_FOCUS_DNA + focusText.substring(focus.ch)
    }

    return {
      markdown: lines.join('\n'),
      isValid: true,
    }
  }

  ContentState.prototype.importCursor = function (this: ContentStateInstance, hasCursor: boolean) {
    // set cursor
    const cursor: { anchor: CursorPosition | null; focus: CursorPosition | null } = {
      anchor: null,
      focus: null,
    }

    let count = 0

    const travel = (blocks: Block[]) => {
      for (const block of blocks) {
        let { key, text, children, editable } = block
        if (text) {
          const offset = text.indexOf(CURSOR_ANCHOR_DNA)
          if (offset > -1) {
            block.text = text.substring(0, offset) + text.substring(offset + CURSOR_ANCHOR_DNA.length)
            text = block.text
            count++
            if (editable) {
              cursor.anchor = { key, offset }
            }
          }
          const focusOffset = text.indexOf(CURSOR_FOCUS_DNA)
          if (focusOffset > -1) {
            block.text = text.substring(0, focusOffset) + text.substring(focusOffset + CURSOR_FOCUS_DNA.length)
            count++
            if (editable) {
              cursor.focus = { key, offset: focusOffset }
            }
          }
          if (count === 2) {
            break
          }
        } else if (children.length) {
          travel(children)
        }
      }
    }
    if (hasCursor) {
      travel(this.blocks)
    } else {
      const lastBlock = this.getLastBlock()!
      const key = lastBlock.key
      const offset = lastBlock.text.length
      cursor.anchor = { key, offset }
      cursor.focus = { key, offset }
    }
    if (cursor.anchor && cursor.focus) {
      this.cursor = { start: cursor.anchor, end: cursor.focus, anchor: cursor.anchor, focus: cursor.focus }
    }
  }

  ContentState.prototype.importMarkdown = function (this: ContentStateInstance, markdown: string) {
    this.blocks = this.markdownToState(markdown)
  }

  ContentState.prototype.extractImages = function (this: ContentStateInstance, markdown: string) {
    const results = new Set<string>()
    const blocks = this.markdownToState(markdown)
    const labels = collectReferenceLabels(blocks)

    interface InlineToken {
      type: string
      attrs?: { src?: string }
      children?: InlineToken[]
      tag?: string
      label?: string
      backlash?: { second: string }
    }

    const travelToken = (token: InlineToken) => {
      const { type, attrs, children, tag, label, backlash } = token
      if (/reference_image|image/.test(type) || (type === 'html_tag' && tag === 'img')) {
        if ((type === 'image' || type === 'html_tag') && attrs?.src) {
          results.add(attrs.src)
        } else {
          const rawSrc = label! + backlash!.second
          if (labels.has(rawSrc.toLowerCase())) {
            const { href } = labels.get(rawSrc.toLowerCase())!
            const { src } = getImageInfo(href)
            if (src) {
              results.add(src)
            }
          }
        }
      } else if (children?.length) {
        for (const child of children) {
          travelToken(child)
        }
      }
    }

    const travel = (block: Block) => {
      const { text, children, type, functionType } = block
      if (children.length) {
        for (const b of children) {
          travel(b)
        }
      } else if (text && type === 'span' && /paragraphContent|atxLine|cellContent/.test(functionType as string)) {
        const tokens = tokenizer(text, {
          highlights: [],
          hasBeginRules: false,
          labels,
        }) as unknown as InlineToken[]
        for (const token of tokens) {
          travelToken(token)
        }
      }
    }

    for (const block of blocks) {
      travel(block)
    }

    return Array.from(results)
  }
}

export default importRegister
