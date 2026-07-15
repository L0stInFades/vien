<template>
  <div class="pref-general">
    <h4>General</h4>
    <separator></separator>
    <compound label="Startup">
      <template #description>
        Choose what Vien should restore or open when the app launches.
      </template>
      <template #children>
        <div class="startup-action-ctrl">
          <label>
            <input type="radio" value="welcome" v-model="startUpAction">
            Show welcome page
          </label>
          <label>
            <input type="radio" value="lastState" v-model="startUpAction">
            Restore previous session
          </label>
          <label>
            <input type="radio" value="folder" v-model="startUpAction">
            Open default directory
          </label>
          <el-button size="small" @click="selectDefaultDirectoryToOpen">Choose…</el-button>
          <span>{{ defaultDirectoryToOpen }}</span>
        </div>
      </template>
    </compound>
    <compound label="Title bar style">
      <template #children>
        <cur-select :currentValue="titleBarStyle" :options="titleBarStyleOptions" :onChange="value => onSelectChange('titleBarStyle', value)"></cur-select>
      </template>
    </compound>
    <compound label="Window behavior">
      <template #children>
        <bool label="Open files in a new window" :value="openFilesInNewWindow" :onChange="value => onSelectChange('openFilesInNewWindow', value)"></bool>
        <bool label="Open folders in a new window" :value="openFolderInNewWindow" :onChange="value => onSelectChange('openFolderInNewWindow', value)"></bool>
      </template>
    </compound>
    <compound label="Autosave">
      <template #children>
        <bool label="Enable autosave" :value="autoSave" :onChange="value => onSelectChange('autoSave', value)"></bool>
        <range :value="autoSaveDelay" :min="1000" :max="10000" :step="500" :onChange="value => onSelectChange('autoSaveDelay', value)"></range>
      </template>
    </compound>
    <compound label="Appearance">
      <template #children>
        <cur-select :currentValue="preferenceZoom" :options="zoomOptions" :onChange="value => onSelectChange('zoom', value)"></cur-select>
        <bool label="Hide scrollbar" :value="hideScrollbar" :onChange="value => onSelectChange('hideScrollbar', value)"></bool>
        <bool label="Wrap words in table of contents" :value="wordWrapInToc" :onChange="value => onSelectChange('wordWrapInToc', value)"></bool>
      </template>
    </compound>
    <compound label="Files">
      <template #children>
        <cur-select :currentValue="fileSortBy" :options="fileSortByOptions" :onChange="value => onSelectChange('fileSortBy', value)"></cur-select>
      </template>
    </compound>
    <compound label="Language">
      <template #children>
        <cur-select :currentValue="language" :options="languageOptions" :onChange="value => onSelectChange('language', value)"></cur-select>
      </template>
    </compound>
  </div>
</template>

<script>
import Compound from '../common/compound'
import Range from '../common/range'
import CurSelect from '../common/select'
import Bool from '../common/bool'
import Separator from '../common/separator'
import { usePreferencesStore } from '@/store/pinia/preferences'
import { isOsx } from '@/util'

import { titleBarStyleOptions, zoomOptions, fileSortByOptions, languageOptions } from './config'

export default {
  components: {
    Compound,
    Bool,
    Range,
    CurSelect,
    Separator,
  },
  data() {
    this.titleBarStyleOptions = titleBarStyleOptions
    this.zoomOptions = zoomOptions
    this.fileSortByOptions = fileSortByOptions
    this.languageOptions = languageOptions
    this.isOsx = isOsx
    return {}
  },
  computed: {
    preferencesStore() {
      return usePreferencesStore()
    },
    autoSave() {
      return this.preferencesStore.autoSave
    },
    autoSaveDelay() {
      return this.preferencesStore.autoSaveDelay
    },
    titleBarStyle() {
      return this.preferencesStore.titleBarStyle
    },
    defaultDirectoryToOpen() {
      return this.preferencesStore.defaultDirectoryToOpen
    },
    openFilesInNewWindow() {
      return this.preferencesStore.openFilesInNewWindow
    },
    openFolderInNewWindow() {
      return this.preferencesStore.openFolderInNewWindow
    },
    preferenceZoom() {
      return this.preferencesStore.zoom
    },
    hideScrollbar() {
      return this.preferencesStore.hideScrollbar
    },
    wordWrapInToc() {
      return this.preferencesStore.wordWrapInToc
    },
    fileSortBy() {
      return this.preferencesStore.fileSortBy
    },
    language() {
      return this.preferencesStore.language
    },
    startUpAction: {
      get: function () {
        return this.preferencesStore.startUpAction
      },
      set: function (value) {
        const type = 'startUpAction'
        this.preferencesStore.setSinglePreference({ type, value })
      },
    },
  },
  methods: {
    onSelectChange(type, value) {
      this.preferencesStore.setSinglePreference({ type, value })
    },
    selectDefaultDirectoryToOpen() {
      this.preferencesStore.selectDefaultDirectoryToOpen()
    },
  },
}
</script>

<style scoped>
  .pref-general {
    & .startup-action-ctrl {
      font-size: 14px;
      user-select: none;
      color: var(--editorColor);
      & .el-button--small {
        margin-left: 25px;
      }
      & label {
        display: block;
        margin: 20px 0;
      }
    }
  }
</style>
