import { contextBridge, ipcRenderer, webFrame, webUtils } from 'electron'
import type {
  PreloadApi,
  SideBarContextMenuPayload,
  TabContextMenuPayload,
  SearchBatchPayload,
  SearchDonePayload,
} from '../common/types/preload'
import { WorkspaceChannels } from '../common/contracts/workspace'
import { AssetChannels } from '../common/contracts/assets'
import { ExportChannels } from '../common/contracts/export'
import { SearchChannels } from '../common/contracts/search'
import { RecoveryChannels } from '../common/contracts/recovery'
import { LEGACY_INVOKE_CHANNELS, LEGACY_RECEIVE_CHANNELS, LEGACY_SEND_CHANNELS } from '../common/ipcChannels'

/** Listener with an optional attached wrapped version (event-stripped) for ipcRenderer.on/off symmetry */
type WrappedIpcListener = ((...args: unknown[]) => void) & {
  __wrappedListener?: (event: Electron.IpcRendererEvent, ...args: unknown[]) => void
}

const sendChannelSet = new Set<string>(LEGACY_SEND_CHANNELS)
const receiveChannelSet = new Set<string>(LEGACY_RECEIVE_CHANNELS)
const invokeChannelSet = new Set<string>(LEGACY_INVOKE_CHANNELS)

/**
 * Capability invoke: returns the ServiceResult envelope as plain data.
 * contextBridge structured-clones thrown values down to bare messages, so
 * typed errors (code/details) must cross as data — the renderer-side
 * wrapper (src/renderer/services/capability.ts) unwraps and rethrows
 * ServiceError instances.
 */
const invokeCapability = (channel: string, payload: unknown) => ipcRenderer.invoke(channel, payload)

/** Sync bridge call for clipboard methods (sandboxed preload has no clipboard). */
const syncBridge = <T>(channel: string, fallback: T, ...args: unknown[]): T => {
  const result = ipcRenderer.sendSync(channel, ...args) as { ok: boolean; value?: T } | undefined
  return result?.ok ? (result.value as T) : fallback
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
    readText: () => syncBridge('mt::clipboard-read-text-sync', ''),
    writeText: (text: string) => {
      syncBridge('mt::clipboard-write-text-sync', false, text)
    },
    readHTML: () => syncBridge('mt::clipboard-read-html-sync', ''),
    writeHTML: (markup: string) => {
      syncBridge('mt::clipboard-write-html-sync', false, markup)
    },
    readImageDataURL: () => syncBridge('mt::clipboard-read-image-data-url-sync', ''),
    writeImageFromDataURL: (dataURL: string) => {
      syncBridge('mt::clipboard-write-image-data-url-sync', false, dataURL)
    },
    has: (format: string) => syncBridge('mt::clipboard-has-format-sync', false, format),
  },

  shell: {
    openExternal: (url: string) => ipcRenderer.invoke('mt::shell-open-external', url),
    openPath: (path: string) => ipcRenderer.invoke('mt::shell-open-path', path),
    showItemInFolder: (fullPath: string) => {
      ipcRenderer.invoke('mt::shell-show-item-in-folder', fullPath).catch(() => {})
    },
  },

  files: {
    getPathForFile: (file: File) => webUtils.getPathForFile(file),
  },

  fonts: {
    getAvailableFamilies: (onlyMonospace = false) =>
      ipcRenderer.invoke('mt::get-available-font-families', onlyMonospace),
  },

  workspace: {
    create: (pathname: string, kind: 'file' | 'directory') =>
      invokeCapability(WorkspaceChannels.create, { pathname, kind }),
    paste: (src: string, dest: string, kind: 'copy' | 'cut') =>
      invokeCapability(WorkspaceChannels.paste, { src, dest, kind }),
    rename: (src: string, dest: string) => invokeCapability(WorkspaceChannels.rename, { src, dest }),
    isExecutable: (pathname: string) => invokeCapability(WorkspaceChannels.isExecutable, { pathname }),
  },

  assets: {
    copyImageToFolder: (request: unknown) => invokeCapability(AssetChannels.copyImageToFolder, request),
    moveToRelativeFolder: (request: unknown) => invokeCapability(AssetChannels.moveToRelativeFolder, request),
    uploadByCommand: (request: unknown) => invokeCapability(AssetChannels.uploadByCommand, request),
    uploaderAvailable: (uploader: string) => invokeCapability(AssetChannels.uploaderAvailable, { uploader }),
    readImageForUpload: (request: unknown) => invokeCapability(AssetChannels.readImageForUpload, request),
  },

  exportThemes: {
    list: () => invokeCapability(ExportChannels.listThemes, {}),
    read: (name: string) => invokeCapability(ExportChannels.readTheme, { name }),
  },

  search: {
    startContentSearch: (request: unknown) => invokeCapability(SearchChannels.contentStart, request),
    startFileSearch: (request: unknown) => invokeCapability(SearchChannels.filesStart, request),
    cancel: (searchId: string) => invokeCapability(SearchChannels.cancel, { searchId }),
    onResultBatch: (listener: (batch: SearchBatchPayload) => void) => {
      const wrapped = (_event: Electron.IpcRendererEvent, batch: unknown) => listener(batch as SearchBatchPayload)
      ipcRenderer.on(SearchChannels.resultBatch, wrapped)
      return () => {
        ipcRenderer.off(SearchChannels.resultBatch, wrapped)
      }
    },
    onDone: (listener: (done: SearchDonePayload) => void) => {
      const wrapped = (_event: Electron.IpcRendererEvent, done: unknown) => listener(done as SearchDonePayload)
      ipcRenderer.on(SearchChannels.done, wrapped)
      return () => {
        ipcRenderer.off(SearchChannels.done, wrapped)
      }
    },
  },

  recovery: {
    snapshot: (request: unknown) => invokeCapability(RecoveryChannels.snapshot, request),
    discard: (tabId: string) => invokeCapability(RecoveryChannels.discard, { tabId }),
    list: () => invokeCapability(RecoveryChannels.list, {}),
  },

  // Trigger a receive-channel listener locally (renderer-to-renderer, no main process).
  // Used to replace ipcRenderer.emit() calls when contextIsolation is enabled.
  localEmit: (channel: string, ...args: unknown[]) => {
    if (receiveChannelSet.has(channel)) {
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
      if (receiveChannelSet.has(channel)) {
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
      if (receiveChannelSet.has(channel)) {
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
