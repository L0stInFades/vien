<template>
  <div
    v-if="currentNotification"
    class="editor-notifications"
    :class="currentNotification.type"
    :style="showSideBar ? { width: `calc(100vw - ${sideBarWidth}px)` } : { width: '100vw' }"
  >
    <div class="msg">{{ currentNotification.message }}</div>
    <div class="actions">
      <el-button v-for="(item, index) in currentNotification.buttons" :key="index" size="small" @click="handleClick(item.status)">{{ item.label }}</el-button>
    </div>
  </div>
</template>

<script>
import { useLayoutStore } from '@/store/pinia/layout'

export default {
  data() {
    return {}
  },
  computed: {
    layoutStore() {
      return useLayoutStore()
    },
    currentFile() {
      return this.$store.state.editor.currentFile
    },
    showSideBar() {
      return this.layoutStore.showSideBar
    },
    sideBarWidth() {
      return this.layoutStore.sideBarWidth
    },
    currentNotification() {
      const notifications = this.currentFile.notifications
      if (!notifications || notifications.length === 0) {
        return null
      }
      return notifications[0]
    },
  },
  methods: {
    handleClick(status) {
      const notifications = this.currentFile.notifications
      if (!notifications || notifications.length === 0) {
        console.error('notifications::handleClick: Cannot find notification on stack.')
        return
      }

      const item = notifications.shift()
      const action = item.action
      if (action) {
        action(status)
      }
    },
  },
}
</script>

<style scoped>
  .editor-notifications {
    position: relative;
    display: flex;
    flex-direction: row;
    max-height: 100px;
    margin-top: 4px;
    background: var(--notificationPrimaryBg);
    color: var(--notificationPrimaryColor);
    padding: 8px 10px;
    user-select: none;
    overflow: hidden;
    &.warn {
      background: var(--notificationWarningBg);
      color: var(--notificationWarningColor);
    }
    &.crit {
      background: var(--notificationErrorBg);
      color: var(--notificationErrorColor);
    }
  }
  .msg {
    flex: 1;
  }
  .actions {
    display: flex;
    gap: 8px;
  }
</style>
