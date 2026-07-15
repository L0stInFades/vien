import notice from '../services/notification'

const state = {}

const getters = {}

const mutations = {}

const actions = {
  LISTEN_FOR_NOTIFICATION() {
    const DEFAULT_OPTS = {
      title: 'Infomation',
      type: 'primary',
      time: 10000,
      message: 'You should never see this message',
    }

    window.api.ipc.on('mt::show-notification', (opts) => {
      const options = Object.assign(DEFAULT_OPTS, opts)

      notice.notify(options)
    })

    window.api.ipc.on('mt::pandoc-not-exists', async (opts) => {
      const options = Object.assign(DEFAULT_OPTS, opts)
      options.showConfirm = true
      await notice.notify(options)
      window.api.shell.openExternal('http://pandoc.org')
    })
  },
}

export default { state, getters, mutations, actions }
