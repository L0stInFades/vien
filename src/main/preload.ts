import { contextBridge, ipcRenderer, clipboard, shell, webFrame, nativeImage } from 'electron'
import type { PreloadApi, SideBarContextMenuPayload, TabContextMenuPayload } from '../common/types/preload'

/** Listener with an optional attached wrapped version (event-stripped) for ipcRenderer.on/off symmetry */
type WrappedIpcListener = ((...args: unknown[]) => void) & {
  __wrappedListener?: (event: Electron.IpcRendererEvent, ...args: unknown[]) => void
}

// Whitelist of allowed IPC channels (mt:: prefix convention)
const ALLOWED_SEND_CHANNELS = [
  // File operations
  'mt::open-file',
  'mt::open-file-or-folder',
  'mt::save-tabs',
  'mt::save-and-close-tabs',
  'mt::window-tab-closed',
  'mt::rename',
  'mt::response-file-save',
  'mt::response-file-save-as',
  'mt::response-file-move-to',
  'mt::response-export',
  'mt::response-print',
  'mt::ask-for-image-auto-path',
  'mt::format-link-click',
  // Editor actions
  'mt::request-keybindings',
  'mt::editor-selection-changed',
  'mt::update-format-menu',
  'mt::update-line-ending-menu',
  'mt::handle-renderer-error',
  // Window management
  'mt::close-window',
  'mt::close-window-confirm',
  'mt::window-toggle-always-on-top',
  'mt::window-add-file-path',
  'mt::window-document-state',
  'mt::window-tab-closed',
  // Preferences
  'mt::ask-for-user-preference',
  'mt::ask-for-user-data',
  'mt::set-user-preference',
  'mt::set-user-data',
  'mt::ask-for-modify-image-folder-path',
  'mt::select-default-directory-to-open',
  'mt::view-layout-changed',
  'mt::update-sidebar-menu',
  // Application commands
  'mt::app-try-quit',
  'mt::cmd-new-editor-window',
  'mt::cmd-open-file',
  'mt::cmd-open-folder',
  'mt::cmd-close-window',
  'mt::cmd-toggle-autosave',
  'mt::cmd-import-file',
  'mt::open-file-by-window-id',
  'mt::open-setting-window',
  'mt::clear-recently-used-documents',
  'mt::make-screenshot',
  'mt::check-for-update',
  'mt::NEED_UPDATE',
  'mt::INSTALL_UPDATE_NOW',
  // Keybindings
  'mt::keybinding-debug-dump-keyboard-info',
  'mt::open-keybindings-config',
  // Sidebar/Project
  'mt::ask-for-open-project-in-sidebar',
  // Context menu actions (triggered from renderer)
  'mt::sidebar-context-menu',
  'mt::tab-context-menu',
  'mt::show-app-menu',
] as const

