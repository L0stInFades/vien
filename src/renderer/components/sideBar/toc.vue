<template>
  <div
    class="side-bar-toc"
    :class="[{ 'side-bar-toc-overflow': !wordWrapInToc, 'side-bar-toc-wordwrap': wordWrapInToc }]"
  >
    <div class="title">On this page</div>
    <el-tree
      v-if="toc.length"
      :data="toc"
      :default-expand-all="true"
      :props="defaultProps"
      @node-click="handleClick"
      :expand-on-click-node="false"
      :indent="10"
    ></el-tree>
    <div class="no-data" v-else>
      <p>Headings gather here once the draft begins to take shape.</p>
    </div>
  </div>
</template>

<script>
import { mapState } from 'vuex'
import bus from '../../bus'

export default {
  data() {
    return {
      defaultProps: {
        children: 'children',
        label: 'label',
      },
    }
  },
  computed: {
    ...mapState({
      toc: (state) => state.editor.toc,
      wordWrapInToc: (state) => state.preferences.wordWrapInToc,
    }),
  },
  methods: {
    handleClick({ slug }) {
      bus.emit('scroll-to-header', slug)
    },
  },
}
</script>

<style>
  .side-bar-toc {
    height: 100%;
    margin: 0;
    padding: 26px 16px 18px;
    box-sizing: border-box;
    list-style: none;
    display: flex;
    flex-direction: column;
    & .title {
      color: var(--panelMutedColor);
      font-size: 11px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      min-height: 36px;
      line-height: 36px;
      margin: 0 0 12px;
      padding: 0 14px;
    }
    & .el-tree-node {
      margin-top: 4px;
    }
    & .el-tree {
      background: transparent;
      color: var(--sideBarColor);
      padding: 0 2px 12px;
    }
    & .el-tree-node:focus > .el-tree-node__content {
      background-color: var(--sideBarRowCurrentBgColor);
      border-color: var(--sideBarRowBorderColor);
    }
    & .el-tree-node__content:hover {
      background: rgba(126, 102, 76, 0.06);
    }
    & .el-tree-node__content {
      min-height: 34px;
      padding-right: 12px;
      border: 1px solid transparent;
      border-radius: 8px;
      background: transparent;
      transition: background-color .18s ease;
    }
    & .el-tree-node__content > .el-tree-node__label {
      font-size: 13px;
      line-height: 1.45;
    }
    & .el-tree-node__expand-icon {
      color: var(--sideBarTextColor);
    }
    & > li {
      font-size: 14px;
      margin-bottom: 15px;
      cursor: pointer;
    }
    & .no-data {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 0 20px 48px;
      text-align: center;
      color: var(--panelMutedColor);
      & p {
        max-width: 200px;
        margin: 0;
        font-size: 13px;
        line-height: 1.7;
      }
    }
  }
  .side-bar-toc-overflow {
    overflow: auto;
  }
  .side-bar-toc-wordwrap {
    overflow-x: hidden;
    overflow-y: auto;
    & .el-tree-node__content {
      white-space: normal;
      height: auto;
      min-height: 26px;
    }
  }
</style>
