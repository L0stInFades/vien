/**
 * AssetService (PLAN.md ASSET-001): image relocation and external uploader
 * tools, owned by the main process.
 *
 * Path policy: destinations are scoped to the sender's workspace plus the
 * explicitly configured image folder and the app's userData directory.
 * Source image paths are user-driven references from the document (images
 * can legitimately live anywhere on disk) — read access is an accepted
 * Phase 1 risk documented in docs/capability-inventory.md; destination
 * writes are always scoped.
 *
 * Uploaders run via execFile (no shell) — the legacy renderer used
 * cp.exec with string interpolation, which was shell-injectable.
 */
import { execFile } from 'node:child_process'
import os from 'node:os'
import path from 'node:path'
import crypto from 'node:crypto'
import fs from 'fs-extra'
import commandExists from 'command-exists'
import { ErrorCodes, ServiceError } from 'common/contracts'
import {
  AssetChannels,
  AssetCopyImageRequestSchema,
  AssetMoveRelativeRequestSchema,
  AssetReadImageRequestSchema,
  AssetUploadByCommandRequestSchema,
  AssetUploaderAvailableRequestSchema,
} from 'common/contracts/assets'
import { handleCapability } from '../../security/ipcGuard'
import {
  assertPathInScope,
  normalizeRequestPath,
  resolveRealParent,
  type WorkspaceScope,
} from '../../security/pathPolicy'

const IMAGE_EXTENSIONS = ['.jpeg', '.jpg', '.png', '.gif', '.svg', '.webp']
const UPLOAD_TIMEOUT_MS = 60_000

interface EditorWindowLike {
  openedRootDirectory?: string | null
  openedFiles?: readonly string[]
}

interface WindowManagerLike {
  get(windowId: number): EditorWindowLike | undefined
}

interface AssetServicePaths {
  userDataPath: string
}

interface DataCenterLike {
  getItem(key: string): unknown
}

const isImagePath = (filepath: string): boolean => {
  return IMAGE_EXTENSIONS.includes(path.extname(filepath).toLowerCase())
}

const sha1 = (data: Buffer | Uint8Array): string => {
  return crypto.createHash('sha1').update(data).digest('hex')
}

export class AssetService {
  private readonly _windowManager: WindowManagerLike
  private readonly _paths: AssetServicePaths
  private readonly _dataCenter: DataCenterLike | null

  constructor(windowManager: WindowManagerLike, paths: AssetServicePaths, dataCenter: DataCenterLike | null = null) {
    this._windowManager = windowManager
    this._paths = paths
    this._dataCenter = dataCenter
    this._registerHandlers()
  }

  private _scopeFor(windowId: number): WorkspaceScope {
    const window = this._windowManager.get(windowId)
    const extraRoots: string[] = [this._paths.userDataPath]
    const imageFolder = this._dataCenter?.getItem('imageFolderPath')
    if (typeof imageFolder === 'string' && imageFolder.length > 0) {
      extraRoots.push(imageFolder)
    }
    return {
      rootDirectory: window?.openedRootDirectory ?? null,
      openedFiles: window?.openedFiles ?? [],
      extraRoots,
    }
  }

