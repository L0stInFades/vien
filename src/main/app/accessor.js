import WindowManager from '../app/windowManager'
import Preference from '../preferences'
import DataCenter from '../dataCenter'
import Keybindings from '../keyboard/shortcutHandler'
import AppMenu from '../menu'
import { loadMenuCommands } from '../menu/actions'
import { CommandManager, loadDefaultCommands } from '../commands'
import { setWindowRegistry } from '../security/ipcGuard'
import { WorkspaceService } from '../services/workspace'
import { AssetService } from '../services/assets'
import { ExportThemeService } from '../services/exportThemes'
import { SearchService } from '../services/search'

class Accessor {
  /**
   * @param {AppEnvironment} appEnvironment The application environment instance.
   */
  constructor(appEnvironment) {
    const userDataPath = appEnvironment.paths.userDataPath

    this.env = appEnvironment
    this.paths = appEnvironment.paths // export paths to make it better accessible

    this.preferences = new Preference(this.paths)
    this.dataCenter = new DataCenter(this.paths)

    this.commandManager = CommandManager
    this._loadCommands()

    this.keybindings = new Keybindings(this.commandManager, appEnvironment)
    this.menu = new AppMenu(this.preferences, this.keybindings, userDataPath)
    this.windowManager = new WindowManager(this.menu, this.preferences)

    // Capability services (ADR-003): validated, window-scoped IPC handlers.
    setWindowRegistry(this.windowManager)
    this.workspaceService = new WorkspaceService(this.windowManager)
    this.assetService = new AssetService(this.windowManager, this.paths, this.dataCenter)
    this.exportThemeService = new ExportThemeService(this.paths)
    this.searchService = new SearchService(this.windowManager)
  }

  _loadCommands() {
    const { commandManager } = this
    loadDefaultCommands(commandManager)
    loadMenuCommands(commandManager)

    if (this.env.isDevMode) {
      commandManager.__verifyDefaultCommands()
    }
  }
}

export default Accessor
