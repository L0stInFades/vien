<template>
  <div class="pref-container">
    <title-bar v-if="showCustomTitleBar" variant="preferences"></title-bar>
    <side-bar></side-bar>
    <div
      class="pref-content"
      :class="{ 'frameless': titleBarStyle === 'custom' || isOsx }"
    >
      <div class="title-bar" v-if="!showCustomTitleBar"></div>
      <router-view class="pref-setting"></router-view>
    </div>
  </div>
</template>

<script>
import TitleBar from '@/components/titleBar'
import SideBar from '@/prefComponents/sideBar'
import { loadingPageMixins } from '@/mixins'
import { addThemeStyle } from '@/util/theme'
import { DEFAULT_STYLE } from '@/config'
import { usePreferencesStore } from '@/store/pinia/preferences'
import { isOsx } from '@/util'

export default {
  data() {
    this.isOsx = isOsx
    return {}
  },
  mixins: [loadingPageMixins],
  components: {
    TitleBar,
    SideBar,
  },
  computed: {
    preferencesStore() {
      return usePreferencesStore()
    },
    currentTheme() {
      return this.preferencesStore.theme
    },
    titleBarStyle() {
      return this.preferencesStore.titleBarStyle
    },
    showCustomTitleBar() {
      return this.titleBarStyle === 'custom' && !this.isOsx
    },
  },
  created() {
    this.$watch('currentTheme', (value, oldValue) => {
      if (value !== oldValue) {
        addThemeStyle(value)
      }
    })

    this.$nextTick(() => {
      const state = window.marktext.initialState || DEFAULT_STYLE
      addThemeStyle(state.theme)

      usePreferencesStore().askForUserPreference()
      this.hideLoadingPage()
    })
  },
}
</script>

<style>
.pref-container {
  --prefSideBarWidth: 304px;

  width: 100vw;
  height: 100vh;
  max-width: 100vw;
  max-height: 100vh;
  position: fixed;
  top: 0;
  left: 0;
  display: flex;
  background:
    radial-gradient(circle at top right, rgba(255, 148, 117, 0.08), transparent 26%),
    radial-gradient(circle at bottom left, rgba(73, 118, 206, 0.1), transparent 28%),
    var(--editorBgColor);

  & h4 {
    margin: 0;
    font-weight: normal;
  }

  & h5 {
    font-weight: normal;
  }

  & .pref-content {
    position: relative;
    flex: 1;
    display: flex;
    flex-direction: column;
    max-width: calc(100vw - var(--prefSideBarWidth));
    padding: 20px 24px 22px 12px;
    box-sizing: border-box;
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.34), rgba(255, 255, 255, 0));
    & .title-bar {
      width: 100%;
      height: var(--titleBarHeight);
      position: fixed;
      top: 0;
      right: 0;
      -webkit-app-region: drag;
    }
    & .pref-setting {
      width: min(100%, 1032px);
      margin: 0 auto;
      padding: 46px 40px 68px;
      padding-top: var(--titleBarHeight);
      flex: 1;
      height: calc(100vh - var(--titleBarHeight));
      overflow: auto;
      box-sizing: border-box;
      border-radius: 34px;
      border: 1px solid var(--panelSurfaceBorderColor);
      background:
        radial-gradient(circle at top right, rgba(255, 148, 117, 0.08), transparent 26%),
        radial-gradient(circle at bottom left, rgba(73, 118, 206, 0.08), transparent 28%),
        linear-gradient(180deg, rgba(255, 255, 255, 0.8), rgba(255, 255, 255, 0.56)),
        var(--panelSurfaceBgColor);
      box-shadow: var(--panelSurfaceShadow);
    }
    & span, & div,
    & h1, & h2, & h3, & h4, & h5 {
      user-select: none;
    }
    & h4 {
      margin: 0 0 28px;
      font-size: 36px;
      line-height: 1;
      font-weight: 600;
      letter-spacing: -0.05em;
      color: var(--sideBarTitleColor);
    }
    & h5 {
      color: var(--sideBarTitleColor);
    }
  }
  & .pref-content.frameless .pref-setting {
    margin-top: var(--titleBarHeight);
    padding-top: 34px;
  }
}
</style>
