<template>
  <div class="command-palette">
    <el-dialog
      v-model="showCommandPalette"
      :show-close="false"
      :modal="true"
      @close="handleDialogClose"
      custom-class="ag-dialog-table"
      width="500px"
    >
      <template #title>
        <div class="search-wrapper">
          <div class="input-wrapper">
            <input
              ref="search"
              type="text"
              v-model="query"
              class="search"
              @keydown="handleBeforeInput"
              @keyup="handleInput"
              :placeholder="placeholderText"
            >
          </div>
          <loading v-if="searcherBusy"></loading>
          <transition name="fade" v-else-if="availableCommands.length">
            <ul class="commands">
              <li
                v-for="(item, index) of availableCommands"
                :key="index"
                ref="command-items"
                @click="search(item.id)"
                :class="{'active': index === selectedCommandIndex}"
              >
                <span class="title" :title="item.title">{{item.description}}</span>
                <span class="shortcut">
                  <span
                    class="shortcut"
                    v-for="(accelerator, index) of item.shortcut"
                    :key="index"
                  >
                      <kbd>{{accelerator}}</kbd>
                  </span>
                </span>
              </li>
            </ul>
          </transition>
        </div>
      </template>
    </el-dialog>
  </div>
</template>

<script>
import log from 'electron-log'
import { useCommandCenterStore } from '@/store/pinia/commandCenter'
import bus from '../../bus'
import loading from '../loading'

export default {
  components: {
    loading,
  },
  computed: {
    rootCommand() {
      return useCommandCenterStore().rootCommand
    },
  },
  data() {
    this.currentCommand = null
    this.defaultPlaceholderText = 'Type a command to execute'
    return {
      showCommandPalette: false,
      placeholderText: this.defaultPlaceholderText,
      query: '',
      selectedCommandIndex: -1,
      availableCommands: [],
      searcherBusy: false,
    }
  },
  created() {
    this.$nextTick(() => {
      bus.on('show-command-palette', this.handleShow)
    })
  },
  beforeUnmount() {
    bus.off('show-command-palette', this.handleShow)
  },
  methods: {
    handleShow(command) {
      this.currentCommand = command || this.rootCommand
      this.currentCommand
        .run()
        .then(() => {
          this.availableCommands = this.currentCommand.subcommands
          this.selectedCommandIndex = this.currentCommand.subcommandSelectedIndex
          this.placeholderText = this.currentCommand.placeholder || this.defaultPlaceholderText
          this.query = ''
          this.showCommandPalette = true
          bus.emit('editor-blur')
          this.$nextTick(() => {
            const items = this.$refs['command-items']
            const { selectedCommandIndex } = this
            if (items && items.length > 0 && selectedCommandIndex >= 0) {
              this.$refs['command-items'][selectedCommandIndex].scrollIntoView({ block: 'end' })
            }

            if (this.$refs.search) {
              this.$refs.search.focus()
            }
          })
        })
        .catch((error) => {
          if (error?.message) {
            log.error('Unable to initialize command:', error)
          }
        })
    },
    handleDialogClose() {
      this.selectedCommandIndex = -1
      this.query = ''
      this.availableCommands = []
      if (this.currentCommand.unload) {
        this.currentCommand.unload()
      }
      this.currentCommand = null
    },
    handleBeforeInput(event) {
      const { availableCommands, selectedCommandIndex } = this
      switch (event.key) {
        case 'ArrowUp': {
          event.preventDefault()
          event.stopPropagation()
          if (selectedCommandIndex <= 0) {
            this.selectedCommandIndex = availableCommands.length - 1
          } else {
            this.selectedCommandIndex--
          }

          const items = this.$refs['command-items']
          if (items && items.length > 0) {
            this.$refs['command-items'][this.selectedCommandIndex].scrollIntoView({ block: 'end' })
          }
          break
        }
        case 'ArrowDown': {
          event.preventDefault()
          event.stopPropagation()
          if (selectedCommandIndex + 1 >= availableCommands.length) {
            this.selectedCommandIndex = 0
          } else {
            this.selectedCommandIndex++
          }

          const items = this.$refs['command-items']
          if (items && items.length > 0) {
            this.$refs['command-items'][this.selectedCommandIndex].scrollIntoView({ block: 'end' })
          }
          break
        }
      }
    },
    handleInput(event) {
      if (event.isComposing) {
        return
      }
      switch (event.key) {
        case 'Control':
        case 'Alt':
        case 'Meta':
        case 'Shift':
        case 'Escape':
        case 'PageDown':
        case 'PageUp':
        case 'ArrowUp':
        case 'ArrowDown':
        case 'ArrowLeft':
        case 'ArrowRight': {
          break
        }
        case 'Enter': {
          this.search()
          break
        }
        default: {
          this.updateCommands()
          break
        }
      }
    },
    search(commandId = null) {
      const { availableCommands, selectedCommandIndex } = this
      if (commandId) {
        this.executeCommand(commandId)
        return
      } else if (selectedCommandIndex >= 0 && selectedCommandIndex < availableCommands.length) {
        this.executeCommand(availableCommands[selectedCommandIndex].id)
        return
      }

      this.updateCommands()
    },
    updateCommands() {
      const { currentCommand, query } = this
      const queryString = query.trim()

      if (currentCommand.search) {
        this.searcherBusy = true
        currentCommand
          .search(queryString)
          .then((result) => {
            this.searcherBusy = false
            this.availableCommands = result.subcommands
            this.selectedCommandIndex = result.subcommandSelectedIndex
            this.placeholderText = result.placeholder || this.defaultPlaceholderText
          })
          .catch((error) => {
            this.searcherBusy = false
            if (error?.message) {
              log.error('Unable to search command:', error)
            }
          })
      }
    },
    executeCommand(commandId) {
      this.showCommandPalette = false
      bus.emit('cmd::execute', commandId)
    },
  },
}
</script>
