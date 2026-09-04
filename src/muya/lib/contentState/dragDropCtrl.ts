import { findNearestParagraph, findOutMostParagraph } from '../selection/dom'
import { verticalPositionInRect, getUniqueId, getImageInfo as getImageSrc, checkImageContentType } from '../utils'
import { getImageInfo } from '../utils/getImageInfo'
import { URL_REG, IMAGE_EXT_REG } from '../config'
import type { IContentState, Block } from '../types'

const GHOST_ID = 'mu-dragover-ghost'
const GHOST_HEIGHT = 3

const dragDropCtrl = (ContentState: { prototype: IContentState }) => {
  ContentState.prototype.hideGhost = function () {
    this.dropAnchor = null
    const ghost = document.querySelector(`#${GHOST_ID}`)
    ghost?.remove()
  }
  /**
   * create the ghost element.
   */
  ContentState.prototype.createGhost = function (event: DragEvent) {
    const target = event.target
    let ghost = null
    const nearestParagraph = findNearestParagraph(target as Node | null)
    const outmostParagraph = findOutMostParagraph(target as Node | null)

    if (!outmostParagraph) {
      return this.hideGhost()
    }

    const block = this.getBlock(nearestParagraph!.id)!
    let anchor = this.getAnchor(block)

    // dragover preview container
    if (!anchor && outmostParagraph) {
      anchor = this.getBlock((outmostParagraph as HTMLElement).id)
    }

    if (anchor) {
      const anchorParagraph = anchor.key ? this.muya.container.querySelector(`#${anchor.key}`) : null
      if (!anchorParagraph) return
      const rect = anchorParagraph.getBoundingClientRect()
      const position = verticalPositionInRect(event, rect)
      this.dropAnchor = {
        position,
        anchor,
      }
      // create ghost
      ghost = document.querySelector(`#${GHOST_ID}`)
      if (!ghost) {
        ghost = document.createElement('div')
        ghost.id = GHOST_ID
        document.body.appendChild(ghost)
      }

      Object.assign((ghost as HTMLElement).style, {
        width: `${rect.width}px`,
        left: `${rect.left}px`,
        top: position === 'up' ? `${rect.top - GHOST_HEIGHT}px` : `${rect.top + rect.height}px`,
      })
    }
  }

  ContentState.prototype.dragoverHandler = function (event: DragEvent) {
    // Cancel to allow tab drag&drop.
    if (!event.dataTransfer!.types.length) {
      event.dataTransfer!.dropEffect = 'none'
      return
    }

    if (event.dataTransfer!.types.includes('text/uri-list')) {
      const items = Array.from(event.dataTransfer!.items)
      const hasUriItem = items.some((i) => i.type === 'text/uri-list')
      const hasTextItem = items.some((i) => i.type === 'text/plain')
      const hasHtmlItem = items.some((i) => i.type === 'text/html')
      if (hasUriItem && hasHtmlItem && !hasTextItem) {
        this.createGhost(event)
        event.dataTransfer!.dropEffect = 'copy'
      }
    }

    if (event.dataTransfer!.types.indexOf('Files') >= 0) {
      if (event.dataTransfer!.items.length === 1 && event.dataTransfer!.items[0].type.indexOf('image') > -1) {
        event.preventDefault()
        this.createGhost(event)
        event.dataTransfer!.dropEffect = 'copy'
      }
    } else {
      event.stopPropagation()
      event.dataTransfer!.dropEffect = 'none'
    }
  }

  ContentState.prototype.dragleaveHandler = function (_event: DragEvent) {
    return this.hideGhost()
  }

  ContentState.prototype.dropHandler = async function (event: DragEvent) {
    event.preventDefault()
    const dropAnchor = this.dropAnchor as { position: string; anchor: Block } | null
    this.hideGhost()
    // handle drag/drop web link image.
    if (event.dataTransfer!.items.length) {
      for (const item of event.dataTransfer!.items) {
        if (item.kind === 'string' && item.type === 'text/uri-list') {
          item.getAsString(async (str: string) => {
            if (URL_REG.test(str) && dropAnchor) {
              let isImage = false
              if (IMAGE_EXT_REG.test(str)) {
                isImage = true
              }
              if (!isImage) {
                isImage = await checkImageContentType(str)
              }
              if (!isImage) return
              const text = `![](${str})`
              const imageBlock = this.createBlockP(text)
              const { anchor, position } = dropAnchor
              if (position === 'up') {
                this.insertBefore(imageBlock, anchor)
              } else {
                this.insertAfter(imageBlock, anchor)
              }

              const key = imageBlock.children[0].key
              const offset = 0
              this.cursor = {
                start: { key, offset },
                end: { key, offset },
              }
              this.render()
              this.muya.eventCenter.dispatch('stateChange')
            }
          })
        }
      }
    }

    if (event.dataTransfer!.files) {
      const fileList = []
      for (const file of event.dataTransfer!.files) {
        fileList.push(file)
      }
      const image = fileList.find((file) => /image/.test(file.type))
      if (image && dropAnchor) {
        const { name } = image
        const path = this.muya.options.filePathResolver?.(image)
        if (!path) return
        const id = `loading-${getUniqueId()}`
        const text = `![${id}](${path})`
        const imageBlock = this.createBlockP(text)
        const { anchor, position } = dropAnchor
        if (position === 'up') {
          this.insertBefore(imageBlock, anchor)
        } else {
          this.insertAfter(imageBlock, anchor)
        }

        const key = imageBlock.children[0].key
        const offset = 0
        this.cursor = {
          start: { key, offset },
          end: { key, offset },
        }
        this.render()

        try {
          const newSrc = await this.muya.options.imageAction!(path, id, name)
          const { src } = getImageSrc(path)
          if (src) {
            this.stateRender.urlMap.set(newSrc, src)
          }
          const imageWrapper = this.muya.container.querySelector(`span[data-id=${id}]`)

          if (imageWrapper) {
            const imageInfo = getImageInfo(imageWrapper as HTMLElement)
            this.replaceImage(imageInfo, {
              alt: name,
              src: newSrc,
            })
          }
        } catch (error) {
          // TODO: Notify user about an error.
          console.error('Unexpected error on image action:', error)
        }
      }
      this.muya.eventCenter.dispatch('stateChange')
    }
  }
}

export default dragDropCtrl
