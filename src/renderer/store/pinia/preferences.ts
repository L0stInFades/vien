import { defineStore } from 'pinia'
import bus from '../../bus'

export const usePreferencesStore = defineStore('preferences', {
  state: () => ({
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
    sideBarVisibility: false,
    tabBarVisibility: true,
    sourceCodeModeEnabled: false,
    searchExclusions: [],
    searchMaxFileSize: '',
    searchIncludeHidden: false,
    searchNoIgnore: false,
    searchFollowSymlinks: true,
    watcherUsePolling: false,
    typewriter: false,
    focus: false,
    sourceCode: false,
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
  }),
  actions: {
    setUserPreference(preference: Record<string, unknown>) {
      const state = this as unknown as Record<string, unknown>
      Object.keys(preference).forEach((key) => {
        if (typeof preference[key] !== 'undefined' && typeof state[key] !== 'undefined') {
          state[key] = preference[key]
        }
      })
    },
    setMode({ type, checked }: { type: string; checked: boolean }) {
      ;(this as unknown as Record<string, unknown>)[type] = checked
    },
    toggleViewMode(entryName: string) {
      const state = this as unknown as Record<string, unknown>
      state[entryName] = !state[entryName]
    },
    askForUserPreference() {
      window.api.ipc.send('mt::ask-for-user-preference')
      window.api.ipc.send('mt::ask-for-user-data')

      window.api.ipc.on('mt::user-preference', (preferences: unknown) => {
        this.setUserPreference(preferences as Record<string, unknown>)
      })
    },
    setSinglePreference({ type, value }: { type: string; value: unknown }) {
      window.api.ipc.send('mt::set-user-preference', { [type]: value })
    },
    setUserData({ type, value }: { type: string; value: unknown }) {
      window.api.ipc.send('mt::set-user-data', { [type]: value })
    },
    setImageFolderPath(value: string) {
      window.api.ipc.send('mt::ask-for-modify-image-folder-path', value)
    },
    selectDefaultDirectoryToOpen() {
      window.api.ipc.send('mt::select-default-directory-to-open')
    },
    dispatchEditorViewState(viewState: Record<string, unknown>) {
      const { windowId } = window.marktext.env
      window.api.ipc.send('mt::view-layout-changed', windowId, viewState)
    },
    listenForView() {
      window.api.ipc.on('mt::show-command-palette', () => {
        bus.emit('show-command-palette')
      })
      window.api.ipc.on('mt::toggle-view-mode-entry', (entryName: unknown) => {
        if (typeof entryName === 'string') {
          this.toggleViewMode(entryName)
          const state = this as unknown as Record<string, unknown>
          this.dispatchEditorViewState({ [entryName]: state[entryName] })
        }
      })
    },
    listenToggleView() {
      bus.on('view:toggle-view-entry', (entryName) => {
        if (typeof entryName === 'string') {
          this.toggleViewMode(entryName)
          const state = this as unknown as Record<string, unknown>
          this.dispatchEditorViewState({ [entryName]: state[entryName] })
        }
      })
    },
  },
})
