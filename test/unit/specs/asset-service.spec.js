/**
 * AssetService integration tests (PLAN.md ASSET-001): image relocation and
 * uploader tools on a real temp filesystem, electron mocked.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest'

const handlers = new Map()
const fromWebContentsMock = vi.fn()

vi.mock('electron', () => ({
  ipcMain: {
    handle: (channel, fn) => handlers.set(channel, fn),
    removeHandler: (channel) => handlers.delete(channel),
  },
  BrowserWindow: { fromWebContents: (...args) => fromWebContentsMock(...args) },
}))
vi.mock('electron-log', () => ({ default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }))

const { setWindowRegistry } = await import('../../../src/main/security/ipcGuard')
const { AssetService } = await import('../../../src/main/services/assets')
const { AssetChannels } = await import('../../../src/common/contracts/assets')
const { ErrorCodes } = await import('../../../src/common/contracts/errors')

let sandbox
let workspaceRoot
let imageFolder
let docPath

const WINDOW_ID = 11
const event = () => ({ sender: {}, senderFrame: { parent: null } })
const invoke = (channel, payload) => handlers.get(channel)(event(), payload)

// 1x1 transparent png
const PNG_BYTES = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
)

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-asset-service-'))
  workspaceRoot = path.join(sandbox, 'workspace')
  imageFolder = path.join(sandbox, 'images')
  fs.mkdirSync(workspaceRoot, { recursive: true })
  fs.mkdirSync(imageFolder, { recursive: true })
  docPath = path.join(workspaceRoot, 'doc.md')
  fs.writeFileSync(docPath, '# doc\n')

  fromWebContentsMock.mockReturnValue({ id: WINDOW_ID })
  setWindowRegistry({ get: (id) => (id === WINDOW_ID ? { id } : undefined) })

  const windowManager = {
    get: (id) => (id === WINDOW_ID ? { openedRootDirectory: workspaceRoot, openedFiles: [docPath] } : undefined),
  }
  new AssetService(
    windowManager,
    { userDataPath: path.join(sandbox, 'userData') },
    { getItem: (key) => (key === 'imageFolderPath' ? imageFolder : undefined) },
  )
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

describe('AssetService.copyImageToFolder', () => {
  it('copies a referenced image with content-hash naming', async () => {
    const original = path.join(workspaceRoot, 'pic.png')
    fs.writeFileSync(original, PNG_BYTES)
    const result = await invoke(AssetChannels.copyImageToFolder, {
      docPathname: docPath,
      outputDir: imageFolder,
      imagePath: 'pic.png',
    })
    expect(result.ok).toBe(true)
    expect(fs.existsSync(result.value.pathname)).toBe(true)
    expect(path.dirname(result.value.pathname)).toBe(fs.realpathSync(imageFolder))
    expect(path.extname(result.value.pathname)).toBe('.png')
    // Original stays (copy, not move).
    expect(fs.existsSync(original)).toBe(true)
  })

  it('passes through non-image references unchanged', async () => {
    const result = await invoke(AssetChannels.copyImageToFolder, {
      docPathname: docPath,
      outputDir: imageFolder,
      imagePath: 'https-remote-or-not-an-image.txt',
    })
    expect(result.ok).toBe(true)
    expect(result.value.pathname).toBe('https-remote-or-not-an-image.txt')
  })

  it('writes pasted bytes with a deterministic content-hash name', async () => {
    const result = await invoke(AssetChannels.copyImageToFolder, {
      docPathname: docPath,
      outputDir: imageFolder,
      imageBytes: new Uint8Array(PNG_BYTES),
      imageName: '2026-07-16-shot.png',
    })
    expect(result.ok).toBe(true)
    expect(path.basename(result.value.pathname)).toMatch(/^[a-f0-9]{40}\.png$/)
    expect(fs.readFileSync(result.value.pathname).equals(PNG_BYTES)).toBe(true)

    const duplicate = await invoke(AssetChannels.copyImageToFolder, {
      docPathname: docPath,
      outputDir: imageFolder,
      imageBytes: new Uint8Array(PNG_BYTES),
      imageName: 'another-name.png',
    })
    expect(duplicate.value.pathname).toBe(result.value.pathname)
  })

  it('denies output directories outside the granted scope', async () => {
    const result = await invoke(AssetChannels.copyImageToFolder, {
      docPathname: docPath,
      outputDir: path.join(sandbox, 'elsewhere'),
      imageBytes: new Uint8Array(PNG_BYTES),
    })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.PATH_DENIED)
  })
})

describe('AssetService.moveToRelativeFolder', () => {
  it('moves the image and returns a doc-relative reference', async () => {
    const staged = path.join(imageFolder, 'staged.png')
    fs.writeFileSync(staged, PNG_BYTES)
    const result = await invoke(AssetChannels.moveToRelativeFolder, {
      cwd: workspaceRoot,
      relativeName: 'assets',
      docPathname: docPath,
      imagePath: staged,
    })
    expect(result.ok).toBe(true)
    expect(result.value.relativePath).toBe(path.join('assets', 'staged.png').replace(/\\/g, '/'))
    expect(fs.existsSync(path.join(workspaceRoot, 'assets/staged.png'))).toBe(true)
    expect(fs.existsSync(staged)).toBe(false)
  })

  it('rejects absolute relativeName', async () => {
    const result = await invoke(AssetChannels.moveToRelativeFolder, {
      cwd: workspaceRoot,
      relativeName: '/etc',
      docPathname: docPath,
      imagePath: path.join(imageFolder, 'nope.png'),
    })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.VALIDATION_FAILED)
  })
})

describe('AssetService.readImageForUpload', () => {
  it('returns image bytes and filename', async () => {
    const original = path.join(workspaceRoot, 'upload-me.png')
    fs.writeFileSync(original, PNG_BYTES)
    const result = await invoke(AssetChannels.readImageForUpload, {
      docPathname: docPath,
      imagePath: 'upload-me.png',
    })
    expect(result.ok).toBe(true)
    expect(result.value.filename).toBe('upload-me.png')
    expect(Buffer.from(result.value.bytes).equals(PNG_BYTES)).toBe(true)
  })

  it('enforces the size cap', async () => {
    const big = path.join(workspaceRoot, 'big.png')
    fs.writeFileSync(big, Buffer.alloc(2048, 1))
    const result = await invoke(AssetChannels.readImageForUpload, {
      docPathname: docPath,
      imagePath: 'big.png',
      maxBytes: 1024,
    })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.IO_ERROR)
  })

  it('rejects non-image references', async () => {
    const result = await invoke(AssetChannels.readImageForUpload, {
      docPathname: docPath,
      imagePath: 'doc.md',
    })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.VALIDATION_FAILED)
  })
})

describe('AssetService.uploadByCommand', () => {
  it('runs a user script uploader via execFile and returns its output', async () => {
    if (process.platform === 'win32') {
      return // shell script fixture is POSIX-only; covered on mac/linux CI
    }
    const script = path.join(sandbox, 'uploader.sh')
    fs.writeFileSync(script, '#!/bin/sh\necho "https://cdn.example.com/$(basename "$1")"\n')
    fs.chmodSync(script, 0o755)
    const image = path.join(workspaceRoot, 'tool-upload.png')
    fs.writeFileSync(image, PNG_BYTES)

    const result = await invoke(AssetChannels.uploadByCommand, {
      uploader: 'cliScript',
      cliScript: script,
      imagePath: image,
    })
    expect(result.ok).toBe(true)
    expect(result.value.url).toBe('https://cdn.example.com/tool-upload.png')
  })

  it('rejects non-executable uploader scripts', async () => {
    const script = path.join(sandbox, 'not-executable.sh')
    fs.writeFileSync(script, '#!/bin/sh\necho nope\n')
    fs.chmodSync(script, 0o644)
    const image = path.join(workspaceRoot, 'tool-upload2.png')
    fs.writeFileSync(image, PNG_BYTES)

    const result = await invoke(AssetChannels.uploadByCommand, {
      uploader: 'cliScript',
      cliScript: script,
      imagePath: image,
    })
    expect(result.ok).toBe(false)
    expect(result.error.code).toBe(ErrorCodes.PATH_DENIED)
  })

  it('cleans up temp files for bytes variants even on failure', async () => {
    const before = fs.readdirSync(os.tmpdir()).filter((f) => f.startsWith('vien-upload-')).length
    const result = await invoke(AssetChannels.uploadByCommand, {
      uploader: 'cliScript',
      cliScript: path.join(sandbox, 'missing-script'),
      imageBytes: new Uint8Array(PNG_BYTES),
    })
    expect(result.ok).toBe(false)
    const after = fs.readdirSync(os.tmpdir()).filter((f) => f.startsWith('vien-upload-')).length
    expect(after).toBe(before)
  })
})
