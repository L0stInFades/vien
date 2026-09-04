// Vite import.meta extensions
interface ImportMeta {
  glob(pattern: string, opts?: { eager?: boolean }): Record<string, () => Promise<unknown>>
}

declare module '*.png' {
  const src: string
  export default src
}

declare module '*.svg' {
  const content: { viewBox: string; url: string }
  export default content
}

declare module '*.css?inline' {
  const css: string
  export default css
}

declare module '*.css' {}

declare module 'fuzzaldrin' {
  interface FilterOptions {
    key?: string
    maxResults?: number
  }
  export function filter<T>(candidates: T[], query: string, options?: FilterOptions): T[]
  export function score(string: string, query: string): number
  export function match(string: string, query: string): number[]
}

declare module 'command-exists' {
  const commandExists: {
    (command: string): Promise<string | null>
    sync(command: string): boolean
  }
  export default commandExists
}

declare module 'element-resize-detector' {
  interface ResizeDetectorOptions {
    strategy?: string
  }
  interface ResizeDetector {
    listenTo(element: HTMLElement, callback: (element: HTMLElement) => void): void
    uninstall(element: HTMLElement): void
  }
  function createResizeDetector(options?: ResizeDetectorOptions): ResizeDetector
  export default createResizeDetector
}

declare module '@marktext/file-icons' {
  interface FileIcon {
    getClass(colourMode: number, colourChanges: boolean): string
  }
  interface FileIcons {
    matchName(name: string): FileIcon | null
    matchLanguage(lang: string): FileIcon | null
    getClassByName(name: string): string | null
    getClassByLanguage(lang: string): string | null
  }
  const fileIcons: FileIcons
  export default fileIcons
}

declare module 'katex' {
  interface KatexOptions {
    displayMode?: boolean
    output?: string
    leqno?: boolean
    fleqn?: boolean
    throwOnError?: boolean
    errorColor?: string
    macros?: Record<string, string>
    minRuleThickness?: number
    colorIsTextColor?: boolean
    maxSize?: number
    maxExpand?: number
    strict?: boolean | string | ((errorCode: string, errorMsg: string, token: unknown) => string | boolean)
    trust?: boolean | ((context: { command: string; url: string; protocol: string }) => boolean)
    globalGroup?: boolean
  }
  const katex: {
    renderToString(expression: string, options?: KatexOptions): string
    render(expression: string, element: HTMLElement, options?: KatexOptions): void
  }
  export default katex
}

declare module 'katex/dist/contrib/mhchem.min.js' {}

declare module 'prismjs' {
  interface Grammar {
    [key: string]: unknown
  }
  const Prism: {
    languages: Record<string, Grammar>
    highlight(text: string, grammar: Grammar, language: string): string
    highlightElement(element: Element, async?: boolean, callback?: (this: Element) => void): void
    highlightAll(async?: boolean, callback?: (element: Element) => void): void
    hooks: {
      add(name: string, callback: (...args: unknown[]) => void): void
      run(name: string, env: Record<string, unknown>): void
      all: Record<string, Array<(...args: unknown[]) => void>>
    }
    tokenize(text: string, grammar: Grammar): Array<string | { type: string; content: string }>
    util: Record<string, unknown>
    [key: string]: unknown
  }
  export default Prism
}

declare module 'prismjs/components.js' {
  interface LanguageEntry {
    title?: string
    alias?: string | string[]
    require?: string | string[]
    peerDependencies?: string | string[]
    [key: string]: unknown
  }
  const components: {
    languages: Record<string, LanguageEntry>
    [key: string]: unknown
  }
  export const languages: Record<string, LanguageEntry>
  export default components
}

declare module 'prismjs/dependencies' {
  interface Loader {
    load(callback: (id: string) => void | Promise<void>): void
  }
  function getLoader(components: unknown, ids: string[], loaded: string[]): Loader
  export default getLoader
}

declare module 'prismjs/plugins/keep-markup/prism-keep-markup' {}

declare module 'dompurify' {
  interface DOMPurifyConfig {
    FORBID_ATTR?: string[]
    ALLOW_DATA_ATTR?: boolean
    ADD_ATTR?: string[]
    USE_PROFILES?: { html?: boolean; svg?: boolean; svgFilters?: boolean; mathMl?: boolean }
    RETURN_TRUSTED_TYPE?: boolean
    ALLOWED_URI_REGEXP?: RegExp
    [key: string]: unknown
  }
  const DOMPurify: {
    sanitize(dirty: string | Node, config?: DOMPurifyConfig): string
    isValidAttribute(tag: string, attr: string, value: string): boolean
    [key: string]: unknown
  }
  export default DOMPurify
}

declare module 'turndown' {
  interface TurndownOptions {
    headingStyle?: string
    hr?: string
    bulletListMarker?: string
    codeBlockStyle?: string
    fence?: string
    emDelimiter?: string
    strongDelimiter?: string
    linkStyle?: string
    linkReferenceStyle?: string
    blankReplacement?: (content: string, node: HTMLElement & { isBlock?: boolean }, options: unknown) => string
    [key: string]: unknown
  }
  interface TurndownRule {
    filter: string | string[] | ((node: HTMLElement, options: unknown) => boolean)
    replacement: (content: string, node: HTMLElement, options: TurndownOptions) => string
  }
  class TurndownService {
    constructor(options?: TurndownOptions)
    turndown(html: string | HTMLElement): string
    use(plugins: unknown): TurndownService
    addRule(key: string, rule: TurndownRule): TurndownService
    keep(tags: string[]): TurndownService
    remove(tags: string[]): TurndownService
    escape: (str: string) => string
  }
  export default TurndownService
}

declare module 'joplin-turndown-plugin-gfm' {
  export const gfm: (service: unknown) => void
  export const tables: (service: unknown) => void
  export const strikethrough: (service: unknown) => void
  export const taskListItems: (service: unknown) => void
}

declare module 'mermaid/dist/mermaid.core.mjs' {
  const mermaid: {
    initialize(config: Record<string, unknown>): void
    init(config: unknown, nodes: NodeListOf<Element> | Element | string): void
    parse(text: string): boolean
    render(
      id: string,
      text: string,
      container?: Element,
    ): Promise<{ svg: string; bindFunctions?: (element: Element) => void }>
    [key: string]: unknown
  }
  export default mermaid
}
