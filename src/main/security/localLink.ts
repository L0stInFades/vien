import fs from 'node:fs/promises'
import { isDangerousExecutableFile } from 'common/filesystem/paths'

/**
 * Check both the visible path and its real target. Executable permission bits
 * cover extensionless scripts/binaries; realpath closes a symlink-name bypass.
 */
export const requiresMacExecutableConfirmation = async (pathname: string): Promise<boolean> => {
  if (isDangerousExecutableFile(pathname)) return true

  try {
    const target = await fs.realpath(pathname)
    if (isDangerousExecutableFile(target)) return true
    const stat = await fs.stat(target)
    return stat.isFile() && (stat.mode & 0o111) !== 0
  } catch (_error) {
    return false
  }
}
