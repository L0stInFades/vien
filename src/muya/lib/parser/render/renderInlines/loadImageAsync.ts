import type { StateRenderContext } from '../renderContext'
import { getUniqueId, loadImage } from '../../../utils'
import { toDisplaySrc } from '../../../utils/assetDisplay'
import { insertAfter, operateClassName } from '../../../utils/domManipulate'
import { CLASS_OR_ID } from '../../../config'

export default function loadImageAsync(
  this: StateRenderContext,
  imageInfo: { src: string; isUnknownType?: boolean; [k: string]: unknown },
  attrs: { alt?: string; title?: string; width?: number; height?: number; [k: string]: unknown },
  className: string,
  imageClass: string,
) {
  const { src, isUnknownType } = imageInfo
  let id: string | undefined
  let isSuccess: boolean | undefined
  let w: number | undefined
  let domsrc: string | undefined
  let h: number | undefined

  let reload = false
  if (this.loadImageMap.has(src)) {
    const imageInfo = this.loadImageMap.get(src)!
    if (imageInfo.dispMsec !== imageInfo.touchMsec) {
      // We have a cached image, but force it to load.
      reload = true
    }
  } else {
    reload = true
  }
  if (reload) {
    id = getUniqueId()
    loadImage(src, isUnknownType)
      .then(({ url, width, height }) => {
        const imageText = document.querySelector(`#${id}`)
        const img = document.createElement('img')
        const dispMsec = Date.now()
        const touchMsec = dispMsec
        if (/^file:\/\//.test(src)) {
          // Local files load through the controlled vien-asset protocol so
          // webSecurity can stay enabled; msec busts the renderer cache.
          domsrc = `${toDisplaySrc(url)}?msec=${dispMsec}`
        } else {
          domsrc = url
        }
        img.src = domsrc
        if (attrs.alt) img.alt = attrs.alt.replace(/[`*{}[\]()#+\-.!_>~:|<>$]/g, '')
        if (attrs.title) img.setAttribute('title', attrs.title)
        if (attrs.width && typeof attrs.width === 'number') {
          img.setAttribute('width', String(attrs.width))
        }
        if (attrs.height && typeof attrs.height === 'number') {
          img.setAttribute('height', String(attrs.height))
        }
        if (imageClass) {
          img.classList.add(imageClass)
        }

        if (imageText) {
          if (imageText.classList.contains('ag-inline-image')) {
            const imageContainer = imageText.querySelector('.ag-image-container')
            const oldImage = imageContainer?.querySelector('img')
            if (oldImage) {
              oldImage.remove()
            }
            imageContainer?.appendChild(img)
            imageText.classList.remove('ag-image-loading')
            imageText.classList.add('ag-image-success')
          } else {
            insertAfter(img, imageText)
            operateClassName(imageText as HTMLElement, 'add', className)
          }
        }
        if (this.urlMap.has(src)) {
          this.urlMap.delete(src)
        }
        this.loadImageMap.set(src, {
          id,
          isSuccess: true,
          width,
          height,
          dispMsec,
          touchMsec,
          domsrc,
        })
      })
      .catch(() => {
        const imageText = document.querySelector(`#${id}`)
        if (imageText) {
          operateClassName(imageText as HTMLElement, 'remove', CLASS_OR_ID.AG_IMAGE_LOADING)
          operateClassName(imageText as HTMLElement, 'add', CLASS_OR_ID.AG_IMAGE_FAIL)
          const image = imageText.querySelector('img')
          if (image) {
            image.remove()
          }
        }
        if (this.urlMap.has(src)) {
          this.urlMap.delete(src)
        }
        this.loadImageMap.set(src, {
          id,
          isSuccess: false,
        })
      })
  } else {
    const imageInfo = this.loadImageMap.get(src)!

    id = imageInfo.id
    isSuccess = imageInfo.isSuccess
    w = imageInfo.width
    h = imageInfo.height
    domsrc = imageInfo.domsrc
  }

  return { id, isSuccess, domsrc, width: w, height: h }
}
