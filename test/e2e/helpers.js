const { execFileSync } = require('node:child_process')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { _electron } = require('@playwright/test')

const mainEntrypoint = 'dist/electron/main.js'
const launchedApps = new WeakMap()

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const getTempPath = () => {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'vien-e2etest-'))
}

const getElectronPath = () => {
  const launcherName = process.platform === 'win32' ? 'electron.cmd' : 'electron'
  return path.resolve(path.join('node_modules', '.bin', launcherName))
}

const readProcessTable = () => {
  if (process.platform === 'win32') {
    return []
  }

  try {
    const output = execFileSync('ps', ['-Ao', 'pid=,ppid=,command='], { encoding: 'utf8' })
    return output
      .split('\n')
      .map((line) => {
        const match = line.trim().match(/^(\d+)\s+(\d+)\s+(.*)$/)
        if (!match) {
          return null
        }

        return {
          pid: Number(match[1]),
          ppid: Number(match[2]),
          command: match[3],
        }
      })
      .filter(Boolean)
  } catch (_error) {
    return []
  }
}

const findDescendantPids = (rootPid) => {
  if (!rootPid) {
    return []
  }

  const processTable = readProcessTable()
  const descendants = []
  const queue = [rootPid]

  while (queue.length) {
    const parentPid = queue.shift()
    for (const processInfo of processTable) {
      if (processInfo.ppid !== parentPid) {
        continue
      }

      descendants.push(processInfo.pid)
      queue.push(processInfo.pid)
    }
  }

  return descendants
}

const killPid = (pid, signal = 'SIGKILL') => {
  if (!pid) {
    return
  }

  try {
    process.kill(pid, signal)
  } catch (error) {
    if (error.code !== 'ESRCH') {
      throw error
    }
  }
}

const forceKillProcessTree = (rootPid) => {
  if (!rootPid) {
    return
  }

  if (process.platform === 'win32') {
    try {
      execFileSync('taskkill', ['/PID', String(rootPid), '/T', '/F'], { stdio: 'ignore' })
    } catch (_error) {
      // Ignore failures if the process already exited.
    }
    return
  }

  const descendants = findDescendantPids(rootPid)
  for (const pid of descendants.reverse()) {
    killPid(pid)
  }
  killPid(rootPid)
}

const findTrackedPids = (userDataDir) => {
  if (!userDataDir || process.platform === 'win32') {
    return []
  }

  return readProcessTable()
    .filter((processInfo) => processInfo.command.includes(userDataDir))
    .map((processInfo) => processInfo.pid)
}

const normalizeLaunchOptions = (launchOptions) => {
  if (Array.isArray(launchOptions)) {
    return {
      args: launchOptions,
      userDataDir: null,
    }
  }

  return {
    args: launchOptions?.args || [],
    userDataDir: launchOptions?.userDataDir || null,
  }
}

const launchElectron = async (launchOptions) => {
  const { args: userArgs, userDataDir: providedUserDataDir } = normalizeLaunchOptions(launchOptions)
  const executablePath = getElectronPath()
  const userDataDir = providedUserDataDir || getTempPath()
  const args = [mainEntrypoint, '--user-data-dir', userDataDir].concat(userArgs)
  const app = await _electron.launch({
    executablePath,
    args,
    timeout: 30000,
  })
  launchedApps.set(app, { pid: app.process()?.pid ?? null, userDataDir })
  const page = await app.firstWindow()
  await page.waitForLoadState('domcontentloaded')
  await new Promise((resolve) => setTimeout(resolve, 500))
  return { app, page, userDataDir }
}

const closeElectron = async (app) => {
  if (!app) {
    return
  }

  const trackedApp = launchedApps.get(app)
  let electronProcess = null
  try {
    electronProcess = typeof app.process === 'function' ? app.process() : null
  } catch (_error) {
    electronProcess = null
  }
  const waitForExit = electronProcess
    ? new Promise((resolve) => {
        if (electronProcess.exitCode !== null || electronProcess.signalCode !== null) {
          resolve()
          return
        }
        electronProcess.once('exit', resolve)
      })
    : Promise.resolve()

  try {
    await Promise.race([
      app.evaluate(({ BrowserWindow, app: electronApp }) => {
        for (const window of BrowserWindow.getAllWindows()) {
          window.removeAllListeners('close')
          window.destroy()
        }
        electronApp.exit(0)
      }),
      delay(2000),
    ])
  } catch (_error) {
    // Fall back to process-tree cleanup below if Electron refuses to exit.
  }

  await Promise.race([waitForExit, delay(2000)])

  if (electronProcess && electronProcess.exitCode === null && electronProcess.signalCode === null) {
    forceKillProcessTree(electronProcess.pid)
    await Promise.race([waitForExit, delay(1000)])
  }

  if (trackedApp?.userDataDir) {
    const lingeringPids = findTrackedPids(trackedApp.userDataDir)
    for (const pid of lingeringPids) {
      killPid(pid)
    }
    await delay(250)
    for (const pid of findTrackedPids(trackedApp.userDataDir)) {
      killPid(pid)
    }
  }

  launchedApps.delete(app)
}

module.exports = { closeElectron, getElectronPath, launchElectron }
