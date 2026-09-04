<template>
    <div
      class="opened-file"
      :title="file.pathname"
      @click="selectFile(file)"
      :class="[{'active': currentFile.id === file.id, 'unsaved': !file.isSaved }]"
    >
      <svg class="icon" aria-hidden="true"
        @click.stop="removeFileInTab(file)"
      >
        <use xlink:href="#icon-close-small"></use>
      </svg>
      <span class="name">{{ file.filename }}</span>
    </div>
</template>

<script>
import { mapState } from 'vuex'
import { tabsMixins } from '../../mixins'

export default {
  mixins: [tabsMixins],
  props: {
    file: {
      type: Object,
      required: true,
    },
  },
  computed: {
    ...mapState({
      currentFile: (state) => state.editor.currentFile,
    }),
  },
}
</script>

<style scoped>
  .opened-file {
    display: flex;
    user-select: none;
    align-items: center;
    min-height: 34px;
    line-height: 1.4;
    padding: 0 12px 0 36px;
    position: relative;
    color: var(--sideBarColor);
    border-radius: 8px;
    border: 1px solid transparent;
    background: transparent;
    transition: background-color .18s ease;
    & > svg {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 10px;
      height: 10px;
      position: absolute;
      top: 11px;
      left: 12px;
      opacity: 0;
      transition: opacity .18s ease;
    }
    &:hover {
      background: rgba(126, 102, 76, 0.06);
    }
    &:hover > svg {
      opacity: 1;
    }
    & > span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
  .opened-file.active {
    color: var(--sideBarTitleColor);
    background: var(--sideBarRowCurrentBgColor);
    border-color: var(--sideBarRowBorderColor);
  }
  .unsaved.opened-file::before {
    content: '';
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--sideBarCurrentIndicator);
    position: absolute;
    top: 13px;
    left: 13px;
  }
  .unsaved.opened-file:hover::before {
    content: none;
  }
</style>
