import BaseFloat from '../baseFloat'
import { patch, h } from '../../parser/render/snabbdom'
import icons from './config'
import type { IMuya } from '../../types'
import type { VNode } from 'snabbdom'

import './index.css'

interface FormatIcon {
  type: string
  tooltip: string
  shortcut: string
  icon: string
}

interface FormatInfo {
  type: string
  tag?: string
}

const defaultOptions = {
  placement: 'top',
  modifiers: {
    offset: {
      offset: '0, 5',
    },
  },
  showArrow: false,
}

class FormatPicker extends BaseFloat {
  static pluginName = 'formatPicker'

  formatContainer: HTMLDivElement
  formats: FormatInfo[] | null
  icons: FormatIcon[]
  oldVnode: VNode | null

  constructor(muya: IMuya, options = {}) {
    const name = 'ag-format-picker'
    const opts = Object.assign({}, defaultOptions, options)
    super(muya, name, opts)
    this.oldVnode = null
    this.formats = null
    this.options = opts
    this.icons = icons
    this.formatContainer = document.createElement('div')
    const formatContainer = this.formatContainer
    this.container.appendChild(formatContainer)
    this.floatBox.classList.add('ag-format-picker-container')
    this.listen()
  }

  listen() {
    const { eventCenter } = this.muya
    super.listen()
    eventCenter.subscribe('muya-format-picker', (({
      reference,
      formats,
    }: {
      reference: HTMLElement | null
      formats: FormatInfo[]
    }) => {
      if (reference) {
        this.formats = formats
        setTimeout(() => {
          this.show(reference)
          this.render()
        }, 0)
      } else {
        this.hide()
      }
    }) as (...args: unknown[]) => void)
  }

  render() {
    const { icons, oldVnode, formatContainer, formats } = this
    if (!formats) return
    const children = icons.map((i: FormatIcon) => {
      // biome-ignore lint/suspicious/noImplicitAnyLet: legacy UI pattern
      let icon
      const iconWrapperSelector = 'div.icon-wrapper'
      if (i.icon) {
        // SVG icon Asset
        icon = h(
          'i.icon',
          h(
            'i.icon-inner',
            {
              style: {
                background: `url(${i.icon}) no-repeat`,
                'background-size': '100%',
              },
            },
            '',
          ),
        )
      }
      const iconWrapper = h(iconWrapperSelector, icon)

      let itemSelector = `li.item.${i.type}`
      if (formats.some((f: FormatInfo) => f.type === i.type || (f.type === 'html_tag' && f.tag === i.type))) {
        itemSelector += '.active'
      }
      return h(
        itemSelector,
        {
          attrs: {
            'data-tooltip': `${i.tooltip} ${i.shortcut}`,
          },
          on: {
            click: (event) => {
              this.selectItem(event as Event, i)
            },
          },
        },
        [iconWrapper],
      )
    })

    const vnode = h('ul.ag-format-picker', children)

    if (oldVnode) {
      patch(oldVnode, vnode)
    } else {
      patch(formatContainer, vnode)
    }
    this.oldVnode = vnode
  }

  selectItem(event: Event, item: FormatIcon) {
    event.preventDefault()
    event.stopPropagation()
    const { contentState } = this.muya
    contentState.render()
    contentState.format(item.type)
    if (/link|image/.test(item.type)) {
      this.hide()
    } else {
      const { formats } = contentState.selectionFormats() as { formats: FormatInfo[] }
      this.formats = formats
      this.render()
    }
  }
}

export default FormatPicker
