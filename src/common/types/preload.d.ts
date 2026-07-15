/**
 * Type definitions for the preload API exposed via contextBridge.
 *
 * The renderer process accesses these APIs through `window.api`.
 */

export interface WindowApi {
  close(): void
  minimize(): void
  maximize(): void
  unmaximize(): void
  toggleMaximize(): void
  setFullScreen(flag: boolean): void
  isFullScreen(): Promise<boolean>
  isMaximized(): Promise<boolean>
}

export interface ContextMenuApi {
  showSideBarContextMenu(items: SideBarContextMenuPayload): void
  showTabContextMenu(items: TabContextMenuPayload): void
  showAppMenu(x: number, y: number): void
}

export interface SideBarContextMenuPayload {
  hasPathCache: boolean
  x: number
  y: number
}

export interface TabContextMenuPayload {
  tabId: string
  pathname: string | null
  x: number
  y: number
}

export interface ClipboardApi {
  /** Check if clipboard has file paths (macOS NSFilenamesPboardType) */
  hasFiles(): Promise<boolean>
  /** Get file paths from clipboard (macOS plist or Windows FileNameW) */
  getFiles(): Promise<string[]>
  /** Guess a single clipboard file path */
  guessFilePath(): Promise<string>
  /** Read text from clipboard */
  readText(): string
  /** Write text to clipboard */
  writeText(text: string): void
  /** Read HTML from clipboard */
  readHTML(): string
  /** Write HTML to clipboard */
  writeHTML(markup: string): void
  /** Read image from clipboard (returns data URL or empty string) */
  readImageDataURL(): string
  /** Write image to clipboard from data URL */
  writeImageFromDataURL(dataURL: string): void
  /** Check if clipboard has text */
  has(format: string): boolean
}

export interface ShellApi {
  openExternal(url: string): Promise<void>
  openPath(path: string): Promise<string>
  showItemInFolder(fullPath: string): void
}

export interface FontsApi {
  getAvailableFamilies(onlyMonospace?: boolean): Promise<string[]>
}

export interface IpcApi {
  send(channel: string, ...args: unknown[]): void
  invoke(channel: string, ...args: unknown[]): Promise<unknown>
  on(channel: string, listener: (...args: unknown[]) => void): void
  once(channel: string, listener: (...args: unknown[]) => void): void
  off(channel: string, listener: (...args: unknown[]) => void): void
}

export interface WebFrameApi {
  getZoomFactor(): number
  getZoomLevel(): number
  setZoomFactor(factor: number): void
  setZoomLevel(level: number): void
}

export interface PreloadApi {
  window: WindowApi
  contextMenu: ContextMenuApi
  clipboard: ClipboardApi
  shell: ShellApi
  fonts: FontsApi
  /** Trigger a receive-channel listener locally (renderer → renderer, no main process roundtrip). */
  localEmit(channel: string, ...args: unknown[]): void
  ipc: IpcApi
  webFrame: WebFrameApi
  platform: NodeJS.Platform
}

export interface MarktextRuntime {
  env: {
    windowId: number
    type: string
    [key: string]: unknown
  }
  paths?: {
    userDataPath?: string
    [key: string]: unknown
  }
  initialState?: Record<string, unknown>
  [key: string]: unknown
}

declare global {
  interface Window {
    api: PreloadApi
    marktext: MarktextRuntime
  }
}
