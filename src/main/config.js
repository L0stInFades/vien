import path from 'node:path'

export const isOsx = process.platform === 'darwin'
export const isWindows = process.platform === 'win32'
export const isLinux = process.platform === 'linux'

// Resolve preload script path. Both main.js and preload.js are output to the
// same directory (dist/electron/), so __dirname reliably points to preload.js.
const preloadPath = path.join(__dirname, 'preload.js')

export const editorWinOptions = Object.freeze({
  minWidth: 550,
  minHeight: 350,
  webPreferences: {
    preload: preloadPath,
    contextIsolation: true,
    // WORKAROUND: We cannot enable spellcheck if it was disabled during
    // renderer startup due to a bug in Electron (Electron#32755). We'll
    // enable it always and set the HTML spelling attribute to false.
    spellcheck: true,
    nodeIntegration: false,
    // BOUNDARY-002: same-origin policy stays ON. Local document images load
    // through the controlled vien-asset:// protocol, never by disabling
    // webSecurity.
    webSecurity: true,
    // PLAN.md §5.7: renderer sandbox enabled. The preload uses only
    // sandbox-available modules (ipcRenderer, contextBridge, webFrame's
    // zoom subset); clipboard/shell/nativeImage go through the validated
    // main-process preload bridge (src/main/ipc/preloadBridge.js).
    sandbox: true,
  },
  useContentSize: true,
  show: true,
  frame: false,
  titleBarStyle: 'hiddenInset',
  zoomFactor: 1.0,
})

export const preferencesWinOptions = Object.freeze({
  minWidth: 450,
  minHeight: 350,
  width: 950,
  height: 650,
  webPreferences: {
    preload: preloadPath,
    contextIsolation: true,
    // Always true to access native spellchecker.
    spellcheck: true,
    nodeIntegration: false,
    // BOUNDARY-002: same-origin policy stays ON (see editorWinOptions).
    webSecurity: true,
    // PLAN.md §5.7: sandbox enabled (see editorWinOptions).
    sandbox: true,
  },
  fullscreenable: false,
  fullscreen: false,
  minimizable: false,
  useContentSize: true,
  show: true,
  frame: false,
  thickFrame: !isOsx,
  titleBarStyle: 'hiddenInset',
  zoomFactor: 1.0,
})

export const PANDOC_EXTENSIONS = Object.freeze([
  'html',
  'docx',
  'odt',
  'latex',
  'tex',
  'ltx',
  'rst',
  'rest',
  'org',
  'wiki',
  'dokuwiki',
  'textile',
  'opml',
  'epub',
])

export const BLACK_LIST = Object.freeze(['$RECYCLE.BIN'])

export const EXTENSION_HASN = Object.freeze({
  styledHtml: '.html',
  pdf: '.pdf',
})

export const TITLE_BAR_HEIGHT = isOsx ? 21 : 32
export const LINE_ENDING_REG = /(?:\r\n|\n)/g
export const LF_LINE_ENDING_REG = /(?:[^\r]\n)|(?:^\n$)/
export const CRLF_LINE_ENDING_REG = /\r\n/

export const GITHUB_REPO_URL = 'https://github.com/L0stInFades/vien'
// copy from muya
export const URL_REG =
  /^http(s)?:\/\/([a-z0-9\-._~]+\.[a-z]{2,}|[0-9.]+|localhost|\[[a-f0-9.:]+\])(:[0-9]{1,5})?(\/[\S]+)?/i
