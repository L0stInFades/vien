/**
 * Pure request validation for the vien-asset:// protocol (BOUNDARY-002).
 * Kept electron-free so it can be unit tested directly.
 *
 * URL shape: vien-asset://local/<encodeURIComponent(absolutePath)>
 * Only image files are served — the protocol exists so document images can
 * load with webSecurity enabled, not as a general disk-read channel.
 */
import path from 'node:path'

export const ASSET_SCHEME = 'vien-asset'
export const ASSET_HOST = 'local'

const IMAGE_EXTENSIONS = new Set(['.jpeg', '.jpg', '.png', '.gif', '.svg', '.webp', '.bmp', '.ico', '.avif'])

/**
 * Validate and resolve a vien-asset request URL to an absolute image path.
 * Returns null for anything that must not be served.
 */
export const resolveAssetRequest = (requestUrl: string): string | null => {
  let parsed: URL
  try {
    parsed = new URL(requestUrl)
  } catch (_error) {
    return null
  }
  if (parsed.protocol !== `${ASSET_SCHEME}:` || parsed.hostname !== ASSET_HOST) {
    return null
  }

  let pathname = parsed.pathname
  if (pathname.startsWith('/')) {
    pathname = pathname.slice(1)
  }
  let decoded: string
  try {
    decoded = decodeURIComponent(pathname)
  } catch (_error) {
    return null
  }
  if (!decoded || decoded.includes('\0')) {
    return null
  }

  const normalized = path.normalize(decoded)
  if (!path.isAbsolute(normalized)) {
    return null
  }
  if (!IMAGE_EXTENSIONS.has(path.extname(normalized).toLowerCase())) {
    return null
  }
  return normalized
}
