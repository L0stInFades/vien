// @vitest-environment node

import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { patchEnvPath } from '../../../src/main/app/envPath.ts'

const originalPlatform = process.platform
const originalPath = process.env.PATH

const setPlatform = (platform) => {
  Object.defineProperty(process, 'platform', { value: platform, configurable: true })
}

afterEach(() => {
  setPlatform(originalPlatform)
  process.env.PATH = originalPath
})

describe('macOS GUI PATH', () => {
  it('adds Intel/Apple Silicon Homebrew, system and TeX locations once', () => {
    setPlatform('darwin')
    process.env.PATH = '/usr/bin:/opt/homebrew/bin'

    patchEnvPath()
    patchEnvPath()

    const entries = process.env.PATH.split(path.delimiter)
    expect(entries).toEqual(
      expect.arrayContaining(['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', '/Library/TeX/texbin']),
    )
    expect(entries.filter((entry) => entry === '/opt/homebrew/bin')).toHaveLength(1)
  })

  it('does not modify non-macOS PATH values', () => {
    setPlatform('linux')
    process.env.PATH = '/custom/bin'
    patchEnvPath()
    expect(process.env.PATH).toBe('/custom/bin')
  })
})
