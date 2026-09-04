import loadRenderer from './index'

export interface MermaidRenderResult {
  svg: string
  bindFunctions?: (element: Element) => void
}

export interface MermaidRenderer {
  initialize(options: Record<string, unknown>): void
  parse(code: string): unknown | Promise<unknown>
  render(renderId: string, text: string, container?: Element): MermaidRenderResult | Promise<MermaidRenderResult>
  run(options: { nodes: HTMLElement[] }): Promise<void>
}

let queue: Promise<void> = Promise.resolve()

/**
 * Mermaid serializes parse/render calls internally, but initialize() mutates
 * shared global configuration outside that queue. Keep initialization, work,
 * and any configuration restoration in one application-level critical section.
 */
export const withMermaidRenderer = async <T>(work: (renderer: MermaidRenderer) => Promise<T>): Promise<T> => {
  let release!: () => void
  const gate = new Promise<void>((resolve) => {
    release = resolve
  })
  const previous = queue.catch(() => undefined)
  queue = previous.then(() => gate)

  await previous
  try {
    return await work((await loadRenderer('mermaid')) as MermaidRenderer)
  } finally {
    release()
  }
}
