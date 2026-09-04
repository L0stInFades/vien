import marked from '../parser/marked'
import Prism from 'prismjs'
import katex from 'katex'
import 'katex/dist/contrib/mhchem.min.js'
import loadRenderer from '../renderers'
import { withMermaidRenderer } from '../renderers/mermaid'
import githubMarkdownCss from 'github-markdown-css/github-markdown.css?inline'
import exportStyle from '../assets/styles/exportStyle.css?inline'
import highlightCss from 'prismjs/themes/prism.css?inline'
import katexCss from 'katex/dist/katex.css?inline'
import footerHeaderCss from '../assets/styles/headerFooterStyle.css?inline'
import { EXPORT_DOMPURIFY_CONFIG } from '../config'
import { sanitize, unescapeHTML } from '../utils'
import { validEmoji } from '../ui/emojis'
import type { IMuya } from '../types'

interface ExportOptions {
  printOptimization?: boolean
  toc?: string
  title?: string
  extraCss?: string
  header?: { type: number; left: string; center: string; right: string }
  footer?: { type: number; left: string; center: string; right: string }
  headerFooterStyled?: boolean
}

const DIAGRAM_TYPE = ['mermaid', 'flowchart', 'sequence', 'plantuml', 'vega-lite']

class ExportHtml {
  exportContainer: HTMLDivElement | null
  markdown: string
  mathRendererCalled: boolean
  muya: IMuya | undefined
  constructor(markdown: string, muya?: IMuya) {
    this.markdown = markdown
    this.muya = muya
    this.exportContainer = null
    this.mathRendererCalled = false
  }

