const extensionForMime = (mime: string): string => {
  if (mime === 'image/jpeg') return 'jpg'
  if (mime === 'image/svg+xml') return 'svg'
  return mime.slice('image/'.length).replace(/[^a-zA-Z0-9]/g, '') || 'png'
}

/** Convert a base64 image data URL into the binary File used by image actions. */
export const dataURLToFile = (dataUrl: string): File | null => {
  const match = /^data:(image\/[a-zA-Z0-9.+-]+);base64,([a-zA-Z0-9+/=\s]+)$/s.exec(dataUrl)
  if (!match) return null

  try {
    const mime = match[1]
    const binary = atob(match[2].replace(/\s/g, ''))
    const bytes = new Uint8Array(binary.length)
    for (let index = 0; index < binary.length; index++) {
      bytes[index] = binary.charCodeAt(index)
    }
    return new File([bytes], `image.${extensionForMime(mime)}`, { type: mime })
  } catch (_error) {
    return null
  }
}
