// @vitest-environment node

import { beforeEach, describe, expect, it, vi } from 'vitest'

const clearRecentlyUsed = vi.fn()
const checkUpdates = vi.fn()
const userSetting = vi.fn()
const showAboutDialog = vi.fn()
const toggleAlwaysOnTop = vi.fn()
const resetZoom = vi.fn()
const zoomIn = vi.fn()
const zoomOut = vi.fn()
const buildFromTemplate = vi.fn((template) => ({ items: template }))

vi.mock('electron', () => ({
  Menu: {
    buildFromTemplate,
  },
  app: {
    quit: vi.fn(),
  },
}))

vi.mock('../../../src/main/config.js', () => ({
  isOsx: true,
}))

vi.mock('../../../src/main/menu/actions/file.js', () => ({
  clearRecentlyUsed,
  newBlankTab: vi.fn(),
  newEditorWindow: vi.fn(),
  openFile: vi.fn(),
  openFolder: vi.fn(),
  save: vi.fn(),
  saveAs: vi.fn(),
  autoSave: vi.fn(),
  moveTo: vi.fn(),
  rename: vi.fn(),
  importFile: vi.fn(),
  exportFile: vi.fn(),
  printDocument: vi.fn(),
  closeTab: vi.fn(),
  closeWindow: vi.fn(),
  openFileOrFolder: vi.fn(),
}))

vi.mock('../../../src/main/menu/actions/help.js', () => ({
  showAboutDialog,
}))

vi.mock('../../../src/main/menu/actions/marktext.js', () => ({
  checkUpdates,
  userSetting,
}))

vi.mock('../../../src/main/menu/actions/window.js', () => ({
  minimizeWindow: vi.fn(),
  toggleAlwaysOnTop,
  toggleFullScreen: vi.fn(),
}))

vi.mock('../../../src/main/windows/utils.js', () => ({
  resetZoom,
  zoomIn,
  zoomOut,
}))

const { default: marktextMenuTemplate } = await import('../../../src/main/menu/templates/marktext.js')
const { default: fileMenuTemplate } = await import('../../../src/main/menu/templates/file.js')
const { default: windowMenuTemplate } = await import('../../../src/main/menu/templates/window.js')
const { default: viewMenuTemplate } = await import('../../../src/main/menu/templates/view.js')
const { default: dockMenu } = await import('../../../src/main/menu/templates/dock.js')

const keybindings = {
  getAccelerator(commandId) {
    return commandId
  },
}

describe('macOS native menus', () => {
  beforeEach(() => {
    clearRecentlyUsed.mockClear()
    checkUpdates.mockClear()
    userSetting.mockClear()
    showAboutDialog.mockClear()
    toggleAlwaysOnTop.mockClear()
    resetZoom.mockClear()
    zoomIn.mockClear()
    zoomOut.mockClear()
    buildFromTemplate.mockClear()
  })

  it('uses mac-native roles in the app menu', () => {
    const appMenu = marktextMenuTemplate(keybindings)
    const roles = appMenu.submenu.map((item) => item.role).filter(Boolean)

    expect(appMenu.submenu.some((item) => item.label === 'Settings...')).toBe(true)
    expect(appMenu.submenu.some((item) => item.label === 'Check for Updates...')).toBe(true)
    expect(roles).toEqual(expect.arrayContaining(['services', 'hide', 'hideOthers', 'unhide', 'quit']))
  })

  it('keeps Open Recent and Clear Menu wired to Vien recents on macOS', () => {
    const fileMenu = fileMenuTemplate(
      keybindings,
      {
        getAll() {
          return { autoSave: false }
        },
      },
      ['/tmp/recent.md'],
    )

    const openRecentMenu = fileMenu.submenu.find((item) => item.role === 'recentDocuments')
    const clearMenuItem = openRecentMenu.submenu.find((item) => item.label === 'Clear Menu')

    clearMenuItem.click()

    expect(openRecentMenu).toBeTruthy()
    expect(clearRecentlyUsed).toHaveBeenCalledTimes(1)
  })

  it('moves content zoom to View and keeps Window menu native on macOS', () => {
    const windowMenu = windowMenuTemplate(keybindings)
    const viewMenu = viewMenuTemplate(keybindings)

    expect(windowMenu.submenu.some((item) => item.role === 'minimize')).toBe(true)
    expect(windowMenu.submenu.some((item) => item.role === 'zoom')).toBe(true)
    expect(windowMenu.submenu.some((item) => item.role === 'front')).toBe(true)
    expect(windowMenu.submenu.some((item) => item.label === 'Zoom In')).toBe(false)
    expect(windowMenu.submenu.some((item) => item.label === 'Show in Full Screen')).toBe(false)

    expect(viewMenu.submenu.some((item) => item.label === 'Zoom In')).toBe(true)
    expect(viewMenu.submenu.some((item) => item.label === 'Zoom Out')).toBe(true)
    expect(viewMenu.submenu.some((item) => item.label === 'Actual Size')).toBe(true)
    expect(viewMenu.submenu.some((item) => item.role === 'togglefullscreen')).toBe(true)
  })

  it('clears Vien recents from the Dock menu too', () => {
    const clearRecentItem = dockMenu.items.find((item) => item.label === 'Clear Recent')

    clearRecentItem.click()

    expect(clearRecentlyUsed).toHaveBeenCalledTimes(1)
  })
})
