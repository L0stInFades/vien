import { ipcMain } from 'electron'

class IpcListenerRegistry {
  constructor() {
    this._listeners = new Map()
  }

  on(windowId, channel, listener) {
    ipcMain.on(channel, listener)

    const entries = this._listeners.get(windowId)
    if (entries) {
      entries.push({ channel, listener })
    } else {
      this._listeners.set(windowId, [{ channel, listener }])
    }
  }

  removeByWindowId(windowId) {
    const entries = this._listeners.get(windowId)
    if (!entries) {
      return
    }

    for (const { channel, listener } of entries) {
      ipcMain.removeListener(channel, listener)
    }

    this._listeners.delete(windowId)
  }

  removeAll() {
    for (const windowId of this._listeners.keys()) {
      this.removeByWindowId(windowId)
    }
  }
}

export default new IpcListenerRegistry()
