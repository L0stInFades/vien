import { defineStore } from 'pinia'
import bus from '../../bus'

type LayoutEntryName = 'showSideBar' | 'showTabBar' | 'rightColumn'

const storedSideBarWidth = Number(localStorage.getItem('side-bar-width'))
const sideBarWidth = Number.isFinite(storedSideBarWidth) ? Math.max(storedSideBarWidth, 220) : 280

export const useLayoutStore = defineStore('layout', {
  state: () => ({
    rightColumn: 'files',
    showSideBar: false,
    showTabBar: true,
    sideBarWidth,
  }),
  actions: {
    setLayout(layout: Record<string, unknown>) {
      if (layout.showSideBar !== undefined) {
        const { windowId } = window.marktext.env
        window.api.ipc.send('mt::update-sidebar-menu', windowId, !!layout.showSideBar)
      }
      Object.assign(this, layout)
    },
    toggleLayoutEntry(entryName: LayoutEntryName) {
      const state = this as unknown as Record<LayoutEntryName, unknown>
      state[entryName] = !state[entryName]
    },
    setSideBarWidth(width: number) {
      localStorage.setItem('side-bar-width', String(Math.max(+width, 220)))
      this.sideBarWidth = width
    },
    dispatchLayoutMenuItems() {
      const { windowId } = window.marktext.env
      const { showTabBar, showSideBar } = this
      window.api.ipc.send('mt::view-layout-changed', windowId, { showTabBar, showSideBar })
    },
    changeSideBarWidth(width: number) {
      this.setSideBarWidth(width)
    },
    listen() {
      window.api.ipc.on('mt::set-view-layout', (layout: unknown) => {
        const nextLayout = layout as Record<string, unknown>
        if (nextLayout.rightColumn) {
          this.setLayout({
            ...nextLayout,
            rightColumn: nextLayout.rightColumn === this.rightColumn ? '' : nextLayout.rightColumn,
            showSideBar: true,
          })
        } else {
          this.setLayout(nextLayout)
        }
        this.dispatchLayoutMenuItems()
      })

      window.api.ipc.on('mt::toggle-view-layout-entry', (entryName: unknown) => {
        if (isLayoutEntryName(entryName)) {
          this.toggleLayoutEntry(entryName)
          this.dispatchLayoutMenuItems()
        }
      })

      bus.on('view:toggle-layout-entry', (entryName) => {
        if (isLayoutEntryName(entryName)) {
          this.toggleLayoutEntry(entryName)
          const { windowId } = window.marktext.env
          const state = this as unknown as Record<LayoutEntryName, unknown>
          window.api.ipc.send('mt::view-layout-changed', windowId, { [entryName]: state[entryName] })
        }
      })
    },
  },
})

const isLayoutEntryName = (value: unknown): value is LayoutEntryName =>
  value === 'showSideBar' || value === 'showTabBar' || value === 'rightColumn'
