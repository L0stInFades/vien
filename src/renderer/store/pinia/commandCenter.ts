import { defineStore } from 'pinia'
import log from 'electron-log'
import bus from '../../bus'
import staticCommands, { RootCommand } from '../../commands'

export const useCommandCenterStore = defineStore('commandCenter', {
  state: () => ({
    rootCommand: new RootCommand(staticCommands),
  }),
  actions: {
    registerCommand(command: unknown) {
      this.rootCommand.subcommands.push(command)
    },
    sortCommands() {
      this.rootCommand.subcommands.sort((a, b) => a.description.localeCompare(b.description))
    },
    executeCommand(commandId: string) {
      const { subcommands } = this.rootCommand
      const command = subcommands.find((c) => c.id === commandId)
      if (!command) {
        const errorMsg = `Cannot execute command "${commandId}" because it's missing.`
        log.error(errorMsg)
        throw new Error(errorMsg)
      }
      command.execute()
    },
    listen() {
      bus.on('cmd::sort-commands', () => {
        this.sortCommands()
      })

      window.api.ipc.on('mt::keybindings-response', (keybindingMap: unknown) => {
        const map = keybindingMap as Record<string, string>
        const { subcommands } = this.rootCommand
        for (const entry of subcommands) {
          const value = map[entry.id]
          if (value) {
            entry.shortcut = normalizeAccelerator(value)
          }
        }
      })

      bus.on('cmd::register-command', (command) => {
        this.registerCommand(command)
      })

      bus.on('cmd::execute', (commandId) => {
        if (typeof commandId === 'string') {
          this.executeCommand(commandId)
        }
      })

      window.api.ipc.on('mt::execute-command-by-id', (commandId: unknown) => {
        if (typeof commandId === 'string') {
          this.executeCommand(commandId)
        }
      })
    },
  },
})

const normalizeAccelerator = (acc: string) => {
  try {
    return acc
      .replace(/cmdorctrl|cmd/i, 'Cmd')
      .replace(/ctrl/i, 'Ctrl')
      .split('+')
  } catch (_) {
    return [acc]
  }
}
