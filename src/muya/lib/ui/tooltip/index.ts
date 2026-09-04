import type { IMuya } from '../../types'
import './index.css'

const position = (source: HTMLElement, ele: HTMLElement) => {
  const rect = source.getBoundingClientRect()
  const width = ele.offsetWidth
  const centerX = rect.left + rect.width / 2
  const left = Math.max(8, Math.min(centerX - width / 2, window.innerWidth - width - 8))

  Object.assign(ele.style, {
    top: `${rect.top + rect.height + 15}px`,
    left: `${left}px`,
  })
}

class Tooltip {
  cache: WeakMap<HTMLElement, HTMLDivElement>
  muya: IMuya
  constructor(muya: IMuya) {
    this.muya = muya
    this.cache = new WeakMap()
    const { eventCenter } = this.muya

    // Float containers are appended to document.body, so listen there instead
    // of on the muya container.
    eventCenter.attachDOMEvent(document.body, 'mouseover', this.mouseOver.bind(this) as EventListener)
  }

  mouseOver(event: MouseEvent) {
    const { target } = event
    const toolTipTarget = (target as HTMLElement).closest('[data-tooltip]') as HTMLElement | null
    const { eventCenter } = this.muya
    if (toolTipTarget && !this.cache.has(toolTipTarget)) {
      const tooltip = toolTipTarget.getAttribute('data-tooltip')
      const tooltipEle = document.createElement('div')
      tooltipEle.textContent = tooltip
      tooltipEle.classList.add('ag-tooltip')
      document.body.appendChild(tooltipEle)
      position(toolTipTarget, tooltipEle)

      this.cache.set(toolTipTarget, tooltipEle)

      setTimeout(() => {
        tooltipEle.classList.add('active')
      })

      const timer = setInterval(() => {
        if (!document.body.contains(toolTipTarget)) {
          this.mouseLeave({ target: toolTipTarget } as unknown as MouseEvent)
          clearInterval(timer)
        }
      }, 300)

      eventCenter.attachDOMEvent(toolTipTarget, 'mouseleave', this.mouseLeave.bind(this) as EventListener)
    }
  }

  mouseLeave(event: MouseEvent) {
    const target = event.target as HTMLElement
    if (this.cache.has(target)) {
      const tooltipEle = this.cache.get(target)
      tooltipEle?.remove()
      this.cache.delete(target)
    }
  }
}

export default Tooltip
