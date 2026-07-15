/**
 * Renderer file-system facade — every operation goes through main-process
 * capability services (PLAN.md WORKSPACE-001 / ASSET-001). No Node fs,
 * no child_process in the renderer.
 */
import path from 'node:path'
import dayjs from 'dayjs'
import { unwrapCapability } from '@/services/capability'

export const create = async (pathname: string, type: string): Promise<void> => {
  await unwrapCapability(window.api.workspace.create(pathname, type === 'directory' ? 'directory' : 'file'))
}

export const paste = async ({ src, dest, type }: { src: string; dest: string; type: string }): Promise<void> => {
  await unwrapCapability(window.api.workspace.paste(src, dest, type === 'cut' ? 'cut' : 'copy'))
}

export const rename = async (src: string, dest: string): Promise<void> => {
  await unwrapCapability(window.api.workspace.rename(src, dest))
}

const digestToHex = (digest: ArrayBuffer): string => {
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

export const getHash = async (
  content: string | ArrayBuffer | Uint8Array,
  type: AlgorithmIdentifier,
): Promise<string> => {
  const source =
    typeof content === 'string'
      ? new TextEncoder().encode(content)
      : content instanceof Uint8Array
        ? content
        : new Uint8Array(content)

  const digest = await globalThis.crypto.subtle.digest(type, source as BufferSource)
  return digestToHex(digest)
}

export const getContentHash = (content: string | ArrayBuffer | Uint8Array): Promise<string> => {
  return getHash(content, 'SHA-1')
}

export const moveToRelativeFolder = async (
  cwd: string,
  relativeName: string,
  filePath: string,
  imagePath: string,
): Promise<string> => {
  const { relativePath } = await unwrapCapability(
    window.api.assets.moveToRelativeFolder({
      cwd,
      relativeName: relativeName || '',
      docPathname: filePath,
      imagePath,
    }),
  )
  return relativePath
}

const readFileAsBytes = (file: File): Promise<Uint8Array> => {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(new Uint8Array(reader.result as ArrayBuffer))
    reader.onerror = () => reject(reader.error ?? new Error('Failed to read file.'))
    reader.readAsArrayBuffer(file)
  })
}

export const moveImageToFolder = async (pathname: string, image: string | File, outputDir: string): Promise<string> => {
  if (typeof image === 'string') {
    const { pathname: resultPath } = await unwrapCapability(
      window.api.assets.copyImageToFolder({
        docPathname: pathname,
        outputDir,
        imagePath: image,
      }),
    )
    return resultPath
  }

  const imageBytes = await readFileAsBytes(image)
  const imageName = `${dayjs().format('YYYY-MM-DD-HH-mm-ss')}-${image.name}`
  const { pathname: resultPath } = await unwrapCapability(
    window.api.assets.copyImageToFolder({
      docPathname: pathname,
      outputDir,
      imageBytes,
      imageName,
    }),
  )
  return resultPath
}

interface ImageBedGithub {
  owner: string
  repo: string
  branch: string
}

interface ImageBed {
  github: ImageBedGithub
}

interface UploadPreferences {
  currentUploader: string
  imageBed: ImageBed
  githubToken: string
  cliScript: string
}

interface GithubUploadResponse {
  content?: {
    download_url?: string | null
  }
}

const encodeGithubContentPath = (pathname: string): string => {
  return pathname.split('/').map(encodeURIComponent).join('/')
}

const arrayBufferToBase64 = (data: ArrayBuffer): string => {
  let binary = ''
  const bytes = new Uint8Array(data)
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

const MAX_UPLOAD_SIZE = 5 * 1024 * 1024

const uploadByGithub = async (content: string, filename: string, preferences: UploadPreferences): Promise<string> => {
  const { imageBed, githubToken: auth } = preferences
  const { owner, repo, branch } = imageBed.github
  if (!auth) {
    throw new Error('GitHub token is missing, the image will be copied to the image folder')
  }

  const ghPath = `${dayjs().format('YYYY/MM')}/${dayjs().format('DD-HH-mm-ss')}-${filename}`
  const message = `Upload by Vien at ${dayjs().format('YYYY-MM-DD HH:mm:ss')}`
  const payload: Record<string, string> = { message, content }
  if (branch) {
    payload.branch = branch
  }

  const response = await fetch(
    `https://api.github.com/repos/${owner}/${repo}/contents/${encodeGithubContentPath(ghPath)}`,
    {
      method: 'PUT',
      headers: {
        Accept: 'application/vnd.github+json',
        Authorization: `Bearer ${auth}`,
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
      body: JSON.stringify(payload),
    },
  )

  if (!response.ok) {
    throw new Error('Upload failed, the image will be copied to the image folder')
  }
  const result = (await response.json()) as GithubUploadResponse
  const downloadUrl = result.content?.download_url
  if (!downloadUrl) {
    throw new Error('Upload failed, the image will be copied to the image folder')
  }
  return downloadUrl
}

export const uploadImage = async (
  pathname: string,
  image: string | File,
  preferences: UploadPreferences,
): Promise<string> => {
  const { currentUploader, cliScript } = preferences
  if (currentUploader === 'none') {
    throw new Error('No image uploader provided.')
  }

  const isPath = typeof image === 'string'
  if (isPath) {
    if (currentUploader === 'picgo' || currentUploader === 'cliScript') {
      const imagePath = image.startsWith('/') || /^[a-zA-Z]:[\\/]/.test(image) ? image : undefined
      const resolved = imagePath ?? path.resolve(path.dirname(pathname), image)
      const { url } = await unwrapCapability(
        window.api.assets.uploadByCommand({
          uploader: currentUploader,
          cliScript: currentUploader === 'cliScript' ? cliScript : undefined,
          imagePath: resolved,
        }),
      )
      return url
    }
    if (currentUploader === 'github') {
      const { bytes, filename } = await unwrapCapability(
        window.api.assets.readImageForUpload({
          docPathname: pathname,
          imagePath: image,
          maxBytes: MAX_UPLOAD_SIZE,
        }),
      )
      const base64 = arrayBufferToBase64(bytes.buffer as ArrayBuffer)
      return uploadByGithub(base64, filename, preferences)
    }
    throw new Error('No image uploader provided.')
  }

  const { size } = image
  if (size > MAX_UPLOAD_SIZE) {
    throw new Error('Cannot upload more than 5M image, the image will be copied to the image folder')
  }

  if (currentUploader === 'picgo' || currentUploader === 'cliScript') {
    const imageBytes = await readFileAsBytes(image)
    const { url } = await unwrapCapability(
      window.api.assets.uploadByCommand({
        uploader: currentUploader,
        cliScript: currentUploader === 'cliScript' ? cliScript : undefined,
        imageBytes,
      }),
    )
    return url
  }

  const bytes = await readFileAsBytes(image)
  const base64 = arrayBufferToBase64(bytes.buffer as ArrayBuffer)
  return uploadByGithub(base64, image.name, preferences)
}

export const isFileExecutable = async (filepath: string): Promise<boolean> => {
  try {
    const { executable } = await unwrapCapability(window.api.workspace.isExecutable(filepath))
    return executable
  } catch (_err) {
    return false
  }
}
