import './globalSetting'
import path from 'node:path'
import { app, dialog } from 'electron'
import cli from './cli'
import setupExceptionHandler, { initExceptionLogger } from './exceptionHandler'
import log from 'electron-log'
import App from './app'
import Accessor from './app/accessor'
import setupEnvironment from './app/env'
import { getLogLevel } from './utils'
import { registerWindowBridgeHandlers } from './ipc/windowBridge'
import { registerPreloadBridgeHandlers } from './ipc/preloadBridge'
import { registerAssetSchemePrivileges } from './security/assetProtocol'

const initializeLogger = (appEnvironment) => {
  log.transports.console.level = process.env.NODE_ENV === 'development' ? 'info' : 'error'
  log.transports.rendererConsole = null
  log.transports.file.resolvePath = () => path.join(appEnvironment.paths.logPath, 'main.log')
  log.transports.file.level = getLogLevel()
  log.transports.file.sync = true
  initExceptionLogger()
}

// -----------------------------------------------

app.setName('Vien')

// Custom protocol privileges must be declared before the app is ready.
registerAssetSchemePrivileges()

// Vien is built, tested, and released for macOS only.
if (process.platform !== 'darwin') {
  process.stdout.write(`Operating system "${process.platform}" is not supported. Vien currently requires macOS.\n`)
  process.exit(1)
}

setupExceptionHandler()

const args = cli()
const appEnvironment = setupEnvironment(args)
initializeLogger(appEnvironment)

if (args['--disable-gpu']) {
  app.disableHardwareAcceleration()
}

// Keep Vien as a single-instance application.
if (!process.mas && process.env.NODE_ENV !== 'development') {
  const gotSingleInstanceLock = app.requestSingleInstanceLock()
  if (!gotSingleInstanceLock) {
    process.stdout.write('Another Vien instance was detected: exiting...\n')
    app.exit()
  }
}

// The application environment is configured successfully. You can now access paths, use the logger etc.
// Create other instances that need access to the modules from above.
let accessor = null
try {
  accessor = new Accessor(appEnvironment)
} catch (err) {
  // Catch errors that may come from invalid configuration files like settings.
  const msgHint = err.message.includes('Config schema violation')
    ? 'This seems to be an issue with your configuration file(s). '
    : ''
  log.error(`Loading Vien failed during initialization. ${msgHint}`, err)

  const EXIT_ON_ERROR = !!process.env.MARKTEXT_EXIT_ON_ERROR
  const SHOW_ERROR_DIALOG = !process.env.MARKTEXT_ERROR_INTERACTION
  if (!EXIT_ON_ERROR && SHOW_ERROR_DIALOG) {
    dialog.showErrorBox('There was an error during loading', `${msgHint}${err.message}\n\n${err.stack}`)
  }
  process.exit(1)
}

// Use synchronous only to report errors in early stage of startup.
log.transports.file.sync = false

// -----------------------------------------------
// Be careful when changing code before this line!
// NOTE: Do not create classes or other code before this line!

// Register IPC handlers for preload bridge (replaces @electron/remote)
registerWindowBridgeHandlers()
registerPreloadBridgeHandlers()

const application = new App(accessor, args)
application.init()
