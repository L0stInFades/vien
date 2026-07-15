import { BrowserWindow, ipcMain, Menu, clipboard } from 'electron'
import plist from 'plist'

const isOsx = process.platform === 'darwin'
const isWindows = process.platform === 'win32'

let cachedFonts = null

const getAvailableFontFamilies = async (onlyMonospace = false) => {
  if (!cachedFonts) {
    const fontManagerModule = await import('fontmanager-redux')
    const fontManager = fontManagerModule.default || fontManagerModule
    cachedFonts = fontManager.getAvailableFontsSync()
  }

  const families = cachedFonts
    .filter((font) => font.family && (!onlyMonospace || font.monospace))
    .map((font) => font.family)

  return [...new Set(families)].sort((a, b) => a.localeCompare(b))
}

/**
 * Register IPC handlers that replace @electron/remote window operations.
 * These handlers allow the renderer to perform window management
 * without direct access to BrowserWindow instances.
 */
export const registerWindowBridgeHandlers = () => {
  // Window management
  ipcMain.on('mt::window-close', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (win) win.close()
  })

  ipcMain.on('mt::window-minimize', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (win) win.minimize()
  })

  ipcMain.on('mt::window-maximize-toggle', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (win) {
      if (win.isMaximized()) {
        win.unmaximize()
      } else {
        win.maximize()
      }
    }
  })

  ipcMain.on('mt::window-toggle-maximize', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (win) {
      if (win.isFullScreen()) {
        win.setFullScreen(false)
      } else if (win.isMaximized()) {
        win.unmaximize()
      } else {
        win.maximize()
      }
    }
  })

  ipcMain.on('mt::window-unmaximize-request', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (win) win.unmaximize()
  })

  ipcMain.on('mt::window-set-fullscreen', (e, flag) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (win) win.setFullScreen(flag)
  })

  ipcMain.handle('mt::window-is-fullscreen', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    return win ? win.isFullScreen() : false
  })

  ipcMain.handle('mt::window-is-maximized', (e) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    return win ? win.isMaximized() : false
  })

  // Context menus (replacing @electron/remote Menu)
  ipcMain.on('mt::sidebar-context-menu', (e, payload) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (!win) return

    const { hasPathCache, x, y } = payload
    // Forward to renderer to handle the actual menu action via IPC
    const menu = Menu.buildFromTemplate([
      { label: 'New File', click: () => e.sender.send('mt::sidebar-context-action', 'newFile') },
      { label: 'New Directory', click: () => e.sender.send('mt::sidebar-context-action', 'newDirectory') },
      { type: 'separator' },
      { label: 'Copy', click: () => e.sender.send('mt::sidebar-context-action', 'copy') },
      { label: 'Cut', click: () => e.sender.send('mt::sidebar-context-action', 'cut') },
      { label: 'Paste', enabled: hasPathCache, click: () => e.sender.send('mt::sidebar-context-action', 'paste') },
      { type: 'separator' },
      { label: 'Rename', click: () => e.sender.send('mt::sidebar-context-action', 'rename') },
      { label: 'Move To Trash', click: () => e.sender.send('mt::sidebar-context-action', 'remove') },
      { type: 'separator' },
      { label: 'Show In Folder', click: () => e.sender.send('mt::sidebar-context-action', 'showInFolder') },
    ])
    menu.popup({ window: win, x, y })
  })

  ipcMain.on('mt::tab-context-menu', (e, payload) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (!win) return

    const { tabId, pathname, x, y } = payload
    const hasPathname = !!pathname
    const menu = Menu.buildFromTemplate([
      { label: 'Close', click: () => e.sender.send('mt::tab-context-action', 'closeThis', tabId) },
      { label: 'Close others', click: () => e.sender.send('mt::tab-context-action', 'closeOthers', tabId) },
      { label: 'Close saved tabs', click: () => e.sender.send('mt::tab-context-action', 'closeSaved') },
      { label: 'Close all tabs', click: () => e.sender.send('mt::tab-context-action', 'closeAll') },
      { type: 'separator' },
      { label: 'Rename', enabled: hasPathname, click: () => e.sender.send('mt::tab-context-action', 'rename', tabId) },
      {
        label: 'Copy path',
        enabled: hasPathname,
        click: () => e.sender.send('mt::tab-context-action', 'copyPath', tabId),
      },
      {
        label: 'Show in folder',
        enabled: hasPathname,
        click: () => e.sender.send('mt::tab-context-action', 'showInFolder', tabId),
      },
    ])
    menu.popup({ window: win, x, y })
  })

  ipcMain.on('mt::show-app-menu', (e, x, y) => {
    const win = BrowserWindow.fromWebContents(e.sender)
    if (!win) return
    const appMenu = Menu.getApplicationMenu()
    if (appMenu) {
      appMenu.popup({ window: win, x, y })
    }
  })

  // Clipboard operations (replacing @electron/remote clipboard)
  ipcMain.handle('mt::clipboard-has-files', () => {
    if (!isOsx) return false
    return clipboard.has('NSFilenamesPboardType')
  })

  ipcMain.handle('mt::clipboard-get-files', () => {
    if (!isOsx) return []
    if (!clipboard.has('NSFilenamesPboardType')) return []
    try {
      return plist.parse(clipboard.read('NSFilenamesPboardType'))
    } catch {
      return []
    }
  })

  ipcMain.handle('mt::clipboard-guess-file-path', () => {
    if (isOsx) {
      if (!clipboard.has('NSFilenamesPboardType')) return ''
      try {
        const result = plist.parse(clipboard.read('NSFilenamesPboardType'))
        return Array.isArray(result) && result.length ? result[0] : ''
      } catch {
        return ''
      }
    } else if (isWindows) {
      const rawFilePath = clipboard.read('FileNameW')
      const filePath = rawFilePath.replace(new RegExp(String.fromCharCode(0), 'g'), '')
      return filePath && typeof filePath === 'string' ? filePath : ''
    }
    return ''
  })

  ipcMain.handle('mt::get-available-font-families', (_event, onlyMonospace = false) =>
    getAvailableFontFamilies(!!onlyMonospace).catch((error) => {
      console.warn('[main] Unable to enumerate fonts:', error)
      return []
    }),
  )
}
