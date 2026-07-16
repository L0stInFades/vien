<template>
  <el-dialog
    v-model="visible"
    :show-close="true"
    :close-on-click-modal="false"
    custom-class="ag-dialog-table recovery-center-dialog"
    width="560px"
    center
    dir="ltr"
    @closed="handleClosed"
  >
    <template #title>
      <div class="dialog-title">Crash Recovery</div>
    </template>

    <p class="recovery-intro">
      Unsaved changes from a previous session were found. Restore them into
      tabs, or discard them. Closing this dialog keeps the snapshots for the
      next start.
    </p>
    <p v-if="corrupt > 0" class="recovery-corrupt">
      {{ corrupt }} recovery {{ corrupt === 1 ? 'entry was' : 'entries were' }} unreadable and skipped.
    </p>

    <div class="recovery-list">
      <div v-for="snapshot in snapshots" :key="snapshot.tabId" class="recovery-item">
        <div class="recovery-item-head">
          <span class="recovery-item-name">{{ snapshot.filename || 'Untitled' }}</span>
          <span class="recovery-item-time">{{ formatTime(snapshot.savedAt) }}</span>
        </div>
        <div v-if="snapshot.pathname" class="recovery-item-path">{{ snapshot.pathname }}</div>
        <pre class="recovery-item-preview">{{ preview(snapshot.markdown) }}</pre>
        <div class="recovery-item-actions">
          <el-button size="small" type="primary" @click="restoreOne(snapshot)">Restore</el-button>
          <el-button size="small" @click="discardOne(snapshot)">Discard</el-button>
        </div>
      </div>
    </div>

    <template #footer>
      <div class="dialog-footer">
        <el-button @click="visible = false">Keep for later</el-button>
        <el-button @click="discardAll">Discard all</el-button>
        <el-button type="primary" @click="restoreAll">Restore all</el-button>
      </div>
    </template>
  </el-dialog>
</template>

<script>
import bus from '../../bus'
import notice from '@/services/notification'

export default {
  name: 'RecoveryCenter',

  data() {
    return {
      visible: false,
      snapshots: [],
      corrupt: 0,
    }
  },

  created() {
    bus.on('show-recovery-center', this.show)
  },

  beforeUnmount() {
    bus.off('show-recovery-center', this.show)
  },

  methods: {
    show({ snapshots, corrupt }) {
      this.snapshots = snapshots
      this.corrupt = corrupt
      this.visible = snapshots.length > 0
      if (snapshots.length === 0 && corrupt > 0) {
        notice.notify({
          title: 'Crash recovery',
          type: 'warning',
          time: 20000,
          message: `${corrupt} recovery ${corrupt === 1 ? 'entry was' : 'entries were'} unreadable.`,
        })
      }
    },

    formatTime(savedAt) {
      if (typeof savedAt !== 'number') return ''
      return new Date(savedAt).toLocaleString()
    },

    preview(markdown) {
      const text = (markdown || '').trim()
      return text.length > 240 ? `${text.slice(0, 240)}…` : text
    },

    restoreOne(snapshot) {
      this.$store.dispatch('RESTORE_RECOVERY_SNAPSHOT', snapshot)
      this.snapshots = this.snapshots.filter((s) => s.tabId !== snapshot.tabId)
      if (this.snapshots.length === 0) {
        this.visible = false
      }
    },

    discardOne(snapshot) {
      if (window.api?.recovery) {
        window.api.recovery.discard(snapshot.tabId).catch(() => {})
      }
      this.snapshots = this.snapshots.filter((s) => s.tabId !== snapshot.tabId)
      if (this.snapshots.length === 0) {
        this.visible = false
      }
    },

    restoreAll() {
      for (const snapshot of [...this.snapshots]) {
        this.restoreOne(snapshot)
      }
    },

    discardAll() {
      for (const snapshot of [...this.snapshots]) {
        this.discardOne(snapshot)
      }
    },

    handleClosed() {
      // Snapshots not acted on stay on disk and will be offered again.
      this.snapshots = []
      this.corrupt = 0
    },
  },
}
</script>

<style scoped>
.recovery-intro {
  margin: 0 0 8px;
  font-size: 13px;
  color: var(--editorColor80, #555);
}
.recovery-corrupt {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--deleteColor, #c0392b);
}
.recovery-list {
  max-height: 320px;
  overflow-y: auto;
}
.recovery-item {
  padding: 10px 12px;
  margin-bottom: 8px;
  border: 1px solid var(--editorColor10, #e5e5e5);
  border-radius: 6px;
}
.recovery-item-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}
.recovery-item-name {
  font-weight: 600;
  font-size: 13px;
}
.recovery-item-time {
  font-size: 11px;
  color: var(--editorColor50, #999);
}
.recovery-item-path {
  font-size: 11px;
  color: var(--editorColor50, #999);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.recovery-item-preview {
  margin: 6px 0;
  padding: 6px 8px;
  max-height: 72px;
  overflow: hidden;
  font-size: 11px;
  line-height: 1.5;
  background: var(--editorColor5, #f7f7f7);
  border-radius: 4px;
  white-space: pre-wrap;
  word-break: break-word;
}
.recovery-item-actions {
  display: flex;
  gap: 8px;
  justify-content: flex-end;
}
</style>
