import { execFile } from 'node:child_process'
import fs from 'node:fs/promises'

type ScreenshotRunner = (
  file: string,
  args: readonly string[],
  callback: (error: (Error & { code?: number | string }) | null) => void,
) => void

/** Run macOS' interactive region capture directly into a PNG file. */
export const captureMacScreenshot = (
  destination: string,
  runner: ScreenshotRunner = execFile as unknown as ScreenshotRunner,
): Promise<string> => {
  return new Promise((resolve, reject) => {
    runner('/usr/sbin/screencapture', ['-i', destination], (error) => {
      if (error) {
        // Escape cancels interactive capture and normally exits with code 1.
        if (error.code === 1 || error.code === '1') {
          resolve('')
        } else {
          reject(error)
        }
        return
      }

      fs.stat(destination)
        .then((stat) => resolve(stat.isFile() && stat.size > 0 ? destination : ''))
        .catch(() => resolve(''))
    })
  })
}
