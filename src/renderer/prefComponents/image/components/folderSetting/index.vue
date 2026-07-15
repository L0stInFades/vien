<template>
  <section class="image-folder">
    <h5>Global or relative image folder</h5>
    <text-box description="Global image folder" :textValue="imageFolderPath"
      :regexValidator="/^(?:$|([a-zA-Z]:)?[\/\\].*$)/" :defaultValue="folderPathPlaceholder"
      :onChange="value => modifyImageFolderPath(value)"></text-box>
    <div>
      <el-button size="mini" @click="modifyImageFolderPath(undefined)">Open...</el-button>
      <el-button size="mini" @click="openImageFolder">Show in Folder</el-button>
    </div>
    <compound>
      <template #head>
        <bool description="Prefer relative assets folder"
          more="https://github.com/L0stInFades/vien/blob/develop/docs/IMAGES.md"
          :isOn="imagePreferRelativeDirectory"
          :onChange="value => onSelectChange('imagePreferRelativeDirectory', value)"></bool>
      </template>
      <template #children>
        <text-box description="Relative image folder name" :textValue="imageRelativeDirectoryName"
          :regexValidator="/^(?:$|(?![a-zA-Z]:)[^\/\\].*$)/"
          :defaultValue="relativeDirectoryNamePlaceholder"
          :onChange="value => onSelectChange('imageRelativeDirectoryName', value)"></text-box>
        <div class="footnote">
          Include <code>${filename}</code> in the text-box above to automatically insert the document file name.
        </div>
      </template>
    </compound>
  </section>
</template>

<script>
import Bool from '@/prefComponents/common/bool'
import Compound from '@/prefComponents/common/compound'
import TextBox from '@/prefComponents/common/textBox'
import { usePreferencesStore } from '@/store/pinia/preferences'

export default {
  components: {
    Bool,
    Compound,
    TextBox,
  },
  data() {
    return {}
  },
  computed: {
    preferencesStore() {
      return usePreferencesStore()
    },
    imageFolderPath() {
      return this.preferencesStore.imageFolderPath
    },
    imagePreferRelativeDirectory() {
      return this.preferencesStore.imagePreferRelativeDirectory
    },
    imageRelativeDirectoryName() {
      return this.preferencesStore.imageRelativeDirectoryName
    },
    imageInsertAction() {
      return this.preferencesStore.imageInsertAction
    },
    folderPathPlaceholder() {
      return this.preferencesStore.imageFolderPath || ''
    },
    relativeDirectoryNamePlaceholder() {
      return this.preferencesStore.imageRelativeDirectoryName || 'assets'
    },
  },
  methods: {
    openImageFolder() {
      window.api.shell.openPath(this.imageFolderPath)
    },
    modifyImageFolderPath(value) {
      return this.preferencesStore.setImageFolderPath(value)
    },
    onSelectChange(type, value) {
      this.preferencesStore.setSinglePreference({ type, value })
    },
  },
}
</script>

<style scoped>
.image-folder .footnote {
  font-size: 13px;
  & code {
    font-size: 13px;
  }
}
</style>