const ALLOWED_RECEIVE_CHANNELS = [
  // File operations
  'mt::set-pathname',
  'mt::tab-saved',
  'mt::tab-save-failure',
  'mt::export-success',
  'mt::force-close-tabs-by-id',
  'mt::show-export-dialog',
  'mt::editor-ask-file-save',
  'mt::editor-ask-file-save-as',
  'mt::editor-move-file',
  'mt::editor-rename-file',
  'mt::editor-close-tab',
  'mt::new-untitled-tab',
  'mt::pandoc-not-exists',
  // Editor actions
  'mt::editor-edit-action',
  'mt::editor-paragraph-action',
  'mt::editor-format-action',
  'mt::set-line-ending',
  'mt::set-file-encoding',
  'mt::set-final-newline',
  'mt::update-file',
  'mt::cm-copy-as-markdown',
  'mt::cm-copy-as-html',
  'mt::cm-paste-as-plain-text',
  'mt::cm-insert-paragraph',
  'mt::spelling-replace-misspelling',
  'mt::spelling-show-switch-language',
  // Tab management
  'mt::tabs-cycle-left',
  'mt::tabs-cycle-right',
  'mt::switch-tab-by-index',
  'mt::execute-command-by-id',
  'mt::open-new-tab',
  'mt::bootstrap-editor',
  // Window events
  'mt::window-active-status',
  'mt::window-maximize',
  'mt::window-unmaximize',
  'mt::window-enter-full-screen',
  'mt::window-leave-full-screen',
  'mt::window-zoom',
  'mt::ask-for-close',
  // Preferences
  'mt::user-preference',
  'mt::set-view-layout',
  'mt::toggle-view-layout-entry',
  'mt::toggle-view-mode-entry',
  // Notifications
  'mt::show-notification',
  'mt::show-command-palette',
  'mt::about-dialog',
  'mt::screenshot-captured',
  'mt::print-service-clearup',
  // Updates
  'mt::UPDATE_ERROR',
  'mt::UPDATE_AVAILABLE',
  'mt::UPDATE_NOT_AVAILABLE',
  'mt::UPDATE_DOWNLOADED',
  // Keybindings
  'mt::keybindings-response',
  // Settings
  'settings::change-tab',
  // Social
  'mt::tweet',
  // Sidebar
  'mt::open-directory',
  'mt::update-object-tree',
  // Context menu action responses (from main → renderer)
  'mt::sidebar-context-action',
  'mt::tab-context-action',
  // Image cache
  'mt::invalidate-image-cache',
] as const

const ALLOWED_INVOKE_CHANNELS = [
  'mt::fs-trash-item',
  'mt::spellchecker-set-enabled',
  'mt::spellchecker-switch-language',
  'mt::spellchecker-get-available-dictionaries',
  'mt::spellchecker-get-custom-dictionary-words',
  'mt::spellchecker-remove-word',
  'mt::keybinding-get-keyboard-info',
  'mt::keybinding-get-pref-keybindings',
  'mt::keybinding-save-user-keybindings',
  // Window operations (replacing @electron/remote)
  'mt::window-is-fullscreen',
  'mt::window-is-maximized',
  'mt::get-recently-used-documents',
  'mt::clipboard-has-files',
  'mt::clipboard-get-files',
  'mt::clipboard-guess-file-path',
  'mt::ask-for-image-path',
  'mt::get-available-font-families',
] as const

const sendChannelSet = new Set<string>(ALLOWED_SEND_CHANNELS)
const receiveChannelSet = new Set<string>(ALLOWED_RECEIVE_CHANNELS)
const invokeChannelSet = new Set<string>(ALLOWED_INVOKE_CHANNELS)

// Also allow dynamic channels (e.g., mt::response-of-image-path-${id})
const isDynamicChannel = (channel: string): boolean => {
  return channel.startsWith('mt::response-of-image-path-')
}

