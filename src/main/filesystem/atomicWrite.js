/**
 * Atomic file replacement (PLAN.md SAFE-002 / §5.3).
 *
 * Write path: temp file in the target directory ('wx', collision-safe name)
 * → write → fsync(file) → close → rename over target → fsync(directory,
 * POSIX). Any failure leaves the original file untouched and cleans up the
 * temp file. Never write user documents through plain fs.writeFile: a crash
 * mid-write must not leave a truncated document.
 */
import crypto from 'node:crypto'
import fsPromises from 'node:fs/promises'
import path from 'node:path'

/**
 * Current on-disk version marker used for compare-and-swap (SAFE-003).
 *
 * @param {string} pathname Absolute file path.
 * @returns {Promise<{mtimeMs: number, size: number} | null>} Version or null when missing.
 */
export const getDiskVersion = async (pathname) => {
  try {
    const stat = await fsPromises.stat(pathname)
    return { mtimeMs: stat.mtimeMs, size: stat.size }
  } catch (_error) {
    return null
  }
}

/**
 * Compare two disk versions.
 */
export const isSameDiskVersion = (a, b) => {
  if (!a || !b) {
    return false
  }
  return a.mtimeMs === b.mtimeMs && a.size === b.size
}

/**
 * Atomically replace `pathname` with `buffer`.
 *
 * @param {string} pathname Absolute target path.
 * @param {Buffer|Uint8Array} buffer Content to write.
 * @returns {Promise<{mtimeMs: number, size: number}>} The new disk version.
 */
export const atomicWriteFile = async (pathname, buffer) => {
  const dir = path.dirname(pathname)
  await fsPromises.mkdir(dir, { recursive: true })

  // Preserve the existing file mode when replacing.
  let mode
  try {
    mode = (await fsPromises.stat(pathname)).mode
  } catch (_error) {
    mode = undefined
  }

  const tempName = `.${path.basename(pathname)}.${process.pid}-${crypto.randomBytes(6).toString('hex')}.vien-tmp`
  const tempPath = path.join(dir, tempName)

  let handle = null
  try {
    handle = await fsPromises.open(tempPath, 'wx', mode)
    await handle.writeFile(buffer)
    // Flush file contents to disk before the rename makes them visible.
    await handle.sync()
    await handle.close()
    handle = null

    // Atomic on POSIX; on Windows libuv uses MoveFileEx(REPLACE_EXISTING).
    await fsPromises.rename(tempPath, pathname)

    // Flush the directory entry so the rename survives power loss (POSIX).
    if (process.platform !== 'win32') {
      let dirHandle = null
      try {
        dirHandle = await fsPromises.open(dir, 'r')
        await dirHandle.sync()
      } catch (_error) {
        // Directory fsync is best-effort (some filesystems refuse it).
      } finally {
        if (dirHandle) {
          await dirHandle.close().catch(() => {})
        }
      }
    }
  } catch (error) {
    if (handle) {
      await handle.close().catch(() => {})
    }
    await fsPromises.unlink(tempPath).catch(() => {})
    throw error
  }

  const version = await getDiskVersion(pathname)
  // Stat after our own rename cannot reasonably fail; guard anyway.
  if (!version) {
    throw new Error(`Failed to stat "${pathname}" after atomic write.`)
  }
  return version
}
