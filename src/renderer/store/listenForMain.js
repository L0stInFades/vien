import bus from '../bus'

const state = {}

const getters = {}

const mutations = {}

const actions = {
  LISTEN_FOR_EDIT({ commit }) {
    window.api.ipc.on('mt::editor-edit-action', (type) => {
      if (type === 'findInFolder') {
        commit('SET_LAYOUT', {
          rightColumn: 'search',
          showSideBar: true,
        })
      }
      bus.emit(type, type)
    })
  },

  LISTEN_FOR_SHOW_DIALOG() {
    window.api.ipc.on('mt::about-dialog', () => {
      bus.emit('aboutDialog')
    })
    window.api.ipc.on('mt::show-export-dialog', (type) => {
      bus.emit('showExportDialog', type)
    })
  },

  LISTEN_FOR_PARAGRAPH_INLINE_STYLE() {
    window.api.ipc.on('mt::editor-paragraph-action', ({ type }) => {
      bus.emit('paragraph', type)
    })
    window.api.ipc.on('mt::editor-format-action', ({ type }) => {
      bus.emit('format', type)
    })
  },
}

const listenForMain = { state, getters, mutations, actions }

export default listenForMain