const api: PreloadApi = {
  window: {
    close: () => ipcRenderer.send('mt::window-close'),
    minimize: () => ipcRenderer.send('mt::window-minimize'),
    maximize: () => ipcRenderer.send('mt::window-maximize-toggle'),
    unmaximize: () => ipcRenderer.send('mt::window-unmaximize-request'),
    toggleMaximize: () => ipcRenderer.send('mt::window-toggle-maximize'),
    setFullScreen: (flag: boolean) => ipcRenderer.send('mt::window-set-fullscreen', flag),
    isFullScreen: () => ipcRenderer.invoke('mt::window-is-fullscreen'),
    isMaximized: () => ipcRenderer.invoke('mt::window-is-maximized'),
  },

  contextMenu: {
    showSideBarContextMenu: (payload: SideBarContextMenuPayload) =>
      ipcRenderer.send('mt::sidebar-context-menu', payload),
    showTabContextMenu: (payload: TabContextMenuPayload) => ipcRenderer.send('mt::tab-context-menu', payload),
    showAppMenu: (x: number, y: number) => ipcRenderer.send('mt::show-app-menu', x, y),
  },

  clipboard: {
    hasFiles: () => ipcRenderer.invoke('mt::clipboard-has-files'),
    getFiles: () => ipcRenderer.invoke('mt::clipboard-get-files'),
    guessFilePath: () => ipcRenderer.invoke('mt::clipboard-guess-file-path'),
    readText: () => clipboard.readText(),
    writeText: (text: string) => clipboard.writeText(text),
    readHTML: () => clipboard.readHTML(),
    writeHTML: (markup: string) => clipboard.writeHTML(markup),
    readImageDataURL: () => {
      const image = clipboard.readImage()
      if (image.isEmpty()) return ''
      return image.toDataURL()
    },
    writeImageFromDataURL: (dataURL: string) => {
      const image = nativeImage.createFromDataURL(dataURL)
      clipboard.writeImage(image)
    },
    has: (format: string) => clipboard.has(format),
  },

  shell: {
    openExternal: (url: string) => shell.openExternal(url),
    openPath: (path: string) => shell.openPath(path),
    showItemInFolder: (fullPath: string) => shell.showItemInFolder(fullPath),
  },

  fonts: {
    getAvailableFamilies: (onlyMonospace = false) =>
      ipcRenderer.invoke('mt::get-available-font-families', onlyMonospace),
  },

  // Trigger a receive-channel listener locally (renderer-to-renderer, no main process).
  // Used to replace ipcRenderer.emit() calls when contextIsolation is enabled.
  localEmit: (channel: string, ...args: unknown[]) => {
    if (receiveChannelSet.has(channel) || isDynamicChannel(channel)) {
      ipcRenderer.emit(channel, null, ...args)
    } else {
      console.warn(`[preload] Blocked localEmit on unauthorized channel: ${channel}`)
    }
  },

  ipc: {
    send: (channel: string, ...args: unknown[]) => {
      if (sendChannelSet.has(channel)) {
        ipcRenderer.send(channel, ...args)
      } else {
        console.warn(`[preload] Blocked send to unauthorized channel: ${channel}`)
      }
    },
    invoke: (channel: string, ...args: unknown[]) => {
      if (invokeChannelSet.has(channel)) {
        return ipcRenderer.invoke(channel, ...args)
      }
      console.warn(`[preload] Blocked invoke on unauthorized channel: ${channel}`)
      return Promise.reject(new Error(`Unauthorized channel: ${channel}`))
    },
    on: (channel: string, listener: (...args: unknown[]) => void) => {
      if (receiveChannelSet.has(channel) || isDynamicChannel(channel)) {
        // Wrap to strip the event object for security
        const wrappedListener = (_event: Electron.IpcRendererEvent, ...args: unknown[]) => listener(...args)
        ipcRenderer.on(channel, wrappedListener)
        // Store mapping for cleanup
        ;(listener as WrappedIpcListener).__wrappedListener = wrappedListener
      } else {
        console.warn(`[preload] Blocked listener on unauthorized channel: ${channel}`)
      }
    },
    once: (channel: string, listener: (...args: unknown[]) => void) => {
      if (receiveChannelSet.has(channel) || isDynamicChannel(channel)) {
        ipcRenderer.once(channel, (_event: Electron.IpcRendererEvent, ...args: unknown[]) => listener(...args))
      } else {
        console.warn(`[preload] Blocked once listener on unauthorized channel: ${channel}`)
      }
    },
    off: (channel: string, listener: (...args: unknown[]) => void) => {
      const wrappedListener = (listener as WrappedIpcListener).__wrappedListener
      if (wrappedListener) {
        ipcRenderer.off(channel, wrappedListener)
      } else {
        // biome-ignore lint/suspicious/noExplicitAny: listener type structurally differs from Electron's IpcRendererListener (event stripped); safe at runtime
        ipcRenderer.off(channel, listener as any)
      }
    },
  },

  webFrame: {
    getZoomFactor: () => webFrame.getZoomFactor(),
    getZoomLevel: () => webFrame.getZoomLevel(),
    setZoomFactor: (factor: number) => webFrame.setZoomFactor(factor),
    setZoomLevel: (level: number) => webFrame.setZoomLevel(level),
  },

  platform: process.platform,
}

contextBridge.exposeInMainWorld('api', api)