  private _registerHandlers(): void {
    /**
     * Copy an image into `outputDir` and return its new absolute path.
     * Mirrors the legacy renderer `moveImageToFolder`:
     * - path variant: content-hash naming, no-op when already in place;
     * - bytes variant: content-hash naming for deterministic deduplication.
     */
    handleCapability(AssetChannels.copyImageToFolder, AssetCopyImageRequestSchema, async (request, context) => {
      const scope = this._scopeFor(context.windowId)
      const outputDir = assertPathInScope(request.outputDir, scope, 'image output directory')
      await fs.ensureDir(outputDir)

      if (request.imagePath !== undefined) {
        const docDir = path.dirname(normalizeRequestPath(request.docPathname))
        const imagePath = path.resolve(docDir, request.imagePath)
        if (!isImagePath(imagePath) || !(await fs.pathExists(imagePath))) {
          // Not a local image reference — return unchanged (legacy behavior).
          return { pathname: request.imagePath }
        }
        const extname = path.extname(imagePath)
        const noHashPath = path.join(outputDir, path.basename(imagePath))
        if (noHashPath === imagePath) {
          return { pathname: imagePath }
        }
        const imageBuffer = await fs.readFile(imagePath)
        const hashFilePath = path.join(outputDir, `${sha1(imageBuffer)}${extname}`)
        await fs.copy(imagePath, hashFilePath)
        return { pathname: hashFilePath }
      }

      if (request.imageBytes !== undefined) {
        const requestedExtension = path.extname(request.imageName ?? '').toLowerCase()
        const extension = IMAGE_EXTENSIONS.includes(requestedExtension) ? requestedExtension : '.png'
        const imagePath = path.join(outputDir, `${sha1(request.imageBytes)}${extension}`)
        await fs.writeFile(imagePath, Buffer.from(request.imageBytes))
        return { pathname: imagePath }
      }

      throw new ServiceError(ErrorCodes.VALIDATION_FAILED, 'Either imagePath or imageBytes is required.')
    })

    /**
     * Move an image under `cwd/relativeName` and return the reference path
     * relative to the document. Mirrors legacy `moveToRelativeFolder`.
     */
    handleCapability(AssetChannels.moveToRelativeFolder, AssetMoveRelativeRequestSchema, async (request, context) => {
      const scope = this._scopeFor(context.windowId)
      const relativeName = request.relativeName || 'assets'
      if (path.isAbsolute(relativeName)) {
        throw new ServiceError(ErrorCodes.VALIDATION_FAILED, 'Invalid relative directory name.')
      }
      const cwd = assertPathInScope(request.cwd, scope, 'relative folder base')
      const imagePath = assertPathInScope(request.imagePath, scope, 'image source')
      const docPathname = resolveRealParent(normalizeRequestPath(request.docPathname))

      const absDir = assertPathInScope(path.resolve(cwd, relativeName), scope, 'relative folder')
      const dstPath = path.resolve(absDir, path.basename(imagePath))
      await fs.ensureDir(absDir)
      await fs.move(imagePath, dstPath, { overwrite: true })

      let dstRelPath = path.relative(path.dirname(docPathname), dstPath)
      if (process.platform === 'win32') {
        dstRelPath = dstRelPath.replace(/\\/g, '/')
      }
      return { relativePath: dstRelPath, pathname: dstPath }
    })

    /**
     * Run a configured uploader tool. picgo resolves via PATH; custom
     * scripts must be executable files the user configured. Bytes variants
     * are written to a temp file that is always cleaned up.
     */
    handleCapability(AssetChannels.uploadByCommand, AssetUploadByCommandRequestSchema, async (request) => {
      let imagePath: string
      let isTempFile = false
      if (request.imageBytes !== undefined) {
        imagePath = path.join(os.tmpdir(), `vien-upload-${Date.now()}-${sha1(request.imageBytes).slice(0, 8)}`)
        await fs.writeFile(imagePath, Buffer.from(request.imageBytes))
        isTempFile = true
      } else if (request.imagePath !== undefined) {
        imagePath = normalizeRequestPath(request.imagePath)
        if (!(await fs.pathExists(imagePath))) {
          throw new ServiceError(ErrorCodes.NOT_FOUND, `Image not found: ${imagePath}`)
        }
      } else {
        throw new ServiceError(ErrorCodes.VALIDATION_FAILED, 'Either imagePath or imageBytes is required.')
      }

      try {
        if (request.uploader === 'picgo') {
          const output = await this._execUploader('picgo', ['u', imagePath])
          const parts = output.split('[PicGo SUCCESS]:')
          if (parts.length === 2) {
            return { url: parts[1].trim() }
          }
          throw new ServiceError(ErrorCodes.IO_ERROR, 'PicGo upload error')
        }

        const script = request.cliScript ? normalizeRequestPath(request.cliScript) : null
        if (!script) {
          throw new ServiceError(ErrorCodes.VALIDATION_FAILED, 'cliScript path is required for the script uploader.')
        }
        const stat = await fs.stat(script).catch(() => null)
        if (!stat || !stat.isFile() || (stat.mode & 0o111) === 0) {
          throw new ServiceError(ErrorCodes.PATH_DENIED, 'Configured uploader script is not an executable file.')
        }
        const output = await this._execUploader(script, [imagePath])
        return { url: output.trim() }
      } finally {
        if (isTempFile) {
          await fs.unlink(imagePath).catch(() => {})
        }
      }
    })

    handleCapability(AssetChannels.uploaderAvailable, AssetUploaderAvailableRequestSchema, async (request) => {
      try {
        await commandExists(request.uploader)
        return { available: true }
      } catch (_error) {
        return { available: false }
      }
    })

    /**
     * Image bytes for upload flows (github uploader, path variant). Same
     * user-driven source-read policy as copyImageToFolder; image extensions
     * only; size capped.
     */
    handleCapability(AssetChannels.readImageForUpload, AssetReadImageRequestSchema, async (request) => {
      const docDir = path.dirname(normalizeRequestPath(request.docPathname))
      const imagePath = path.resolve(docDir, request.imagePath)
      if (!isImagePath(imagePath)) {
        throw new ServiceError(ErrorCodes.VALIDATION_FAILED, 'Not an image file reference.')
      }
      const stat = await fs.stat(imagePath).catch(() => null)
      if (!stat || !stat.isFile()) {
        throw new ServiceError(ErrorCodes.NOT_FOUND, `Image not found: ${imagePath}`)
      }
      const maxBytes = request.maxBytes ?? 5 * 1024 * 1024
      if (stat.size > maxBytes) {
        throw new ServiceError(ErrorCodes.IO_ERROR, `Image larger than ${maxBytes} bytes.`)
      }
      const bytes = await fs.readFile(imagePath)
      return { bytes: new Uint8Array(bytes), filename: path.basename(imagePath) }
    })
  }

  private _execUploader(file: string, args: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      execFile(file, args, { timeout: UPLOAD_TIMEOUT_MS, windowsHide: true }, (error, stdout) => {
        if (error) {
          reject(new ServiceError(ErrorCodes.IO_ERROR, `Uploader failed: ${error.message}`))
          return
        }
        resolve(String(stdout))
      })
    })
  }
}
