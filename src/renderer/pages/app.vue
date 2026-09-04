<template>
  <div
    class="editor-container"
  >
    <side-bar v-if="init"></side-bar>
    <div class="editor-middle">
      <title-bar
        :project="projectTree"
        :pathname="pathname"
        :filename="filename"
        :active="windowActive"
        :word-count="wordCount"
        :platform="platform"
        :is-saved="isSaved"
      ></title-bar>
      <div class="editor-placeholder" v-if="!init"></div>
      <editor-with-tabs
        v-if="hasCurrentFile && init"
        :markdown="markdown"
        :cursor="cursor"
        :source-code="sourceCode"
        :show-tab-bar="showTabBar"
        :text-direction="textDirection"
        :platform="platform"
      ></editor-with-tabs>
      <command-palette></command-palette>
      <about-dialog></about-dialog>
      <export-setting-dialog></export-setting-dialog>
      <rename></rename>
      <recovery-center></recovery-center>
    </div>
  </div>
</template>

<script>
import { addStyles, addThemeStyle } from '@/util/theme'
import EditorWithTabs from '@/components/editorWithTabs'
import TitleBar from '@/components/titleBar'
import SideBar from '@/components/sideBar'
import AboutDialog from '@/components/about'
import CommandPalette from '@/components/commandPalette'
import ExportSettingDialog from '@/components/exportSettings'
import Rename from '@/components/rename'
import RecoveryCenter from '@/components/recoveryCenter'
import { loadingPageMixins } from '@/mixins'
import { DEFAULT_STYLE } from '@/config'
import { useAutoUpdatesStore } from '@/store/pinia/autoUpdates'
import { useCommandCenterStore } from '@/store/pinia/commandCenter'
import { useLayoutStore } from '@/store/pinia/layout'
import { useNotificationStore } from '@/store/pinia/notification'
import { usePreferencesStore } from '@/store/pinia/preferences'

export default {
  name: 'marktext',
  components: {
    EditorWithTabs,
    TitleBar,
    SideBar,
    AboutDialog,
    ExportSettingDialog,
    Rename,
    CommandPalette,
    RecoveryCenter,
  },
  mixins: [loadingPageMixins],
  computed: {
    layoutStore() {
      return useLayoutStore()
    },
    preferencesStore() {
      return usePreferencesStore()
    },
    showTabBar() {
      return this.layoutStore.showTabBar
    },
    sourceCode() {
      return this.preferencesStore.sourceCode
    },
    theme() {
      return this.preferencesStore.theme
    },
    textDirection() {
      return this.preferencesStore.textDirection
    },
    zoom() {
      return this.preferencesStore.zoom
    },
    projectTree() {
      return this.$store.state.project.projectTree
    },
    pathname() {
      return this.$store.state.editor.currentFile.pathname
    },
    filename() {
      return this.$store.state.editor.currentFile.filename
    },
    isSaved() {
      return this.$store.state.editor.currentFile.isSaved
    },
    markdown() {
      return this.$store.state.editor.currentFile.markdown
    },
    cursor() {
      return this.$store.state.editor.currentFile.cursor
    },
    wordCount() {
      return this.$store.state.editor.currentFile.wordCount
    },
    windowActive() {
      return this.$store.state.windowActive
    },
    platform() {
      return this.$store.state.platform
    },
    init() {
      return this.$store.state.init
    },
    hasCurrentFile() {
      return this.markdown !== undefined
    },
  },
  created() {
    const { dispatch } = this.$store
    const commandCenterStore = useCommandCenterStore()
    const layoutStore = useLayoutStore()
    const preferencesStore = usePreferencesStore()

    if (window.marktext.initialState) {
      preferencesStore.setUserPreference(window.marktext.initialState)
    }

    this.$watch('theme', (value, oldValue) => {
      if (value !== oldValue) {
        addThemeStyle(value)
      }
    })
    this.$watch('zoom', (zoom) => {
      window.api.localEmit('mt::window-zoom', zoom)
    })

    dispatch('LINTEN_WIN_STATUS')
    commandCenterStore.listen()
    layoutStore.listen()
    dispatch('LISTEN_FOR_EDIT')
    preferencesStore.listenForView()
    dispatch('LISTEN_FOR_SHOW_DIALOG')
    dispatch('LISTEN_FOR_PARAGRAPH_INLINE_STYLE')
    dispatch('LISTEN_FOR_UPDATE_PROJECT')
    dispatch('LISTEN_FOR_LOAD_PROJECT')
    dispatch('LISTEN_FOR_SIDEBAR_CONTEXT_MENU')
    useAutoUpdatesStore().listen()
    dispatch('LISTEN_SCREEN_SHOT')
    preferencesStore.askForUserPreference()
    preferencesStore.listenToggleView()
    dispatch('LISTEN_FOR_CLOSE')
    dispatch('LISTEN_FOR_SAVE_AS')
    dispatch('LISTEN_FOR_MOVE_TO')
    dispatch('LISTEN_FOR_SAVE')
    dispatch('LISTEN_FOR_SET_PATHNAME')
    dispatch('LISTEN_FOR_BOOTSTRAP_WINDOW')
    dispatch('LISTEN_FOR_SAVE_CLOSE')
    dispatch('LISTEN_FOR_RENAME')
    dispatch('LINTEN_FOR_SET_LINE_ENDING')
    dispatch('LINTEN_FOR_SET_ENCODING')
    dispatch('LINTEN_FOR_SET_FINAL_NEWLINE')
    dispatch('LISTEN_FOR_NEW_TAB')
    dispatch('LISTEN_FOR_CLOSE_TAB')
    dispatch('LISTEN_FOR_TAB_CYCLE')
    dispatch('LISTEN_FOR_SWITCH_TABS')
    dispatch('LINTEN_FOR_PRINT_SERVICE_CLEARUP')
    dispatch('LINTEN_FOR_EXPORT_SUCCESS')
    dispatch('LISTEN_FOR_FILE_CHANGE')
    dispatch('LISTEN_WINDOW_ZOOM')
    dispatch('LISTEN_FOR_RELOAD_IMAGES')
    dispatch('LISTEN_FOR_CONTEXT_MENU')
    useNotificationStore().listen()

    this.$nextTick(() => {
      const style = window.marktext.initialState || DEFAULT_STYLE
      addStyles(style)
      this.hideLoadingPage()
    })
  },
}
</script>

<style scoped>
  .editor-placeholder,
  .editor-container {
    display: flex;
    flex-direction: row;
    position: absolute;
    width: 100vw;
    height: 100vh;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
  }
  .editor-container .hide {
    z-index: -1;
    opacity: 0;
    position: absolute;
    left: -10000px;
  }
  .editor-placeholder {
    background: var(--editorBgColor);
  }
  .editor-middle {
    display: flex;
    flex-direction: column;
    flex: 1;
    /* A row-flex item defaults to min-width:auto, so its automatic minimum
       tracks the content's min-content width. Wide blocks (e.g. a table
       whose min-content exceeds the window) would blow the whole editor
       column past the viewport, pushing centered previews (mermaid) mostly
       off-screen: blank left slice, diagram shifted right, clipped right.
       min-width: 0 keeps the column at viewport width; wide tables/code
       already scroll inside their own blocks. */
    min-width: 0;
    min-height: 100vh;
    position: relative;
    background: var(--editorBgColor);
    & > .editor {
      flex: 1;
    }
  }
</style>
