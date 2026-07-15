/**
 * This file is copy from [medium-editor](https://github.com/yabwe/medium-editor)
 * and customize for specialized use.
 */
import Cursor from './cursor'
import { CLASS_OR_ID } from '../config'
import {
  isBlockContainer,
  traverseUp,
  getFirstSelectableLeafNode,
  getClosestBlockContainer,
  getCursorPositionWithinMarkedText,
  findNearestParagraph,
  getTextContent,
  getOffsetOfParagraph,
} from './dom'

const filterOnlyParentElements = (node: Node) => {
  return isBlockContainer(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP
}

interface SelectionState {
  start: number
  end: number
  startsWithImage?: boolean
  emptyBlocksIndex?: number
  trailingImageCount?: number
}

class Selection {
  doc: Document
  constructor(doc: Document) {
    this.doc = doc // document
  }

  findMatchingSelectionParent(testElementFunction: (el: Element) => boolean, contentWindow: Window) {
    const selection = contentWindow.getSelection()

    if (!selection || selection.rangeCount === 0) {
      return false
    }

    const range = selection.getRangeAt(0)
    const current = range.commonAncestorContainer

    return traverseUp(current, testElementFunction)
  }

  // https://stackoverflow.com/questions/17678843/cant-restore-selection-after-html-modify-even-if-its-the-same-html
  // Tim Down
  //
  // {object} selectionState - the selection to import
  // {DOMElement} root - the root element the selection is being restored inside of
  // {boolean} [favorLaterSelectionAnchor] - defaults to false. If true, import the cursor immediately
  //      subsequent to an anchor tag if it would otherwise be placed right at the trailing edge inside the
  //      anchor. This cursor positioning, even though visually equivalent to the user, can affect behavior
  //      in MS IE.
  importSelection(selectionState: SelectionState, root: Node, favorLaterSelectionAnchor?: boolean) {
    if (!selectionState || !root) {
      throw new Error('your must provide a [selectionState] and a [root] element')
    }

    let range = this.doc.createRange()
    range.setStart(root, 0)
    range.collapse(true)

    let node: Node | undefined = root
    const nodeStack: Node[] = []
    let charIndex = 0
    let foundStart = false
    let foundEnd = false
    let trailingImageCount = 0
    let stop = false
    let nextCharIndex: number | undefined
    let allowRangeToStartAtEndOfNode = false
    let lastTextNode: Text | null = null

    // When importing selection, the start of the selection may lie at the end of an element
    // or at the beginning of an element.  Since visually there is no difference between these 2
    // we will try to move the selection to the beginning of an element since this is generally
    // what users will expect and it's a more predictable behavior.
    //
    // However, there are some specific cases when we don't want to do this:
    //  1) We're attempting to move the cursor outside of the end of an anchor [favorLaterSelectionAnchor = true]
    //  2) The selection starts with an image, which is special since an image doesn't have any 'content'
    //     as far as selection and ranges are concerned
    //  3) The selection starts after a specified number of empty block elements (selectionState.emptyBlocksIndex)
    //
    // For these cases, we want the selection to start at a very specific location, so we should NOT
    // automatically move the cursor to the beginning of the first actual chunk of text
    if (
      favorLaterSelectionAnchor ||
      selectionState.startsWithImage ||
      typeof selectionState.emptyBlocksIndex !== 'undefined'
    ) {
      allowRangeToStartAtEndOfNode = true
    }

    while (!stop && node) {
      // Only iterate over elements and text nodes
      if (node.nodeType > 3) {
        node = nodeStack.pop()
        continue
      }

      // If we hit a text node, we need to add the amount of characters to the overall count
      if (node.nodeType === 3 && !foundEnd) {
        nextCharIndex = charIndex + (node as Text).length
        // Check if we're at or beyond the start of the selection we're importing
        if (!foundStart && selectionState.start >= charIndex && selectionState.start <= nextCharIndex) {
          // NOTE: We only want to allow a selection to start at the END of an element if
          //  allowRangeToStartAtEndOfNode is true
          if (allowRangeToStartAtEndOfNode || selectionState.start < nextCharIndex) {
            range.setStart(node, selectionState.start - charIndex)
            foundStart = true
          } else {
            // We're at the end of a text node where the selection could start but we shouldn't
            // make the selection start here because allowRangeToStartAtEndOfNode is false.
            // However, we should keep a reference to this node in case there aren't any more
            // text nodes after this, so that we have somewhere to import the selection to
            lastTextNode = node as Text
          }
        }
        // We've found the start of the selection, check if we're at or beyond the end of the selection we're importing
        if (foundStart && selectionState.end >= charIndex && selectionState.end <= nextCharIndex) {
          if (!selectionState.trailingImageCount) {
            range.setEnd(node, selectionState.end - charIndex)
            stop = true
          } else {
            foundEnd = true
          }
        }
        charIndex = nextCharIndex
      } else {
        if (selectionState.trailingImageCount && foundEnd) {
          if (node.nodeName.toLowerCase() === 'img') {
            trailingImageCount++
          }
          if (trailingImageCount === selectionState.trailingImageCount && node.parentNode) {
            // Find which index the image is in its parent's children
            let endIndex = 0
            while (endIndex < node.parentNode.childNodes.length && node.parentNode.childNodes[endIndex] !== node) {
              endIndex++
            }
            const setEndOffset = Math.min(endIndex + 1, node.parentNode.childNodes.length)
            range.setEnd(node.parentNode, setEndOffset)
            stop = true
          }
        }

        if (!stop && node.nodeType === 1) {
          // this is an element
          // add all its children to the stack
          let i = node.childNodes.length - 1
          while (i >= 0) {
            nodeStack.push(node.childNodes[i])
            i -= 1
          }
        }
      }

      if (!stop) {
        node = nodeStack.pop()
      }
    }

    // If we've gone through the entire text but didn't find the beginning of a text node
    // to make the selection start at, we should fall back to starting the selection
    // at the END of the last text node we found
    if (!foundStart && lastTextNode) {
      range.setStart(lastTextNode, lastTextNode.length)
      range.setEnd(lastTextNode, lastTextNode.length)
    }

    if (typeof selectionState.emptyBlocksIndex !== 'undefined') {
      range = this.importSelectionMoveCursorPastBlocks(root, selectionState.emptyBlocksIndex, range)
    }

    // If the selection is right at the ending edge of a link, put it outside the anchor tag instead of inside.
    if (favorLaterSelectionAnchor) {
      range = this.importSelectionMoveCursorPastAnchor(selectionState, range)
    }

    this.selectRange(range)
  }

  // Utility method called from importSelection only
  importSelectionMoveCursorPastAnchor(selectionState: SelectionState, range: Range): Range {
    const nodeInsideAnchorTagFunction = (node: Element) => node.nodeName.toLowerCase() === 'a'
    if (
      selectionState.start === selectionState.end &&
      range.startContainer.nodeType === 3 &&
      range.startOffset === (range.startContainer as Text).nodeValue!.length &&
      traverseUp(range.startContainer, nodeInsideAnchorTagFunction)
    ) {
      let prevNode: Node = range.startContainer
      let currentNode: Node | null = range.startContainer.parentNode
      while (currentNode !== null && currentNode.nodeName.toLowerCase() !== 'a') {
        if (currentNode.childNodes[currentNode.childNodes.length - 1] !== prevNode) {
          currentNode = null
        } else {
          prevNode = currentNode
          currentNode = currentNode.parentNode
        }
      }
      if (currentNode !== null && currentNode.nodeName.toLowerCase() === 'a' && currentNode.parentNode) {
        let currentNodeIndex: number | null = null
        for (let i = 0; currentNodeIndex === null && i < currentNode.parentNode.childNodes.length; i++) {
          if (currentNode.parentNode.childNodes[i] === currentNode) {
            currentNodeIndex = i
          }
        }
        if (currentNodeIndex !== null) {
          const setOffset = Math.min(currentNodeIndex + 1, currentNode.parentNode.childNodes.length)
          range.setStart(currentNode.parentNode, setOffset)
          range.collapse(true)
        }
      }
    }
    return range
  }

  // Uses the emptyBlocksIndex calculated by getIndexRelativeToAdjacentEmptyBlocks
  // to move the cursor back to the start of the correct paragraph
  importSelectionMoveCursorPastBlocks(root: Node, index: number, range: Range): Range {
    const treeWalker = this.doc.createTreeWalker(root, NodeFilter.SHOW_ELEMENT, {
      acceptNode: filterOnlyParentElements,
    })
    const startContainer = range.startContainer
    let startBlock: Node | null | false
    let targetNode: Node | undefined
    let currIndex = 0
    // If index is 0, we still want to move to the next block

    // Chrome counts newlines and spaces that separate block elements as actual elements.
    // If the selection is inside one of these text nodes, and it has a previous sibling
    // which is a block element, we want the treewalker to start at the previous sibling
    // and NOT at the parent of the textnode
    if (startContainer.nodeType === 3 && isBlockContainer(startContainer.previousSibling)) {
      startBlock = startContainer.previousSibling
    } else {
      startBlock = getClosestBlockContainer(startContainer)
    }

    // Skip over empty blocks until we hit the block we want the selection to be in
    while (treeWalker.nextNode()) {
      if (!targetNode) {
        // Loop through all blocks until we hit the starting block element
        if (startBlock === treeWalker.currentNode) {
          targetNode = treeWalker.currentNode
        }
      } else {
        targetNode = treeWalker.currentNode
        currIndex++
        // We hit the target index, bail
        if (currIndex === index) {
          break
        }
        // If we find a non-empty block, ignore the emptyBlocksIndex and just put selection here
        if (targetNode.textContent!.length > 0) {
          break
        }
      }
    }

    if (!targetNode) {
      targetNode = startBlock || root
    }

    // We're selecting a high-level block node, so make sure the cursor gets moved into the deepest
    // element at the beginning of the block
    const leafNode = getFirstSelectableLeafNode(targetNode)
    if (leafNode) {
      range.setStart(leafNode, 0)
    }

    return range
  }

  // https://stackoverflow.com/questions/4176923/html-of-selected-text
  // by Tim Down
  getSelectionHtml() {
    const sel = this.doc.getSelection()
    let i: number
    let html = ''
    let len: number
    let container: HTMLElement | undefined
    if (sel?.rangeCount) {
      container = this.doc.createElement('div')
      for (i = 0, len = sel.rangeCount; i < len; i += 1) {
        container.appendChild(sel.getRangeAt(i).cloneContents())
      }
      html = container.innerHTML
    }
    return html
  }

  chopHtmlByCursor(root: HTMLElement) {
    const { left } = this.getCaretOffsets(root)
    const markedText = root.textContent ?? ''
    const { type, info } = getCursorPositionWithinMarkedText(markedText, left)
    const pre = markedText.slice(0, left)
    const post = markedText.slice(left)
    switch (type) {
      case 'OUT':
        return {
          pre,
          post,
        }
      case 'IN':
        return {
          pre: `${pre}${info}`,
          post: `${info}${post}`,
        }
      case 'LEFT':
        return {
          pre: markedText.slice(0, left - (info as number)),
          post: markedText.slice(left - (info as number)),
        }
      case 'RIGHT':
        return {
          pre: markedText.slice(0, left + (info as number)),
          post: markedText.slice(left + (info as number)),
        }
    }
  }

  /**
   *  Find the caret position within an element irrespective of any inline tags it may contain.
   *
   *  @param {DOMElement} An element containing the cursor to find offsets relative to.
   *  @param {Range} A Range representing cursor position. Will window.getSelection if none is passed.
   *  @return {Object} 'left' and 'right' attributes contain offsets from beginning and end of Element
   */
  getCaretOffsets(element: Node, range?: Range) {
    if (!range) {
      const sel = window.getSelection()
      if (!sel || sel.rangeCount === 0) {
        return { left: 0, right: 0 }
      }
      range = sel.getRangeAt(0)
    }

    const preCaretRange = range.cloneRange()
    const postCaretRange = range.cloneRange()

    preCaretRange.selectNodeContents(element)
    preCaretRange.setEnd(range.endContainer, range.endOffset)

    postCaretRange.selectNodeContents(element)
    postCaretRange.setStart(range.endContainer, range.endOffset)

    return {
      left: preCaretRange.toString().length,
      right: postCaretRange.toString().length,
    }
  }

  selectNode(node: Node) {
    const range = this.doc.createRange()
    range.selectNodeContents(node)
    this.selectRange(range)
  }

  select(startNode: Node, startOffset: number, endNode?: Node, endOffset?: number) {
    const range = this.doc.createRange()

    // Defensive bounds checking to prevent "Failed to execute 'setStart' on 'Range': There is no child at offset N" errors
    // For element nodes, offset must be <= childNodes.length
    // For text nodes, offset must be <= node.length
    const clampOffset = (node: Node, offset: number): number => {
      if (offset < 0) return 0
      if (node.nodeType === 3) {
        // Text node
        return Math.min(offset, (node as Text).length)
      }
      // Element node
      return Math.min(offset, node.childNodes.length)
    }

    startOffset = clampOffset(startNode, startOffset)
    range.setStart(startNode, startOffset)

    if (endNode) {
      endOffset = clampOffset(endNode, endOffset!)
      range.setEnd(endNode, endOffset)
    } else {
      range.collapse(true)
    }
    this.selectRange(range)
    return range
  }

  setFocus(focusNode: Node, focusOffset: number) {
    const selection = this.doc.getSelection()
    // Clamp focusOffset to prevent out-of-bounds errors
    if (focusNode.nodeType === 3) {
      focusOffset = Math.min(focusOffset, (focusNode as Text).length)
    } else {
      focusOffset = Math.min(focusOffset, focusNode.childNodes.length)
    }
    if (focusOffset < 0) focusOffset = 0
    selection?.extend(focusNode, focusOffset)
  }

  /**
   *  Clear the current highlighted selection and set the caret to the start or the end of that prior selection, defaults to end.
   *
   *  @param {boolean} moveCursorToStart  A boolean representing whether or not to set the caret to the beginning of the prior selection.
   */
  clearSelection(moveCursorToStart?: boolean) {
    const sel = this.doc.getSelection()
    if (!sel || !sel.rangeCount) return
    if (moveCursorToStart) {
      sel.collapseToStart()
    } else {
      sel.collapseToEnd()
    }
  }

  /**
   * Move cursor to the given node with the given offset.
   *
   * @param  {DomElement}  node    Element where to jump
   * @param  {integer}     offset  Where in the element should we jump, 0 by default
   */
  moveCursor(node: Node, offset: number) {
    this.select(node, offset)
  }

  getSelectionRange(): Range | null {
    const selection = this.doc.getSelection()
    if (!selection || selection.rangeCount === 0) {
      return null
    }
    return selection.getRangeAt(0)
  }

  selectRange(range: Range) {
    const selection = this.doc.getSelection()
    if (!selection) return

    selection.removeAllRanges()
    selection.addRange(range)
  }

  // https://stackoverflow.com/questions/1197401/
  // how-can-i-get-the-element-the-caret-is-in-with-javascript-when-using-contenteditable
  // by You
  getSelectionStart(): Node | null {
    const sel = this.doc.getSelection()
    const node = sel?.anchorNode ?? null
    const startNode = node && node.nodeType === 3 ? node.parentNode : node

    return startNode
  }

  setCursorRange(cursorRange: { anchor: { key: string; offset: number }; focus: { key: string; offset: number } }) {
    const { anchor, focus } = cursorRange

    // Guard against empty or invalid keys that would cause querySelector('#') to crash
    if (!anchor.key || !focus.key) return

    const anchorParagraph = document.querySelector(`#${anchor.key}`)
    const focusParagraph = document.querySelector(`#${focus.key}`)

    // Guard against missing DOM elements
    if (!anchorParagraph || !focusParagraph) return

    const getNodeAndOffset = (node: Node | null, offset: number): { node: Node; offset: number } => {
      if (!node) return { node: document, offset: 0 }
      if (node.nodeType === 3) {
        return {
          node,
          offset,
        }
      }

      const childNodes = node.childNodes
      const len = childNodes.length
      let i: number
      let count = 0
      for (i = 0; i < len; i++) {
        const child = childNodes[i] as HTMLElement
        const textContent = getTextContent(child, [CLASS_OR_ID.AG_MATH_RENDER, CLASS_OR_ID.AG_RUBY_RENDER])
        const textLength = textContent.length
        if ((child as Element).classList?.contains(CLASS_OR_ID.AG_FRONT_ICON)) {
          continue
        }

        // Fix #1460 - put the cursor at the next text node or element if it can be put at the last of /^\n$/ or the next text node/element.
        if (/^\n$/.test(textContent) && i !== len - 1 ? count + textLength > offset : count + textLength >= offset) {
          if ((child as Element).classList?.contains('ag-inline-image')) {
            const imageContainer = (child as Element).querySelector('.ag-image-container')
            const hasImg = imageContainer?.querySelector('img')

            if (!hasImg) {
              return {
                node: child,
                offset: 0,
              }
            }
            if (count + textLength === offset) {
              if (child.nextElementSibling) {
                return {
                  node: child.nextElementSibling,
                  offset: 0,
                }
              } else {
                return {
                  node: imageContainer!,
                  offset: 1,
                }
              }
            } else if (count === offset && count === 0) {
              return {
                node: imageContainer!,
                offset: 0,
              }
            } else {
              return {
                node: child,
                offset: 0,
              }
            }
          } else {
            return getNodeAndOffset(child, offset - count)
          }
        } else {
          count += textLength
        }
      }
      return { node, offset }
    }

    let { node: anchorNode, offset: anchorOffset } = getNodeAndOffset(anchorParagraph, anchor.offset)
    let { node: focusNode, offset: focusOffset } = getNodeAndOffset(focusParagraph, focus.offset)

    if (
      anchorNode.nodeType === 3 ||
      (anchorNode.nodeType === 1 && !(anchorNode as Element).classList.contains('ag-image-container'))
    ) {
      anchorOffset = Math.min(anchorOffset, (anchorNode.textContent ?? '').length)
      focusOffset = Math.min(focusOffset, (focusNode.textContent ?? '').length)
    }

    // First set the anchor node and anchor offset, make it collapsed
    this.select(anchorNode, anchorOffset)
    // Secondly, set the focus node and focus offset.
    this.setFocus(focusNode, focusOffset)
  }

  isValidCursorNode(node: Node | null): Element | null {
    if (!node) return null
    if (node.nodeType === 3) {
      node = node.parentNode
    }

    return (node as Element)?.closest('span.ag-paragraph') ?? null
  }

  getCursorRange() {
    const sel = this.doc.getSelection()
    if (!sel) {
      return new Cursor({
        start: null,
        end: null,
        anchor: null,
        focus: null,
      })
    }
    let { anchorNode, anchorOffset, focusNode, focusOffset } = sel
    const isAnchorValid = this.isValidCursorNode(anchorNode)
    const isFocusValid = this.isValidCursorNode(focusNode)
    let needFix = false
    if (!isAnchorValid && isFocusValid) {
      needFix = true
      anchorNode = focusNode
      anchorOffset = focusOffset
    } else if (isAnchorValid && !isFocusValid) {
      needFix = true
      focusNode = anchorNode
      focusOffset = anchorOffset
    } else if (!isAnchorValid && !isFocusValid) {
      const editor = document.querySelector('#ag-editor-id')?.parentNode as HTMLElement | null
      editor?.blur()

      return new Cursor({
        start: null,
        end: null,
        anchor: null,
        focus: null,
      })
    }

    // fix bug click empty line, the cursor will jump to the end of pre line.
    if (
      anchorNode === focusNode &&
      anchorOffset === focusOffset &&
      anchorNode!.textContent === '\n' &&
      focusOffset === 0
    ) {
      focusOffset = anchorOffset = 1
    }

    const anchorParagraph = findNearestParagraph(anchorNode)
    const focusParagraph = findNearestParagraph(focusNode)

    // Guard against null paragraphs or empty IDs — prevents querySelector('#') crash
    if (!anchorParagraph || !focusParagraph || !anchorParagraph.id || !focusParagraph.id) {
      return new Cursor({
        start: null,
        end: null,
        anchor: null,
        focus: null,
      })
    }

    let aOffset = getOffsetOfParagraph(anchorNode!, anchorParagraph) + anchorOffset
    let fOffset = getOffsetOfParagraph(focusNode!, focusParagraph) + focusOffset

    // fix input after image.
    if (
      anchorNode === focusNode &&
      anchorOffset === focusOffset &&
      (anchorNode!.parentNode as HTMLElement)?.classList?.contains('ag-image-container') &&
      (anchorNode as Element)?.previousElementSibling &&
      (anchorNode as Element).previousElementSibling!.nodeName === 'IMG'
    ) {
      const imageWrapper = anchorNode!.parentNode!.parentNode
      const preElement = (imageWrapper as Element)?.previousElementSibling
      aOffset = 0
      if (preElement) {
        aOffset += getOffsetOfParagraph(preElement, anchorParagraph!)
        aOffset += getTextContent(preElement, [CLASS_OR_ID.AG_MATH_RENDER, CLASS_OR_ID.AG_RUBY_RENDER]).length
      }
      aOffset += getTextContent(imageWrapper as Node, [CLASS_OR_ID.AG_MATH_RENDER, CLASS_OR_ID.AG_RUBY_RENDER]).length
      fOffset = aOffset
    }

    if (
      anchorNode === focusNode &&
      anchorNode!.nodeType === 1 &&
      (anchorNode as Element).classList.contains('ag-image-container')
    ) {
      const imageWrapper = anchorNode!.parentNode
      const preElement = (imageWrapper as Element)?.previousElementSibling
      aOffset = 0
      if (preElement) {
        aOffset += getOffsetOfParagraph(preElement, anchorParagraph!)
        aOffset += getTextContent(preElement, [CLASS_OR_ID.AG_MATH_RENDER, CLASS_OR_ID.AG_RUBY_RENDER]).length
      }
      if (anchorOffset === 1) {
        aOffset += getTextContent(imageWrapper as Node, [CLASS_OR_ID.AG_MATH_RENDER, CLASS_OR_ID.AG_RUBY_RENDER]).length
      }
      fOffset = aOffset
    }

    const anchor = { key: anchorParagraph!.id, offset: aOffset }

    const focus = { key: focusParagraph!.id, offset: fOffset }
    const result = new Cursor({ anchor, focus })

    if (needFix) {
      this.setCursorRange({ anchor, focus })
    }

    return result
  }

  // topOffset is the line counts above cursor, and bottomOffset is line counts below cursor.
  getCursorYOffset(paragraph: HTMLElement) {
    const { y } = this.getCursorCoords()
    const { height, top } = paragraph.getBoundingClientRect()
    const lineHeight = parseFloat(getComputedStyle(paragraph).lineHeight)
    const topOffset = Math.round((y - top) / lineHeight)
    const bottomOffset = Math.round((top + height - lineHeight - y) / lineHeight)

    return {
      topOffset,
      bottomOffset,
    }
  }

  getCursorCoords() {
    const sel = this.doc.getSelection()
    let range: Range | undefined
    let x = 0
    let y = 0
    let width = 0

    if (sel?.rangeCount) {
      range = sel.getRangeAt(0).cloneRange()
      if (range.getClientRects) {
        // range.collapse(true)
        let rects = range.getClientRects()
        if (
          rects.length === 0 &&
          range.startContainer &&
          (range.startContainer.nodeType === Node.ELEMENT_NODE || range.startContainer.nodeType === Node.TEXT_NODE)
        ) {
          rects = (range.startContainer as Element).parentElement!.getClientRects()
          // prevent tiny vibrations
          if (rects.length) {
            const rect = rects[0]
            rect.y = rect.y + 1
          }
        }
        if (rects.length) {
          const { left, top, x: rectX, y: rectY, width: rWidth } = rects[0]
          x = rectX || left
          y = rectY || top
          width = rWidth
        }
      }
    }

    return { x, y, width }
  }

  getSelectionEnd(): Node | null {
    const sel = this.doc.getSelection()
    const node = sel?.focusNode ?? null
    const endNode = node && node.nodeType === 3 ? node.parentNode : node

    return endNode
  }
}

export default new Selection(document)
