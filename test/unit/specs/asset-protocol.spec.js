/**
 * vien-asset protocol request validation + display URL conversion
 * (BOUNDARY-002): the controlled replacement for webSecurity: false.
 */
import path from 'node:path'
import { describe, it, expect } from 'vitest'
import { resolveAssetRequest, ASSET_SCHEME } from '../../../src/main/security/assetRequest'
import { toDisplaySrc, isDisplayAssetSrc } from '../../../src/muya/lib/utils/assetDisplay'

const enc = encodeURIComponent

describe('resolveAssetRequest', () => {
  it('resolves valid absolute image paths', () => {
    expect(resolveAssetRequest(`vien-asset://local/${enc('/Users/me/pics/photo.png')}`)).toBe(
      path.normalize('/Users/me/pics/photo.png'),
    )
    expect(resolveAssetRequest(`vien-asset://local/${enc('/a/b/c.webp')}`)).toBe(path.normalize('/a/b/c.webp'))
  })

  it('accepts query strings (cache busting) without affecting the path', () => {
    expect(resolveAssetRequest(`vien-asset://local/${enc('/x/y.png')}?msec=12345`)).toBe(path.normalize('/x/y.png'))
  })

  it('rejects non-image extensions', () => {
    expect(resolveAssetRequest(`vien-asset://local/${enc('/etc/passwd')}`)).toBeNull()
    expect(resolveAssetRequest(`vien-asset://local/${enc('/home/me/.ssh/id_rsa')}`)).toBeNull()
    expect(resolveAssetRequest(`vien-asset://local/${enc('/x/script.js')}`)).toBeNull()
    expect(resolveAssetRequest(`vien-asset://local/${enc('/x/doc.md')}`)).toBeNull()
  })

  it('rejects wrong scheme, host, or malformed URLs', () => {
    expect(resolveAssetRequest(`file://local/${enc('/x/y.png')}`)).toBeNull()
    expect(resolveAssetRequest(`vien-asset://remote/${enc('/x/y.png')}`)).toBeNull()
    expect(resolveAssetRequest('not a url')).toBeNull()
    expect(resolveAssetRequest('vien-asset://local/')).toBeNull()
  })

  it('rejects relative paths and null bytes', () => {
    expect(resolveAssetRequest(`vien-asset://local/${enc('relative/pic.png')}`)).toBeNull()
    expect(resolveAssetRequest(`vien-asset://local/${enc('/x/\0y.png')}`)).toBeNull()
  })

  it('normalizes .. traversal inside the path (still image-only)', () => {
    // Traversal is normalized; the result is still an absolute image path.
    // The protocol serves images only — it is a display channel, not a
    // general read primitive.
    expect(resolveAssetRequest(`vien-asset://local/${enc('/a/b/../c.png')}`)).toBe(path.normalize('/a/c.png'))
  })

  it('exposes the expected scheme constant', () => {
    expect(ASSET_SCHEME).toBe('vien-asset')
  })
})

describe('toDisplaySrc', () => {
  it('converts file URLs to vien-asset display URLs', () => {
    expect(toDisplaySrc('file:///Users/me/photo.png')).toBe(`vien-asset://local/${enc('/Users/me/photo.png')}`)
  })

  it('handles Windows drive letter file URLs', () => {
    expect(toDisplaySrc('file:///C:/pics/photo.png')).toBe(`vien-asset://local/${enc('C:/pics/photo.png')}`)
  })

  it('decodes percent-encoded file URLs before re-encoding', () => {
    expect(toDisplaySrc('file:///Users/me/my%20pics/photo.png')).toBe(
      `vien-asset://local/${enc('/Users/me/my pics/photo.png')}`,
    )
  })

  it('passes through non-file URLs unchanged', () => {
    expect(toDisplaySrc('https://example.com/x.png')).toBe('https://example.com/x.png')
    expect(toDisplaySrc('data:image/png;base64,AAA')).toBe('data:image/png;base64,AAA')
    expect(toDisplaySrc('./relative.png')).toBe('./relative.png')
  })

  it('round-trips through resolveAssetRequest', () => {
    const display = toDisplaySrc('file:///Users/me/中文 图片.png')
    expect(isDisplayAssetSrc(display)).toBe(true)
    expect(resolveAssetRequest(display)).toBe(path.normalize('/Users/me/中文 图片.png'))
  })
})
