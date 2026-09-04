<template>
  <div>
    <template v-if="variant === 'preferences'">
      <div class="title-bar title-bar-preferences">
        <div class="frameless-titlebar-button frameless-titlebar-close" @click.stop="handleCloseClick">
          <div>
            <svg width="10" height="10">
              <path :d="windowIconClose" />
            </svg>
          </div>
        </div>
      </div>
    </template>
    <template v-else>
      <div
        class="title-bar-editor-bg"
        :class="{ 'tabs-visible': showTabBar }"
      ></div>
      <div
        class="title-bar"
        :class="[{ 'active': active }, { 'tabs-visible': showTabBar }, { 'frameless': titleBarStyle === 'custom' }, { 'isOsx': isOsx }]"
      >
        <div class="title" @dblclick.stop="toggleMaxmizeOnMacOS">
          <span v-if="filename">
            <span
              class="filename"
              :class="{'isOsx': platform === 'darwin'}"
              @click="rename"
            >
              {{ filename }}
            </span>
            <span class="save-dot" :class="{'show': !isSaved}"></span>
          </span>
        </div>
        <div :class="showCustomTitleBar ? 'left-toolbar title-no-drag' : 'right-toolbar'">
          <div
            v-if="showCustomTitleBar"
            class="frameless-titlebar-menu title-no-drag"
            @click.stop="handleMenuClick"
          >
            <span class="text-center-vertical">&#9776;</span>
          </div>
          <div
            v-if="wordCount"
            class="word-count item"
            :class="[{ 'title-no-drag': platform !== 'darwin' }]"
            @click.stop="handleWordClick"
          >
            <span class="text-center-vertical">{{ `${HASH[show].short} ${wordCount[show]}` }}</span>
          </div>
        </div>
        <div
          v-if="titleBarStyle === 'custom' && !isFullScreen && !isOsx"
          class="right-toolbar"
          :class="[{ 'title-no-drag': titleBarStyle === 'custom' }]"
        >
          <div class="frameless-titlebar-button frameless-titlebar-close" @click.stop="handleCloseClick">
            <div>
              <svg width="10" height="10">
                <path :d="windowIconClose" />
              </svg>
            </div>
          </div>
          <div class="frameless-titlebar-button frameless-titlebar-toggle" @click.stop="handleMaximizeClick">
            <div>
              <svg width="10" height="10">
                <path v-show="!isMaximized" :d="windowIconMaximize" />
                <path v-show="isMaximized" :d="windowIconRestore" />
              </svg>
            </div>
          </div>
          <div class="frameless-titlebar-button frameless-titlebar-minimize" @click.stop="handleMinimizeClick">
            <div>
              <svg width="10" height="10">
                <path :d="windowIconMinimize" />
              </svg>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script>
import { minimizePath, restorePath, maximizePath, closePath } from '../../assets/window-controls.js'
import { isOsx } from '@/util'
import { useLayoutStore } from '@/store/pinia/layout'
import { usePreferencesStore } from '@/store/pinia/preferences'

export default {
  data() {
    return {
      isFullScreen: false,
      isMaximized: false,
      show: 'word',
      isOsx,
      HASH: {
        word: { short: 'W', full: 'word' },
        character: { short: 'C', full: 'character' },
        paragraph: { short: 'P', full: 'paragraph' },
        all: { short: 'A', full: '(with space)character' },
      },
      windowIconMinimize: minimizePath,
      windowIconRestore: restorePath,
      windowIconMaximize: maximizePath,
      windowIconClose: closePath,
    }
  },
  async created() {
    this.updateDocumentTitle()
    this.syncWindowDocumentState()
    // Initialize window state via preload API (with fallback if window.api not ready)
    if (window.api) {
      this.isFullScreen = await window.api.window.isFullScreen()
      this.isMaximized = await window.api.window.isMaximized()
    }
    window.api.ipc.on('mt::window-maximize', this.onMaximize)
    window.api.ipc.on('mt::window-unmaximize', this.onUnmaximize)
    window.api.ipc.on('mt::window-enter-full-screen', this.onEnterFullScreen)
    window.api.ipc.on('mt::window-leave-full-screen', this.onLeaveFullScreen)
  },
  props: {
    variant: {
      type: String,
      default: 'editor',
    },
    project: Object,
    filename: String,
    pathname: String,
    active: Boolean,
    wordCount: Object,
    platform: String,
    isSaved: Boolean,
  },
  computed: {
    titleBarStyle() {
      return usePreferencesStore().titleBarStyle
    },
    showTabBar() {
      return useLayoutStore().showTabBar
    },
    projectName() {
      return this.project?.name || ''
    },
    showCustomTitleBar() {
      return this.titleBarStyle === 'custom' && !this.isOsx
    },
  },
  watch: {
    filename() {
      this.updateDocumentTitle()
      this.syncWindowDocumentState()
    },
    pathname() {
      this.syncWindowDocumentState()
    },
    isSaved() {
      this.syncWindowDocumentState()
    },
    projectName() {
      this.updateDocumentTitle()
    },
  },
  methods: {
    updateDocumentTitle() {
      if (this.filename) {
        document.title = this.projectName ? `${this.filename} - ${this.projectName}` : `${this.filename} - Vien`
      } else {
        document.title = this.projectName || 'Vien'
      }
    },

    syncWindowDocumentState() {
      if (!window.api?.ipc) {
        return
      }
      window.api.ipc.send('mt::window-document-state', {
        filename: this.filename || '',
        pathname: this.pathname || '',
        isSaved: typeof this.isSaved === 'boolean' ? this.isSaved : true,
      })
    },

    handleWordClick() {
      const ITEMS = ['word', 'paragraph', 'character', 'all']
      const len = ITEMS.length
      let index = ITEMS.indexOf(this.show)
      index += 1
      if (index >= len) index = 0
      this.show = ITEMS[index]
    },

    handleCloseClick() {
      window.api.window.close()
    },

    handleMaximizeClick() {
      window.api.window.toggleMaximize()
    },

    toggleMaxmizeOnMacOS() {
      if (this.isOsx) {
        this.handleMaximizeClick()
      }
    },

    handleMinimizeClick() {
      window.api.window.minimize()
    },

    handleMenuClick() {
      window.api.contextMenu.showAppMenu(23, 20)
    },

    rename() {
      if (this.platform === 'darwin') {
        this.$store.dispatch('RESPONSE_FOR_RENAME')
      }
    },

    onMaximize() {
      this.isMaximized = true
    },
    onUnmaximize() {
      this.isMaximized = false
    },
    onEnterFullScreen() {
      this.isFullScreen = true
    },
    onLeaveFullScreen() {
      this.isFullScreen = false
    },
  },
  beforeUnmount() {
    window.api.ipc.off('mt::window-maximize', this.onMaximize)
    window.api.ipc.off('mt::window-unmaximize', this.onUnmaximize)
    window.api.ipc.off('mt::window-enter-full-screen', this.onEnterFullScreen)
    window.api.ipc.off('mt::window-leave-full-screen', this.onLeaveFullScreen)
  },
}
</script>

