<template>
  <div
    class="source-code"
    ref="sourceCode"
  >
  </div>
</template>

<script>
import { markRaw } from 'vue'
import codeMirror, { setMode, setCursorAtLastLine, setTextDirection } from '../../codeMirror'
import { wordCount as getWordCount } from 'muya/lib/utils'
import { adjustCursor } from '../../util'
import bus from '../../bus'
import { oneDarkThemes, railscastsThemes } from '@/config'
import { usePreferencesStore } from '@/store/pinia/preferences'

export default {
  props: {
    markdown: String,
    cursor: Object,
    textDirection: {
      type: String,
      required: true,
    },
  },

  computed: {
    preferencesStore() {
      return usePreferencesStore()
    },
    preferenceTheme() {
      return this.preferencesStore.theme
    },
    sourceCode() {
      return this.preferencesStore.sourceCode
    },
    currentTab() {
      return this.$store.state.editor.currentFile
    },
  },

  data() {
    return {
      contentState: null,
      editor: null,
      commitTimer: null,
      viewDestroyed: false,
      tabId: null,
    }
  },

  watch: {
    '$props.textDirection': function (value, oldValue) {
      const { editor } = this
      if (value !== oldValue && editor) {
        setTextDirection(editor, value)
      }
    },
  },

  created() {
    this.$nextTick(() => {
      // TODO: Should we load markdown from the tab or mapped vue property?
      const { id } = this.currentTab
      const { markdown = '', preferenceTheme, cursor, textDirection } = this
      const container = this.$refs.sourceCode
      const codeMirrorConfig = {
        value: markdown,
        lineNumbers: true,
        autofocus: true,
        lineWrapping: true,
        styleActiveLine: true,
        direction: textDirection,
        // The amount of updates needed when scrolling. Settings this to >Infinity< or use CSS
        // >height: auto< result in bad performance because the whole document is always rendered.
        // Since we are using >height: auto< setting this to >Infinity< to fix #171. The best
        // solution would be to set a fixed height like in #791 but then the scrollbar is not on
        // the right side. Please also see CodeMirror#1104.
        viewportMargin: Infinity,
        lineNumberFormatter(line) {
          if (line % 10 === 0 || line === 1) {
            return line
          } else {
            return ''
          }
        },
      }

      // Set theme
      if (railscastsThemes.includes(preferenceTheme)) {
        codeMirrorConfig.theme = 'railscasts'
      } else if (oneDarkThemes.includes(preferenceTheme)) {
        codeMirrorConfig.theme = 'one-dark'
      }

      // Init CodeMirror
      const editor = codeMirror(container, codeMirrorConfig)
      // CodeMirror owns a mutable line tree. Vue must not proxy it because
      // proxying can corrupt CodeMirror's internal parent/child references.
      this.editor = markRaw(editor)

      bus.on('file-loaded', this.handleFileChange)
      bus.on('invalidate-image-cache', this.handleInvalidateImageCache)
      bus.on('file-changed', this.handleFileChange)
      bus.on('selectAll', this.handleSelectAll)
      bus.on('image-action', this.handleImageAction)
      bus.on('undo', this.handleUndo)
      bus.on('redo', this.handleRedo)
      bus.on('flush-active-editor', this.flushActiveEditor)

      setMode(editor, 'markdown')
      this.listenChange()

      editor.on('contextmenu', (_cm, event) => {
        // Make sure no context menu is shown in source-code mode because we have to handle
        // Muyas menu by Electron.
        event.preventDefault()
        event.stopPropagation()
      })

      // NOTE: Cursor may be not null but the inner values are.
      if (cursor?.anchor && cursor.focus) {
        const { anchor, focus } = cursor
        editor.setSelection(anchor, focus, { scroll: true }) // Scroll the focus into view.
      } else {
        setCursorAtLastLine(editor)
      }
      this.tabId = id
    })
  },
  beforeUnmount() {
    // NOTE: Clear timer and manually commit changes. After mode switching and cleanup may follow
    // further key inputs, so ignore all inputs.
    this.viewDestroyed = true
    if (this.commitTimer) clearTimeout(this.commitTimer)

    bus.off('file-loaded', this.handleFileChange)
    bus.off('invalidate-image-cache', this.handleInvalidateImageCache)
    bus.off('file-changed', this.handleFileChange)
    bus.off('selectAll', this.handleSelectAll)
    bus.off('image-action', this.handleImageAction)
    bus.off('undo', this.handleUndo)
    bus.off('redo', this.handleRedo)
    bus.off('flush-active-editor', this.flushActiveEditor)

    const { editor } = this
    const { cursor, markdown } = this.getMarkdownAndCursor(editor)
    bus.emit('file-changed', { id: this.tabId, markdown, cursor, renderCursor: true })
    editor.destroy()
    this.editor = null
  },
  methods: {
    handleImageAction({ id, result, alt }) {
      const { editor } = this
      const value = editor.getValue()
      const focus = editor.getCursor('focus')
      const anchor = editor.getCursor('anchor')
      const lines = value.split('\n')
      const index = lines.findIndex((line) => line.indexOf(id) > 0)

      if (index > -1) {
        const oldLine = lines[index]
        lines[index] = oldLine.replace(new RegExp(`!\\[${id}\\]\\(.*\\)`), `![${alt}](${result})`)
        const newValue = lines.join('\n')
        editor.setValue(newValue)
        const match = /(!\[.*\]\(.*\))/.exec(oldLine)
        if (!match) {
          // User maybe delete `![]()` structure, and the match is null.
          return
        }
        const range = {
          start: match.index,
          end: match.index + match[1].length,
        }
        const delta = alt.length + result.length + 5 - match[1].length

        const adjust = (pointer) => {
          if (!pointer) {
            return
          }
          if (pointer.line !== index) {
            return
          }
          if (pointer.ch <= range.start) {
            // do nothing.
          } else if (pointer.ch > range.start && pointer.ch < range.end) {
            pointer.ch = range.start + alt.length + result.length + 5
          } else {
            pointer.ch += delta
          }
        }

        adjust(focus)
        adjust(anchor)
        if (focus && anchor) {
          editor.setSelection(anchor, focus, { scroll: true })
        } else {
          setCursorAtLastLine(editor)
        }
      }
    },
    listenChange() {
      const { editor } = this
      editor.on('cursorActivity', () => {
        if (this.commitTimer) clearTimeout(this.commitTimer)
        this.commitTimer = setTimeout(() => {
          this.flushActiveEditor()
        }, 150)
      })
    },
    // Persist the live CodeMirror buffer synchronously before save/close/move
    // actions serialize Vuex state. This closes the debounce data-loss window.
    flushActiveEditor() {
      if (this.commitTimer) {
        clearTimeout(this.commitTimer)
        this.commitTimer = null
      }
      if (this.viewDestroyed || !this.editor) {
        return
      }
      if (!this.tabId) {
        console.warn('LISTEN_FOR_CONTENT_CHANGE: Cannot commit changes because no tab id was set!')
        return
      }

      const { cursor, markdown } = this.getMarkdownAndCursor(this.editor)
      // Attention: the cursor may be `{focus: null, anchor: null}` after Backspace.
      const wordCount = getWordCount(markdown)
      this.$store.dispatch('LISTEN_FOR_CONTENT_CHANGE', {
        id: this.tabId,
        markdown,
        wordCount,
        cursor,
      })
    },
    // Another tab was selected - only listen to get changes but don't set history or other things.
    handleFileChange({ id, markdown, cursor }) {
      this.prepareTabSwitch()

      const { editor } = this
      if (typeof markdown === 'string') {
        editor.setValue(markdown)
      }
      // Cursor is null when loading a file or creating a new tab in source code mode.
      if (cursor) {
        const { anchor, focus } = cursor
        editor.setSelection(anchor, focus, { scroll: true }) // Scroll the focus into view.
      } else {
        setCursorAtLastLine(editor)
      }
      this.tabId = id
    },
    // Get markdown and cursor from CodeMirror.
    getMarkdownAndCursor(cm) {
      let focus = cm.getCursor('head')
      let anchor = cm.getCursor('anchor')
      const markdown = cm.getValue()
      const convertToMuyaCursor = (cursor) => {
        const line = cm.getLine(cursor.line)
        const preLine = cm.getLine(cursor.line - 1)
        const nextLine = cm.getLine(cursor.line + 1)
        return adjustCursor(cursor, preLine, line, nextLine)
      }

      anchor = convertToMuyaCursor(anchor) // Selection start as Muya cursor
      focus = convertToMuyaCursor(focus) // Selection end as Muya cursor

      // Normalize cursor that `anchor` is always before `focus` because
      // this is the expected behavior in Muya.
      if (anchor && focus && anchor.line > focus.line) {
        const tmpCursor = focus
        focus = anchor
        anchor = tmpCursor
      }
      return { cursor: { focus, anchor }, markdown }
    },
    // Commit changes from old tab. Problem: tab was already switched, so commit changes with old tab id.
    prepareTabSwitch() {
      if (this.tabId) {
        this.flushActiveEditor()
        this.tabId = null // invalidate tab id
      }
    },

    handleUndo() {
      this.editor?.undo()
    },

    handleRedo() {
      this.editor?.redo()
    },

    handleSelectAll() {
      if (!this.sourceCode) {
        return
      }

      const { editor } = this
      if (editor?.hasFocus()) {
        this.editor.execCommand('selectAll')
      } else {
        const activeElement = document.activeElement
        const nodeName = activeElement.nodeName
        if (nodeName === 'INPUT' || nodeName === 'TEXTAREA') {
          activeElement.select()
        }
      }
    },

    handleInvalidateImageCache() {
      if (this.editor) {
        this.editor.invalidateImageCache()
      }
    },
  },
}
</script>

<style>
  .source-code {
    height: calc(100vh - var(--titleBarHeight));
    box-sizing: border-box;
    overflow: auto;
  }
  .source-code .CodeMirror {
    height: auto;
    margin: 50px auto;
    max-width: var(--editorAreaWidth);
    background: transparent;
  }
  .source-code .cm-gutters {
    border-right: none;
    background-color: transparent;
  }
  .source-code .cm-activeLine,
  .source-code .cm-activeLineGutter {
    background: var(--floatHoverColor);
  }
</style>
