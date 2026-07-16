/**
 * Main-process backing for the sandboxed preload (PLAN.md §5.7 sandbox
 * enablement). clipboard/shell/nativeImage are unavailable in sandboxed
 * preloads, so the narrow window.api surface calls through here instead.
 *
 * - clipboard methods keep their synchronous signatures via sendSync
 *   (rare, user-action-driven calls);
 * - shell methods are validated: openExternal accepts http(s)/mailto only,
 *   path operations require absolute paths (ShellService policy, ADR-003).
 */
import path from 'node:path'
import { clipboard, ipcMain, nativeImage, shell } from 'electron'
import log from 'electron-log'
import { assertTrustedSender } from '../security/ipcGuard'

const EXTERNAL_URL_REG = /^(?:https?|mailto):/i

const handleSync = (channel, compute) => {
  ipcMain.on(channel, (event, ...args) => {
    try {
      assertTrustedSender(event)
      event.returnValue = { ok: true, value: compute(...args) }
    } catch (error) {
      log.warn(`[preloadBridge] ${channel}: ${error.message}`)
      event.returnValue = { ok: false }
    }
  })
}

export const registerPreloadBridgeHandlers = () => {
  // --- clipboard (sync signatures preserved) -------------------------------
  handleSync('mt::clipboard-read-text-sync', () => clipboard.readText())
  handleSync('mt::clipboard-write-text-sync', (text) => {
    clipboard.writeText(String(text ?? ''))
    return true
  })
  handleSync('mt::clipboard-read-html-sync', () => clipboard.readHTML())
  handleSync('mt::clipboard-write-html-sync', (markup) => {
    clipboard.writeHTML(String(markup ?? ''))
    return true
  })
  handleSync('mt::clipboard-has-format-sync', (format) => clipboard.has(String(format ?? '')))
  handleSync('mt::clipboard-read-image-data-url-sync', () => {
    const image = clipboard.readImage()
    return image.isEmpty() ? '' : image.toDataURL()
  })
  handleSync('mt::clipboard-write-image-data-url-sync', (dataURL) => {
    if (typeof dataURL !== 'string' || !dataURL.startsWith('data:image/')) {
      throw new Error('Expected an image data URL.')
    }
    clipboard.writeImage(nativeImage.createFromDataURL(dataURL))
    return true
  })

  // --- shell (validated, async) --------------------------------------------
  ipcMain.handle('mt::shell-open-external', (event, url) => {
    assertTrustedSender(event)
    if (typeof url !== 'string' || !EXTERNAL_URL_REG.test(url)) {
      log.warn(`[preloadBridge] blocked openExternal for: ${String(url).slice(0, 200)}`)
      throw new Error('Only http(s) and mailto links may be opened externally.')
    }
    return shell.openExternal(url)
  })

  ipcMain.handle('mt::shell-open-path', (event, pathname) => {
    assertTrustedSender(event)
    if (typeof pathname !== 'string' || !path.isAbsolute(pathname) || pathname.includes('\0')) {
      throw new Error('Expected an absolute path.')
    }
    return shell.openPath(path.normalize(pathname))
  })

  ipcMain.handle('mt::shell-show-item-in-folder', (event, pathname) => {
    assertTrustedSender(event)
    if (typeof pathname !== 'string' || !path.isAbsolute(pathname) || pathname.includes('\0')) {
      throw new Error('Expected an absolute path.')
    }
    shell.showItemInFolder(path.normalize(pathname))
    return true
  })
}
