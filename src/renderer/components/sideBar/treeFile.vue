<template>
  <div
    :title="file.pathname"
    class="side-bar-file"
    data-testid="tree-file"
    :data-pathname="file.pathname"
    :style="{'padding-left': `${(depth * 20) + 20}px`, 'opacity': file.isMarkdown ? 1 : 0.75 }"
    @click="handleFileClick()"
    :class="[{'current': currentFile.pathname === file.pathname, 'active': file.id === activeItem.id }]"
    ref="file"
  >
    <file-icon
      :name="file.name"
    ></file-icon>
    <input
      type="text"
      @click.stop="noop"
      class="rename"
      v-if="renameCache === file.pathname"
      v-model="newName"
      ref="renameInput"
      @keydown.enter="rename"
    >
    <span v-else>{{ file.name }}</span>
  </div>
</template>

<script>
import FileIcon from './icon.vue'
import { mapState } from 'vuex'
import { fileMixins } from '../../mixins'
import { showContextMenu } from '../../contextMenu/sideBar'
import bus from '../../bus'

export default {
  mixins: [fileMixins],
  name: 'file',
  data() {
    return {
      newName: '',
    }
  },
  props: {
    file: {
      type: Object,
      required: true,
    },
    depth: {
      type: Number,
      required: true,
    },
  },
  components: {
    FileIcon,
  },
  computed: {
    ...mapState({
      renameCache: (state) => state.project.renameCache,
      activeItem: (state) => state.project.activeItem,
      clipboard: (state) => state.project.clipboard,
      currentFile: (state) => state.editor.currentFile,
      tabs: (state) => state.editor.tabs,
    }),
  },
  created() {
    this.$nextTick(() => {
      this.$refs.file.addEventListener('contextmenu', (event) => {
        event.preventDefault()
        this.$store.dispatch('CHANGE_ACTIVE_ITEM', this.file)
        showContextMenu(event, !!this.clipboard)
      })

      bus.on('SIDEBAR::show-rename-input', this.focusRenameInput)
    })
  },
  methods: {
    noop() {},
    focusRenameInput() {
      this.$nextTick(() => {
        if (this.$refs.renameInput) {
          this.$refs.renameInput.focus()
          this.newName = this.file.name
        }
      })
    },
    rename() {
      const { newName } = this
      if (newName) {
        this.$store.dispatch('RENAME_IN_SIDEBAR', newName)
      }
    },
  },
}
</script>

<style scoped>
  .side-bar-file {
    display: flex;
    position: relative;
    align-items: center;
    cursor: default;
    user-select: none;
    min-height: 34px;
    box-sizing: border-box;
    margin: 1px 0;
    padding-right: 12px;
    border-radius: 8px;
    border: 1px solid transparent;
    background: transparent;
    transition: background-color .18s ease;
    &:hover {
      background: rgba(126, 102, 76, 0.06);
    }
    & > span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    &::before {
      content: '';
      position: absolute;
      display: block;
      left: 6px;
      background: var(--sideBarCurrentIndicator);
      width: 4px;
      height: 0;
      top: 50%;
      transform: translateY(-50%);
      border-radius: 999px;
      transition: all .2s ease;
    }
  }
  .side-bar-file.current::before {
    height: 18px;
  }
  .side-bar-file.current > span {
    color: var(--sideBarTitleColor);
  }
  .side-bar-file.current {
    background: var(--sideBarRowCurrentBgColor);
    border-color: var(--sideBarRowBorderColor);
  }
  .side-bar-file.active > span {
    color: var(--sideBarTitleColor);
  }
  .side-bar-file.active {
    background: var(--sideBarRowActiveBgColor);
    border-color: var(--sideBarRowBorderColor);
  }
  input.rename {
    height: 34px;
    outline: none;
    margin: 4px 0;
    padding: 0 12px;
    color: var(--sideBarColor);
    border: 1px solid var(--controlBorderColor);
    background: var(--inputBgColor);
    width: 100%;
    border-radius: 8px;
    box-sizing: border-box;
  }
</style>
