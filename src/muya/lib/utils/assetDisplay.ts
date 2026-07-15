/**
 * Display-boundary conversion of local file URLs to the controlled
 * vien-asset:// protocol (BOUNDARY-002).
 *
 * IMPORTANT: this conversion is for DOM `src` attributes ONLY. The document
 * model, markdown source and export pipeline keep their original paths —
 * vien-asset URLs must never be written into a document (see
 * contentState/imageCtrl.ts `correctImageSrc`, whose output lands in
 * block.text).
 */

const FILE_URL_REG = /^file:\/\//i

export const ASSET_DISPLAY_PREFIX = 'vien-asset://local/'

/** Convert a file:// URL to a vien-asset display URL; other URLs pass through. */
export const toDisplaySrc = (src: string): string => {
  if (typeof src !== 'string' || !FILE_URL_REG.test(src)) {
    return src
  }
  let pathname = src.replace(FILE_URL_REG, '')
  try {
    pathname = decodeURI(pathname)
  } catch (_error) {
    // keep the raw value; encodeURIComponent below still round-trips it
  }
  // file:///C:/... arrives as "/C:/..." — strip the leading slash on Windows drives.
  if (/^\/[a-zA-Z]:[\\/]/.test(pathname)) {
    pathname = pathname.slice(1)
  }
  return `${ASSET_DISPLAY_PREFIX}${encodeURIComponent(pathname)}`
}

/** True when a DOM src already points at the controlled asset protocol. */
export const isDisplayAssetSrc = (src: string): boolean => {
  return typeof src === 'string' && src.startsWith(ASSET_DISPLAY_PREFIX)
}
