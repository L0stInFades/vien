const fs = require('node:fs')
const path = require('node:path')
const { tmpdir } = require('node:os')
const { execFileSync, spawn } = require('node:child_process')

const projectRoot = path.resolve(__dirname, '..')
const defaultAppPath =
  process.arch === 'arm64'
    ? path.join(projectRoot, 'build', 'mac-arm64', 'Vien.app')
    : path.join(projectRoot, 'build', 'mac', 'Vien.app')
const appPath = path.resolve(process.argv[2] || defaultAppPath)
const binaryPath = path.join(appPath, 'Contents', 'MacOS', 'Vien')
const appAsarPath = path.join(appPath, 'Contents', 'Resources', 'app.asar')
const appAsarUnpackedPath = `${appAsarPath}.unpacked`
const processPattern = `${appPath}/Contents/MacOS/Vien`
const smokeLogPath = path.join(tmpdir(), 'vien-mac-smoke.log')
const packagedNodeModules = ['fs-extra', 'jsonfile', 'universalify', 'iconv-lite', 'safer-buffer']
const packagedNativeModules = [
  ['ced', 'build', 'Release', 'ced.node'],
  ['fontmanager-redux', 'build', 'Release', 'fontmanager.node'],
  ['keytar', 'build', 'Release', 'keytar.node'],
  ['native-keymap', 'build', 'Release', 'keymapping.node'],
]

const sleep = (ms) => new Promise((resolve) => {
  setTimeout(resolve, ms)
})

const getRunningPids = () => {
  try {
    const stdout = execFileSync('pgrep', ['-f', processPattern], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })
    return stdout.split('\n').map((line) => line.trim()).filter(Boolean)
  } catch (_) {
    return []
  }
}

const stopRunningBundle = () => {
  const pids = getRunningPids()
  if (pids.length === 0) {
    return
  }

  execFileSync('pkill', ['-f', processPattern], { stdio: 'ignore' })
}

const readSmokeLog = () => {
  if (!fs.existsSync(smokeLogPath)) {
    return ''
  }

  return fs.readFileSync(smokeLogPath, 'utf8').trim()
}

const verifyPackagedNodeModules = () => {
  const verificationScript = `
    const path = require('node:path')
    const appAsar = process.env.VIEN_APP_ASAR
    const appAsarUnpacked = process.env.VIEN_APP_ASAR_UNPACKED
    for (const moduleName of ${JSON.stringify(packagedNodeModules)}) {
      require(path.join(appAsar, 'node_modules', moduleName))
    }
    for (const modulePath of ${JSON.stringify(packagedNativeModules)}) {
      require(path.join(appAsarUnpacked, 'node_modules', ...modulePath))
    }
    process.stdout.write('verified-packaged-node-modules\\n')
  `

  execFileSync(binaryPath, ['-e', verificationScript], {
    encoding: 'utf8',
    env: {
      ...process.env,
      ELECTRON_RUN_AS_NODE: '1',
      VIEN_APP_ASAR: appAsarPath,
      VIEN_APP_ASAR_UNPACKED: appAsarUnpackedPath,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
}

const verifyPackagedRipgrep = () => {
  for (const arch of ['x64', 'arm64']) {
    const rgPath = path.join(
      appAsarUnpackedPath,
      'node_modules',
      `@vscode/ripgrep-darwin-${arch}`,
      'bin',
      'rg',
    )
    if (!fs.existsSync(rgPath)) {
      throw new Error(`Missing packaged ripgrep binary: ${rgPath}`)
    }
    if (arch === process.arch) {
      execFileSync(rgPath, ['--version'], { stdio: ['ignore', 'pipe', 'pipe'] })
    }
  }
}

const main = async () => {
  if (process.platform !== 'darwin') {
    throw new Error('verify:mac-bundle can only run on macOS.')
  }

  if (!fs.existsSync(binaryPath)) {
    throw new Error(`Missing app bundle binary: ${binaryPath}`)
  }
  if (!fs.existsSync(appAsarPath)) {
    throw new Error(`Missing app bundle archive: ${appAsarPath}`)
  }

  fs.writeFileSync(smokeLogPath, '', 'utf8')
  stopRunningBundle()
  verifyPackagedNodeModules()
  verifyPackagedRipgrep()

  const stdout = fs.openSync(smokeLogPath, 'a')
  const child = spawn(binaryPath, [], {
    cwd: projectRoot,
    detached: true,
    stdio: ['ignore', stdout, stdout],
    env: {
      ...process.env,
      MARKTEXT_EXIT_ON_ERROR: '1',
    },
  })

  child.unref()
  fs.closeSync(stdout)

  for (let attempt = 0; attempt < 20; attempt += 1) {
    await sleep(500)

    if (getRunningPids().length > 0) {
      stopRunningBundle()
      console.log(`Verified packaged app launch: ${appPath}`)
      return
    }
  }

  const smokeLog = readSmokeLog()
  stopRunningBundle()
  throw new Error(
    `Packaged app failed to stay running: ${appPath}${smokeLog ? `\n\nSmoke log:\n${smokeLog}` : ''}`,
  )
}

main().catch((error) => {
  console.error(error.message || error)
  process.exit(1)
})
