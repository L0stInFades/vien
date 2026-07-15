<template>
  <div class="editor-with-tabs">
    <tabs v-if="showTabBar"></tabs>
    <tab-notifications></tab-notifications>
    <div class="container">
      <source-code
        v-if="sourceCode"
        :markdown="markdown"
        :cursor="cursor"
        :text-direction="textDirection"
      ></source-code>
      <editor
        v-else
        :markdown="markdown"
        :cursor="cursor"
        :text-direction="textDirection"
        :platform="platform"
      ></editor>
    </div>
  </div>
</template>

<script>
import { useLayoutStore } from '@/store/pinia/layout'
import Tabs from './tabs.vue'
import Editor from './editor.vue'
import SourceCode from './sourceCode.vue'
import TabNotifications from './notifications.vue'

export default {
  props: {
    markdown: {
      type: String,
      required: true,
    },
    cursor: {
      validator(value) {
        return typeof value === 'object'
      },
      required: true,
    },
    sourceCode: {
      type: Boolean,
      required: true,
    },
    showTabBar: {
      type: Boolean,
      required: true,
    },
    textDirection: {
      type: String,
      required: true,
    },
    platform: {
      type: String,
      required: true,
    },
  },
  components: {
    Tabs,
    Editor,
    SourceCode,
    TabNotifications,
  },
  computed: {
    layoutStore() {
      return useLayoutStore()
    },
    showSideBar() {
      return this.layoutStore.showSideBar
    },
    sideBarWidth() {
      return this.layoutStore.sideBarWidth
    },
  },
}
</script>

<style scoped>
  .editor-with-tabs {
    position: relative;
    height: 100%;
    flex: 1;
    display: flex;
    flex-direction: column;

    overflow: hidden;
    background: var(--editorBgColor);
    & > .container {
      flex: 1;
      overflow: hidden;
    }
  }
</style>
