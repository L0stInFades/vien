import { URL_REG, DATA_URL_REG } from '../config'
import { escapeHTML } from '../utils'
import { correctImageSrc } from '../utils/getImageInfo'
import type { IContentState, Token } from '../types'

const imageCtrl = (ContentState: { prototype: IContentState }) => {
  /**
   * insert inline image at the cursor position.
   */
  ContentState.prototype.insertImage = function (
    this: IContentState,
    { alt = '', src = '', title = '' }: { alt?: string; src?: string; title?: string },
  ) {
    const match = /(?:\/|\\)?([^./\\]+)\.[a-z]+$/.exec(src)
    if (!alt) {
      alt = match?.[1] ? match[1] : ''
    }

    const { start, end } = this.cursor
    const { formats } = this.selectionFormats({ start, end })
    const { key, offset: startOffset } = start
    const { offset: endOffset } = end
    const block = this.getBlock(key)
    if (
      block!.type === 'span' &&
      (block!.functionType === 'codeContent' ||
        block!.functionType === 'languageInput' ||
        block!.functionType === 'thematicBreakLine')
    ) {
      // You can not insert image into code block or language input...
      return
    }
    const { text } = block!
    const imageFormat = formats.filter((f: Token) => f.type === 'image')
    // Only encode URLs but not local paths or data URLs
    let imgUrl: string
    if (URL_REG.test(src)) {
      imgUrl = encodeURI(src)
    } else if (DATA_URL_REG.test(src)) {
      imgUrl = src
    } else {
      if (src) {
        imgUrl = src.replace(/ /g, encodeURI(' ')).replace(/#/g, encodeURIComponent('#'))
      } else {
        imgUrl = ''
      }
    }

    let srcAndTitle = imgUrl

    if (srcAndTitle && title) {
      srcAndTitle += ` "${title}"`
    }

    if (
      imageFormat.length === 1 &&
      imageFormat[0].range.start !== startOffset &&
      imageFormat[0].range.end !== endOffset
    ) {
      // Replace already existing image
      let imageAlt = alt

      // Extract alt from image if there isn't an image source already (GH#562). E.g: ![old-alt]()
      if (imageFormat[0].alt && !imageFormat[0].src) {
        imageAlt = imageFormat[0].alt as string
      }

      const { start, end } = imageFormat[0].range as { start: number; end: number }
      block!.text = `${text.substring(0, start)}![${imageAlt}](${srcAndTitle})${text.substring(end)}`

      this.cursor = {
        start: { key, offset: start + 2 },
        end: { key, offset: start + 2 + imageAlt.length },
      }
    } else if (key !== end.key) {
      // Replace multi-line text
      const endBlock = this.getBlock(end.key)!
      const { text } = endBlock
      endBlock.text = `${text.substring(0, endOffset)}![${alt}](${srcAndTitle})${text.substring(endOffset)}`
      const offset = endOffset + 2
      this.cursor = {
        start: { key: end.key, offset },
        end: { key: end.key, offset: offset + alt.length },
      }
    } else {
      // Replace single-line text
      const imageAlt = startOffset !== endOffset ? text.substring(startOffset, endOffset) : alt
      block!.text = `${text.substring(0, start.offset)}![${imageAlt}](${srcAndTitle})${text.substring(end.offset)}`

      this.cursor = {
        start: {
          key,
          offset: startOffset + 2,
        },
        end: {
          key,
          offset: startOffset + 2 + imageAlt.length,
        },
      }
    }
    this.partialRender()
    this.muya.dispatchChange()
  }

  ContentState.prototype.updateImage = function (
    this: IContentState,
    {
      imageId,
      key,
      token,
    }: {
      imageId: string
      key: string
      token: { range: { start: number; end: number }; attrs: Record<string, string> }
    },
    attrName: string,
    attrValue: string,
  ) {
    // inline/left/center/right
    const block = this.getBlock(key)!
    const { range } = token
    const { start, end } = range
    const oldText = block.text
    let imageText = ''
    const attrs = Object.assign({}, token.attrs)
    attrs[attrName] = attrValue

    imageText = '<img '
    for (const attr of Object.keys(attrs)) {
      let value = attrs[attr]
      if (value && attr === 'src') {
        value = correctImageSrc(value)
      }
      imageText += `${attr}="${escapeHTML(String(value))}" `
    }
    imageText = imageText.trim()
    imageText += '>'
    block.text = oldText.substring(0, start) + imageText + oldText.substring(end)

    this.singleRender(block, false)
    const image = document.querySelector(`#${imageId} img`)
    if (image) {
      ;(image as HTMLElement).click()
      return this.muya.dispatchChange()
    }
  }

  ContentState.prototype.replaceImage = function (
    this: IContentState,
    {
      key,
      token,
    }: { key: string; token: { type: string; range: { start: number; end: number }; attrs?: Record<string, string> } },
    { alt = '', src = '', title = '' }: { alt?: string; src?: string; title?: string },
  ) {
    const { type } = token
    const block = this.getBlock(key)!
    const { start, end } = token.range
    const oldText = block.text
    let imageText = ''
    if (type === 'image') {
      imageText = '!['
      if (alt) {
        imageText += alt
      }
      imageText += ']('
      if (src) {
        imageText += src.replace(/ /g, encodeURI(' ')).replace(/#/g, encodeURIComponent('#'))
      }
      if (title) {
        imageText += ` "${title}"`
      }
      imageText += ')'
    } else if (type === 'html_tag') {
      const attrs = Object.assign({}, token.attrs, { alt, src, title })
      imageText = '<img '
      for (const attr of Object.keys(attrs)) {
        let value = attrs[attr]
        if (value && attr === 'src') {
          value = correctImageSrc(value)
        }
        imageText += `${attr}="${escapeHTML(String(value))}" `
      }
      imageText = imageText.trim()
      imageText += '>'
    }

    block.text = oldText.substring(0, start) + imageText + oldText.substring(end)

    this.singleRender(block)
    return this.muya.dispatchChange()
  }

  ContentState.prototype.deleteImage = function (
    this: IContentState,
    { key, token }: { key: string; token: { range: { start: number; end: number }; raw: string } },
  ) {
    const block = this.getBlock(key)!
    const oldText = block.text
    const { start, end } = token.range
    const { eventCenter } = this.muya
    block.text = oldText.substring(0, start) + oldText.substring(end)

    this.cursor = {
      start: { key, offset: start },
      end: { key, offset: start },
    }
    this.singleRender(block)
    // Hide image toolbar and image transformer
    eventCenter.dispatch('muya-transformer', { reference: null })
    eventCenter.dispatch('muya-image-toolbar', { reference: null })
    return this.muya.dispatchChange()
  }

  ContentState.prototype.selectImage = function (
    this: IContentState,
    imageInfo: { key: string; token: { range: { start: number; end: number }; raw: string }; imageId?: string },
  ) {
    this.selectedImage = imageInfo
    const { key } = imageInfo
    const block = this.getBlock(key)!
    const outMostBlock = this.findOutMostBlock(block)
    this.cursor = {
      start: { key, offset: imageInfo.token.range.end },
      end: { key, offset: imageInfo.token.range.end },
    }
    // Fix #1568
    const { start } = this.prevCursor!
    const oldBlock = this.findOutMostBlock(this.getBlock(start.key)!)
    if (oldBlock.key !== outMostBlock.key) {
      this.singleRender(oldBlock, false)
    }

    return this.singleRender(outMostBlock, true)
  }
}

export default imageCtrl