  async renderMermaid() {
    const codes = this.exportContainer!.querySelectorAll('code.language-mermaid')
    for (const code of codes) {
      const preEle = code.parentNode
      if (!(preEle instanceof HTMLElement)) continue
      const mermaidContainer = document.createElement('div')
      mermaidContainer.innerHTML = sanitize(unescapeHTML(code.innerHTML), EXPORT_DOMPURIFY_CONFIG, true)
      mermaidContainer.classList.add('mermaid')
      preEle.replaceWith(mermaidContainer)
    }

    const nodes = Array.from(this.exportContainer!.querySelectorAll<HTMLElement>('div.mermaid'))
    if (nodes.length === 0) return

    await withMermaidRenderer(async (mermaid) => {
      // Export with a deterministic light theme. `run` is the supported Mermaid
      // v10+ integration API; render each node separately so one malformed
      // diagram cannot abort the rest of the document export.
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        theme: 'default',
      })

      try {
        for (const node of nodes) {
          try {
            await mermaid.run({ nodes: [node] })
          } catch (_error) {
            node.textContent = '< Invalid Diagram >'
            node.classList.add('invalid-diagram')
          }
        }
      } finally {
        // Mermaid configuration is global. Restore the live editor theme after
        // the temporary export render, including when a diagram is invalid.
        if (this.muya) {
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: 'strict',
            theme: this.muya.options.mermaidTheme,
          })
        }
      }
    })
  }

  async renderDiagram() {
    const selector = 'code.language-vega-lite, code.language-flowchart, code.language-sequence, code.language-plantuml'
    const renderers = new Map<string, unknown>()
    const codes = this.exportContainer!.querySelectorAll(selector)
    for (const code of codes) {
      const rawCode = unescapeHTML(code.innerHTML)
      const functionType = (() => {
        if (/sequence/.test(code.className)) {
          return 'sequence'
        } else if (/plantuml/.test(code.className)) {
          return 'plantuml'
        } else if (/flowchart/.test(code.className)) {
          return 'flowchart'
        } else {
          return 'vega-lite'
        }
      })()
      if (!renderers.has(functionType)) {
        renderers.set(functionType, await loadRenderer(functionType))
      }
      // biome-ignore lint/suspicious/noExplicitAny: diagram renderers have heterogeneous APIs
      const render = renderers.get(functionType) as any
      const preParent = code.parentNode as HTMLElement
      const diagramContainer = document.createElement('div')
      diagramContainer.classList.add(functionType)
      preParent.replaceWith(diagramContainer)
      const options: Record<string, unknown> = {}
      if (functionType === 'sequence') {
        Object.assign(options, { theme: this.muya!.options.sequenceTheme })
      } else if (functionType === 'vega-lite') {
        Object.assign(options, {
          actions: false,
          tooltip: false,
          renderer: 'svg',
          theme: 'latimes', // only render light theme
        })
      }
      try {
        if (functionType === 'flowchart' || functionType === 'sequence') {
          const diagram = render.parse(rawCode)
          diagramContainer.innerHTML = ''
          diagram.drawSVG(diagramContainer, options)
        }
        if (functionType === 'plantuml') {
          const diagram = render.parse(rawCode)
          diagramContainer.innerHTML = ''
          diagram.insertImgElement(diagramContainer)
        }
        if (functionType === 'vega-lite') {
          await render(diagramContainer, JSON.parse(rawCode), options)
        }
      } catch (err) {
        console.error('Failed to render diagram:', err)
        diagramContainer.innerHTML = '<pre class="invalid-diagram">Invalid Diagram</pre>'
      }
    }
  }

  mathRenderer = (math: string, displayMode: boolean): string => {
    this.mathRendererCalled = true

    try {
      return katex.renderToString(math, {
        displayMode,
      })
    } catch (_err) {
      return displayMode
        ? `<pre class="multiple-math invalid">\n${math}</pre>\n`
        : `<span class="inline-math invalid" title="invalid math">${math}</span>`
    }
  }

  // render pure html by marked
  async renderHtml(toc?: string) {
    this.mathRendererCalled = false
    let html = marked(this.markdown, {
      superSubScript: this.muya ? this.muya.options.superSubScript : false,
      footnote: this.muya ? this.muya.options.footnote : false,
      isGitlabCompatibilityEnabled: this.muya ? this.muya.options.isGitlabCompatibilityEnabled : false,
      highlight(code: string, lang: string) {
        // Language may be undefined (GH#591)
        if (!lang) {
          return code
        }

        if (DIAGRAM_TYPE.includes(lang)) {
          return code
        }

        const grammar = Prism.languages[lang]
        if (!grammar) {
          console.warn(`Unable to find grammar for "${lang}".`)
          return code
        }
        return Prism.highlight(code, grammar, lang)
      },
      emojiRenderer(emoji: string) {
        const validate = validEmoji(emoji)
        if (validate) {
          return validate.emoji
        } else {
          return `:${emoji}:`
        }
      },
      mathRenderer: this.mathRenderer,
      tocRenderer() {
        if (!toc) {
          return ''
        }
        return toc
      },
    })

    html = sanitize(html, EXPORT_DOMPURIFY_CONFIG, false)

    this.exportContainer = document.createElement('div')
    const exportContainer = this.exportContainer
    exportContainer.classList.add('ag-render-container')
    exportContainer.innerHTML = html
    document.body.appendChild(exportContainer)

    // render only render the light theme of mermaid and diragram...
    await this.renderMermaid()
    await this.renderDiagram()
    let result = exportContainer.innerHTML
    exportContainer.remove()

    // hack to add arrow marker to output html
    const pathes = document.querySelectorAll('path[id^=raphael-marker-]')
    const def = '<defs style="-webkit-tap-highlight-color: rgba(0, 0, 0, 0);">'
    result = result.replace(def, () => {
      let str = ''
      for (const path of pathes) {
        str += path.outerHTML
      }
      return `${def}${str}`
    })

    this.exportContainer = null
    return result
  }

  /**
   * Get HTML with style
   *
   * @param {*} options Document options
   */
  async generate(options: ExportOptions) {
    const { printOptimization } = options

    // WORKAROUND: Hide Prism.js style when exporting or printing. Otherwise the background color is white in the dark theme.
    const highlightCssStyle = printOptimization ? `@media print { ${highlightCss} }` : highlightCss
    const html = this._prepareHtml(await this.renderHtml(options.toc), options)
    const katexCssStyle = this.mathRendererCalled ? katexCss : ''
    this.mathRendererCalled = false

    // `extraCss` may changed in the mean time.
    const { title, extraCss } = options
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${sanitize(title ?? '', EXPORT_DOMPURIFY_CONFIG, true)}</title>
  <style>
  ${githubMarkdownCss}
  </style>
  <style>
  ${highlightCssStyle}
  </style>
  <style>
  ${katexCssStyle}
  </style>
  <style>
    .markdown-body {
      font-family: -apple-system,Segoe UI,Helvetica,Arial,sans-serif,Apple Color Emoji,Segoe UI Emoji;
      box-sizing: border-box;
      min-width: 200px;
      max-width: 980px;
      margin: 0 auto;
      padding: 45px;
    }

    @media not print {
      .markdown-body {
        padding: 45px;
      }

      @media (max-width: 767px) {
        .markdown-body {
          padding: 15px;
        }
      }
    }

    .hf-container {
      color: #24292e;
      line-height: 1.3;
    }

    .markdown-body .highlight pre,
    .markdown-body pre {
      white-space: pre-wrap;
    }
    .markdown-body table {
      display: table;
    }
    .markdown-body img[data-align="center"] {
      display: block;
      margin: 0 auto;
    }
    .markdown-body img[data-align="right"] {
      display: block;
      margin: 0 0 0 auto;
    }
    .markdown-body li.task-list-item {
      list-style-type: none;
    }
    .markdown-body li > [type=checkbox] {
      margin: 0 0 0 -1.3em;
    }
    .markdown-body input[type="checkbox"] ~ p {
      margin-top: 0;
      display: inline-block;
    }
    .markdown-body ol ol,
    .markdown-body ul ol {
      list-style-type: decimal;
    }
    .markdown-body ol ol ol,
    .markdown-body ol ul ol,
    .markdown-body ul ol ol,
    .markdown-body ul ul ol {
      list-style-type: decimal;
    }
  </style>
  <style>${exportStyle}</style>
  <style>${extraCss ?? ''}</style>
</head>
<body>
  ${html}
</body>
</html>`
  }

  /**
   * @private
   *
   * @param {string} html The converted HTML text.
   * @param {*} options The export options.
   */
  _prepareHtml(html: string, options: ExportOptions): string {
    const { header, footer } = options
    const appendHeaderFooter = !!header || !!footer
    if (!appendHeaderFooter) {
      return createMarkdownArticle(html)
    }

    if (!options.extraCss) {
      options.extraCss = footerHeaderCss
    } else {
      options.extraCss = footerHeaderCss + options.extraCss
    }

    let output = HF_TABLE_START
    if (header) {
      output += createTableHeader(options)
    }

    if (footer) {
      output += HF_TABLE_FOOTER
      output = createRealFooter(options) + output
    }

    output = output + createTableBody(html) + HF_TABLE_END
    return sanitize(output, EXPORT_DOMPURIFY_CONFIG, false)
  }
}

// Variables and function to generate the header and footer.
const HF_TABLE_START = '<table class="page-container">'
const createTableBody = (html: string) => {
  return `<tbody><tr><td>
  <div class="main-container">
    ${createMarkdownArticle(html)}
  </div>
</td></tr></tbody>`
}
const HF_TABLE_END = '</table>'

/// The header at is shown at the top.
const createTableHeader = (options: ExportOptions) => {
  const { header, headerFooterStyled } = options
  const { type, left, center, right } = header!
  let headerClass = type === 1 ? 'single' : ''
  headerClass += getHeaderFooterStyledClass(headerFooterStyled)
  return `<thead class="page-header ${headerClass}"><tr><th>
  <div class="hf-container">
    <div class="header-content-left">${left}</div>
    <div class="header-content">${center}</div>
    <div class="header-content-right">${right}</div>
  </div>
</th></tr></thead>`
}

/// Fake footer to reserve space.
const HF_TABLE_FOOTER = `<tfoot class="page-footer-fake"><tr><td>
  <div class="hf-container">
    &nbsp;
  </div>
</td></tr></tfoot>`

/// The real footer at is shown at the bottom.
const createRealFooter = (options: ExportOptions) => {
  const { footer, headerFooterStyled } = options
  const { type, left, center, right } = footer!
  let footerClass = type === 1 ? 'single' : ''
  footerClass += getHeaderFooterStyledClass(headerFooterStyled)
  return `<div class="page-footer ${footerClass}">
  <div class="hf-container">
    <div class="footer-content-left">${left}</div>
    <div class="footer-content">${center}</div>
    <div class="footer-content-right">${right}</div>
  </div>
</div>`
}

/// Generate the mardown article HTML.
const createMarkdownArticle = (html: string) => {
  return `<article class="markdown-body">${html}</article>`
}

/// Return the class whether a header/footer should be styled.
const getHeaderFooterStyledClass = (value: boolean | undefined) => {
  if (value === undefined) {
    // Prefer theme settings.
    return ''
  }
  return !value ? ' simple' : ' styled'
}

export default ExportHtml
