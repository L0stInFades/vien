import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { captureMacScreenshot } from '../../../src/main/app/screenshot'

const temporaryDirectories = []

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

const destination = () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-screenshot-test-'))
  temporaryDirectories.push(directory)
  return path.join(directory, 'capture.png')
}

describe('captureMacScreenshot', () => {
  it('uses the system tool with argv and returns a non-empty capture', async () => {
    const target = destination()
    const runner = vi.fn((_file, _args, callback) => {
      fs.writeFileSync(target, Buffer.from([1, 2, 3]))
      callback(null)
    })

    await expect(captureMacScreenshot(target, runner)).resolves.toBe(target)
    expect(runner).toHaveBeenCalledWith('/usr/sbin/screencapture', ['-i', target], expect.any(Function))
  })

  it('treats Escape cancellation as a no-op', async () => {
    const runner = (_file, _args, callback) => callback(Object.assign(new Error('cancelled'), { code: 1 }))

    await expect(captureMacScreenshot(destination(), runner)).resolves.toBe('')
  })
})
