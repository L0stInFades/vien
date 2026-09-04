import { describe, expect, it } from 'vitest'
import { dataURLToFile } from '../../../src/renderer/util/dataURLToFile'

describe('dataURLToFile', () => {
  it('decodes a base64 image into a named File', async () => {
    const file = dataURLToFile('data:image/png;base64,AQIDBA==')

    expect(file).not.toBeNull()
    expect(file.name).toBe('image.png')
    expect(file.type).toBe('image/png')
    expect(Array.from(new Uint8Array(await file.arrayBuffer()))).toEqual([1, 2, 3, 4])
  })

  it('rejects non-image and malformed payloads', () => {
    expect(dataURLToFile('data:text/plain;base64,SGVsbG8=')).toBeNull()
    expect(dataURLToFile('data:image/png;base64,%%%')).toBeNull()
  })
})
