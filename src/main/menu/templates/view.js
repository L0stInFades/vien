import * as actions from '../actions/view'
import { isOsx } from '../../config'
import { resetZoom, zoomIn, zoomOut } from '../../windows/utils'

export default function (keybindings) {
  const viewMenu = {
    label: '&View',
    submenu: [
      {
        label: 'Command Palette...',
        accelerator: keybindings.getAccelerator('view.command-palette'),
        click(_menuItem, focusedWindow) {
          actions.showCommandPalette(focusedWindow)
        },
      },
      {
        type: 'separator',
      },
      {
        id: 'sourceCodeModeMenuItem',
        label: 'Source Code Mode',
        accelerator: keybindings.getAccelerator('view.source-code-mode'),
        type: 'checkbox',
        checked: false,
        click(_item, focusedWindow) {
          actions.toggleSourceCodeMode(focusedWindow)
        },
      },
      {
        id: 'typewriterModeMenuItem',
        label: 'Typewriter Mode',
        accelerator: keybindings.getAccelerator('view.typewriter-mode'),
        type: 'checkbox',
        checked: false,
        click(_item, focusedWindow) {
          actions.toggleTypewriterMode(focusedWindow)
        },
      },
      {
        id: 'focusModeMenuItem',
        label: 'Focus Mode',
        accelerator: keybindings.getAccelerator('view.focus-mode'),
        type: 'checkbox',
        checked: false,
        click(_item, focusedWindow) {
          actions.toggleFocusMode(focusedWindow)
        },
      },
      {
        type: 'separator',
      },
      {
        label: 'Show Sidebar',
        id: 'sideBarMenuItem',
        accelerator: keybindings.getAccelerator('view.toggle-sidebar'),
        type: 'checkbox',
        checked: false,
        click(_item, focusedWindow) {
          actions.toggleSidebar(focusedWindow)
        },
      },
      {
        label: 'Show Tab Bar',
        id: 'tabBarMenuItem',
        accelerator: keybindings.getAccelerator('view.toggle-tabbar'),
        type: 'checkbox',
        checked: false,
        click(_item, focusedWindow) {
          actions.toggleTabBar(focusedWindow)
        },
      },
      {
        label: 'Toggle Table of Contents',
        id: 'tocMenuItem',
        accelerator: keybindings.getAccelerator('view.toggle-toc'),
        click(_, focusedWindow) {
          actions.showTableOfContents(focusedWindow)
        },
      },
      {
        label: 'Reload Images',
        accelerator: keybindings.getAccelerator('view.reload-images'),
        click(_item, focusedWindow) {
          actions.reloadImageCache(focusedWindow)
        },
      },
    ],
  }

  if (isOsx) {
    viewMenu.submenu.push(
      {
        type: 'separator',
      },
      {
        label: 'Zoom In',
        accelerator: keybindings.getAccelerator('window.zoom-in'),
        click(_item, focusedWindow) {
          zoomIn(focusedWindow)
        },
      },
      {
        label: 'Zoom Out',
        accelerator: keybindings.getAccelerator('window.zoom-out'),
        click(_item, focusedWindow) {
          zoomOut(focusedWindow)
        },
      },
      {
        label: 'Actual Size',
        accelerator: keybindings.getAccelerator('window.zoom-reset'),
        click(_item, focusedWindow) {
          resetZoom(focusedWindow)
        },
      },
      {
        accelerator: keybindings.getAccelerator('window.toggle-full-screen'),
        role: 'togglefullscreen',
      },
    )
  }

  if (global.MARKTEXT_DEBUG) {
    viewMenu.submenu.push({
      type: 'separator',
    })
    viewMenu.submenu.push({
      label: 'Show Developer Tools',
      accelerator: keybindings.getAccelerator('view.toggle-dev-tools'),
      click(_item, win) {
        actions.debugToggleDevTools(win)
      },
    })
    viewMenu.submenu.push({
      label: 'Reload window',
      accelerator: keybindings.getAccelerator('view.dev-reload'),
      click(_item, focusedWindow) {
        actions.debugReloadWindow(focusedWindow)
      },
    })
  }

  return viewMenu
}