<style scoped>
  .title-bar-editor-bg {
    height: var(--titleBarHeight);
    background: var(--editorBgColor);
    box-shadow: inset 0 -1px 0 var(--editorColor04);
    position: relative;
    left: 0;
    top: 0;
    right: 0;
  }
  .title-bar {
    -webkit-app-region: drag;
    user-select: none;
    background: transparent;
    height: var(--titleBarHeight);
    box-sizing: border-box;
    color: var(--editorColor50);
    position: fixed;
    left: 0;
    top: 0;
    right: 0;
    z-index: 2;
    backdrop-filter: blur(18px);
    transition: color .4s ease-in-out;
    cursor: default;
  }
  .active {
    color: var(--editorColor);
  }
  .title {
    padding: 0 142px;
    height: 100%;
    line-height: var(--titleBarHeight);
    font-size: 13px;
    text-align: center;
    transition: all .25s ease-in-out;
    & .filename {
      transition: all .25s ease-in-out;
    }
  }
  div.title > span {
    /* Workaround for GH#339 */
    display: block;
    direction: rtl;
    overflow: hidden;
    text-overflow: clip;
    white-space: nowrap;
  }

  .title-bar .title .filename.isOsx:hover {
    color: var(--themeColor);
  }

  .active .save-dot {
    margin-left: 3px;
    width: 7px;
    height: 7px;
    display: inline-block;
    border-radius: 50%;
    background: var(--highlightThemeColor);
    opacity: .7;
    visibility: hidden;
  }
  .active .save-dot.show {
    visibility: visible;
  }
  .title:hover {
    color: var(--sideBarTitleColor);
  }

  .left-toolbar {
    padding: 0 10px;
    height: 100%;
    position: absolute;
    top: 0;
    left: 0;
    width: 118px; /* + 2*10px padding*/
    display: flex;
    align-items: center;
    flex-direction: row;
  }
  .right-toolbar {
    height: 100%;
    position: absolute;
    top: 0;
    right: 0;
    width: 138px;
    display: flex;
    align-items: center;
    flex-direction: row-reverse;
    & .item {
      margin-right: 10px;
    }
  }

  .word-count {
    cursor: pointer;
    font-size: 12px;
    color: var(--editorColor30);
    text-align: center;
    line-height: 24px;
    padding: 0 5px;
    box-sizing: border-box;
    transition: all .25s ease-in-out;
    &:hover > span {
      color: var(--sideBarTitleColor);
    }
  }

  .title-no-drag {
    -webkit-app-region: no-drag;
  }
  /* frameless window controls */
  .frameless-titlebar-button {
    position: relative;
    display: block;
    width: 46px;
    height: var(--titleBarHeight);
  }
  .frameless-titlebar-button > div {
    position: absolute;
    display: inline-flex;
    top: 50%;
    left: 50%;
    transform: translateX(-50%) translateY(-50%);
  }
  .frameless-titlebar-menu {
    color: var(--sideBarColor);
  }
  .frameless-titlebar-close:hover {
    background-color: rgb(228, 79, 79);
  }
  .frameless-titlebar-minimize:hover,
  .frameless-titlebar-toggle:hover {
    background-color: rgba(0, 0, 0, 0.1);
  }
  .frameless-titlebar-button svg {
    fill: #000000
  }
  .frameless-titlebar-close:hover svg {
    fill: #ffffff
  }

  .text-center-vertical {
    display: inline-block;
    vertical-align: middle;
    line-height: normal;
  }
</style>
