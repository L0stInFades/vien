import path from 'node:path'

// Finder-launched applications do not inherit the user's login-shell PATH.
// Keep this list deterministic: it covers Apple Silicon and Intel Homebrew,
// the system toolchain, and MacTeX/Pandoc helpers used by import/export.
const MACOS_GUI_PATHS = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', '/Library/TeX/texbin']

export const patchEnvPath = (): void => {
  if (process.platform !== 'darwin') {
    return
  }

  const entries = (process.env.PATH ?? '').split(path.delimiter).filter(Boolean)
  for (const directory of MACOS_GUI_PATHS) {
    if (!entries.includes(directory)) {
      entries.push(directory)
    }
  }
  process.env.PATH = entries.join(path.delimiter)
}
