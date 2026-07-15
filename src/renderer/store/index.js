import { createStore } from 'vuex'

import listenForMain from './listenForMain'
import project from './project'
import editor from './editor'
import layout from './layout'
import preferences from './preferences'
import commandCenter from './commandCenter'

// global states
const state = {
  platform: process.platform, // platform of system `darwin` | `win32` | `linux`
  appVersion: process.versions.MARKTEXT_VERSION_STRING, // Vien version string
  windowActive: true, // whether current window is active or focused
  init: false, // whether Vien is initialized
}

const getters = {}

const mutations = {
  SET_WIN_STATUS(state, status) {
    state.windowActive = status
  },
  SET_INITIALIZED(state) {
    state.init = true
  },
}

const actions = {
  LINTEN_WIN_STATUS({ commit }) {
    window.api.ipc.on('mt::window-active-status', ({ status }) => {
      commit('SET_WIN_STATUS', status)
    })
  },

  SEND_INITIALIZED({ commit }) {
    commit('SET_INITIALIZED')
  },
}

const store = createStore({
  state,
  getters,
  mutations,
  actions,
  modules: {
    // have no states
    listenForMain,
    // have states
    project,
    preferences,
    editor,
    layout,
    commandCenter,
  },
})

export default store
