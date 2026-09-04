<template>
  <div
    v-show="showSideBar"
    class="side-bar"
    ref="sideBar"
    :style="[ !rightColumn ? { 'min-width': '86px' } : {}, { 'width': `${finalSideBarWidth}px` } ]"
  >
    <div class="left-column">
      <ul>
        <li
          v-for="(c, index) of sideBarIcons"
          :key="index"
          @click="handleLeftIconClick(c.name)"
          :class="{ 'active': c.name === rightColumn }"
        >
          <svg :viewBox="c.icon.viewBox">
            <use :xlink:href="c.icon.url"></use>
          </svg>
        </li>
      </ul>
    </div>
    <div class="right-column" v-show="rightColumn">
      <tree
        :project-tree="projectTree"
        :opened-files="openedFiles"
        :tabs="tabs"
        v-if="rightColumn === 'files'"
      ></tree>
      <side-bar-search
        v-else-if="rightColumn === 'search'"
      ></side-bar-search>
      <toc
        v-else-if="rightColumn === 'toc'"
      ></toc>
    </div>
    <div class="drag-bar" ref="dragBar" v-show="rightColumn"></div>
  </div>
</template>

<script>
import { sideBarIcons } from './help'
import Tree from './tree.vue'
import SideBarSearch from './search.vue'
import Toc from './toc.vue'
import { useLayoutStore } from '@/store/pinia/layout'

export default {
  data() {
    this.sideBarIcons = sideBarIcons
    return {
      openedFiles: [],
      sideBarViewWidth: 280,
    }
  },
  components: {
    Tree,
    SideBarSearch,
    Toc,
  },
  computed: {
    layoutStore() {
      return useLayoutStore()
    },
    rightColumn() {
      return this.layoutStore.rightColumn
    },
    showSideBar() {
      return this.layoutStore.showSideBar
    },
    projectTree() {
      return this.$store.state.project.projectTree
    },
    sideBarWidth() {
      return this.layoutStore.sideBarWidth
    },
    tabs() {
      return this.$store.state.editor.tabs
    },
    finalSideBarWidth() {
      const { showSideBar, rightColumn, sideBarViewWidth } = this
      if (!showSideBar) return 0
      if (rightColumn === '') return 86
      return sideBarViewWidth < 260 ? 260 : sideBarViewWidth
    },
  },
  created() {
    this.$nextTick(() => {
      const dragBar = this.$refs.dragBar
      let startX = 0
      let sideBarWidth = +this.sideBarWidth
      let startWidth = sideBarWidth

      this.sideBarViewWidth = sideBarWidth

      const mouseUpHandler = (_event) => {
        document.removeEventListener('mousemove', mouseMoveHandler, false)
        document.removeEventListener('mouseup', mouseUpHandler, false)
        this.layoutStore.changeSideBarWidth(sideBarWidth < 260 ? 260 : sideBarWidth)
      }

      const mouseMoveHandler = (event) => {
        const offset = event.clientX - startX
        sideBarWidth = startWidth + offset
        this.sideBarViewWidth = sideBarWidth
      }

      const mouseDownHandler = (event) => {
        startX = event.clientX
        startWidth = +this.sideBarWidth
        document.addEventListener('mousemove', mouseMoveHandler, false)
        document.addEventListener('mouseup', mouseUpHandler, false)
      }

      dragBar.addEventListener('mousedown', mouseDownHandler, false)
    })
  },
  methods: {
    handleLeftIconClick(name) {
      if (this.rightColumn === name) {
        this.layoutStore.setLayout({ rightColumn: '' })
        this.layoutStore.changeSideBarWidth(this.finalSideBarWidth)
      } else {
        const needDispatch = this.rightColumn === ''
        this.layoutStore.setLayout({ rightColumn: name })
        this.sideBarViewWidth = +this.sideBarWidth
        if (needDispatch) {
          this.layoutStore.changeSideBarWidth(this.finalSideBarWidth)
        }
      }
    },
  },
}
</script>

<style scoped>
  .side-bar {
    display: flex;
    gap: 12px;
    flex-shrink: 0;
    flex-grow: 0;
    width: 280px;
    height: 100vh;
    min-width: 260px;
    position: relative;
    color: var(--sideBarColor);
    user-select: none;
    padding: 16px 12px 16px 14px;
    box-sizing: border-box;
    background: var(--sideBarBgColor);
    border-right: 1px solid var(--editorSurfaceEdge);
    & .left-column {
      & svg {
        fill: var(--editorColor40);
      }
    }
  }

  .left-column {
    height: 100%;
    width: 60px;
    display: flex;
    flex-direction: column;
    justify-content: flex-start;
    padding: 56px 8px 10px;
    box-sizing: border-box;
    & > ul {
      opacity: 1;
      display: flex;
      flex-direction: column;
      gap: 8px;
    }
  }

  .left-column ul {
    list-style: none;
    margin: 0;
    padding: 0;
    & > li {
      width: 42px;
      height: 42px;
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      align-items: center;
      cursor: pointer;
      border-radius: 10px;
      background: transparent;
      transition: background-color .18s ease;
      & > svg {
        width: 18px;
        height: 18px;
        fill: var(--editorColor40);
        opacity: 1;
        transition: fill .18s ease;
      }
      &:hover {
        background: rgba(126, 102, 76, 0.07);
      }
      &.active {
        background: var(--itemBgColor);
        & > svg {
          fill: var(--editorColor80);
        }
      }
    }
  }

  .right-column {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    & > * {
      flex: 1;
      min-height: 0;
    }
  }
</style>
