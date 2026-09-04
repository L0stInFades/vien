import bus from '../bus'

// user preference
const state = {
  autoSave: false,
  autoSaveDelay: 5000,
  titleBarStyle: 'custom',
  openFilesInNewWindow: false,
  openFolderInNewWindow: false,
  zoom: 1.0,
  hideScrollbar: false,
  wordWrapInToc: false,
  fileSortBy: 'created',
  startUpAction: 'lastState',
  defaultDirectoryToOpen: '',
  language: 'en',

  editorFontFamily: 'Open Sans',
  fontSize: 16,
  lineHeight: 1.6,
  codeFontSize: 14,
  codeFontFamily: 'DejaVu Sans Mono',
  codeBlockLineNumbers: true,
  trimUnnecessaryCodeBlockEmptyLines: true,
  editorLineWidth: '',

  autoPairBracket: true,
  autoPairMarkdownSyntax: true,
  autoPairQuote: true,
  endOfLine: 'default',
  defaultEncoding: 'utf8',
  autoGuessEncoding: true,
  trimTrailingNewline: 2,
  textDirection: 'ltr',
  hideQuickInsertHint: true,
  imageInsertAction: 'folder',
  imagePreferRelativeDirectory: false,
  imageRelativeDirectoryName: 'assets',
  hideLinkPopup: false,
  autoCheck: false,

  preferLooseListItem: true,
  bulletListMarker: '-',
  orderListDelimiter: '.',
  preferHeadingStyle: 'atx',
  tabSize: 4,
  listIndentation: 1,
  frontmatterType: '-',
  superSubScript: false,
  footnote: false,
  isHtmlEnabled: true,
  isGitlabCompatibilityEnabled: false,
  sequenceTheme: 'hand',

  theme: 'light',
  autoSwitchTheme: 2,

  spellcheckerEnabled: false,
  spellcheckerNoUnderline: false,
  spellcheckerLanguage: 'en-US',

  // Default values that are overwritten with the entries below.
  sideBarVisibility: false,
  tabBarVisibility: true,
  sourceCodeModeEnabled: false,

  searchExclusions: [],
  searchMaxFileSize: '',
  searchIncludeHidden: false,
  searchNoIgnore: false,
  searchFollowSymlinks: true,

  watcherUsePolling: false,

  // --------------------------------------------------------------------------

  // Edit modes of the current window (not part of persistent settings)
  typewriter: false, // typewriter mode
  focus: false, // focus mode
  sourceCode: false, // source code mode

  // user configration
  imageFolderPath: '',
  webImages: [],
  cloudImages: [],
  currentUploader: 'none',
  githubToken: '',
  imageBed: {
    github: {
      owner: '',
      repo: '',
      branch: '',
    },
  },
  cliScript: '',
}

const getters = {}

const mutations = {
  SET_USER_PREFERENCE(state, preference) {
    Object.keys(preference).forEach((key) => {
      if (typeof preference[key] !== 'undefined' && typeof state[key] !== 'undefined') {
        state[key] = preference[key]
      }
    })
  },
  SET_MODE(state, { type, checked }) {
    state[type] = checked
  },
  TOGGLE_VIEW_MODE(state, entryName) {
    state[entryName] = !state[entryName]
  },
}

const actions = {
  ASK_FOR_USER_PREFERENCE({ commit }) {
    window.api.ipc.send('mt::ask-for-user-preference')
    window.api.ipc.send('mt::ask-for-user-data')

    window.api.ipc.on('mt::user-preference', (preferences) => {
      commit('SET_USER_PREFERENCE', preferences)
    })
  },

  SET_SINGLE_PREFERENCE(_context, { type, value }) {
    // save to electron-store
    window.api.ipc.send('mt::set-user-preference', { [type]: value })
  },

  SET_USER_DATA(_context, { type, value }) {
    window.api.ipc.send('mt::set-user-data', { [type]: value })
  },

  SET_IMAGE_FOLDER_PATH(_context, value) {
    window.api.ipc.send('mt::ask-for-modify-image-folder-path', value)
  },

  SELECT_DEFAULT_DIRECTORY_TO_OPEN() {
    window.api.ipc.send('mt::select-default-directory-to-open')
  },

  LISTEN_FOR_VIEW({ commit, dispatch }) {
    window.api.ipc.on('mt::show-command-palette', () => {
      bus.emit('show-command-palette')
    })
    window.api.ipc.on('mt::toggle-view-mode-entry', (entryName) => {
      commit('TOGGLE_VIEW_MODE', entryName)
      dispatch('DISPATCH_EDITOR_VIEW_STATE', { [entryName]: state[entryName] })
    })
  },

  // Toggle a view option and notify main process to toggle menu item.
  LISTEN_TOGGLE_VIEW({ commit, dispatch, state }) {
    bus.on('view:toggle-view-entry', (entryName) => {
      commit('TOGGLE_VIEW_MODE', entryName)
      dispatch('DISPATCH_EDITOR_VIEW_STATE', { [entryName]: state[entryName] })
    })
  },

  DISPATCH_EDITOR_VIEW_STATE(_, viewState) {
    const { windowId } = window.marktext.env
    window.api.ipc.send('mt::view-layout-changed', windowId, viewState)
  },
}

const preferences = { state, getters, mutations, actions }

export default preferences
