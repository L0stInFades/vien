import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { isDangerousExecutableFile } from '../../../src/common/filesystem/paths'
import { requiresMacExecutableConfirmation } from '../../../src/main/security/localLink'

const temporaryDirectories = []

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    fs.rmSync(directory, { recursive: true, force: true })
  }
})

describe('macOS local-link execution guard', () => {
  it('flags app bundles, Terminal launchers, installers, and indirect links', () => {
    for (const name of ['Editor.app', 'run.command', 'task.tool', 'setup.pkg', 'profile.terminal', 'site.webloc']) {
      expect(isDangerousExecutableFile(name)).toBe(true)
    }
  })

  it('covers case, trailing separators, dots, and spaces', () => {
    expect(isDangerousExecutableFile('/Applications/Example.APP/')).toBe(true)
    expect(isDangerousExecutableFile('run.command.')).toBe(true)
    expect(isDangerousExecutableFile('run.command  ')).toBe(true)
  })

  it('does not flag ordinary documents and images', () => {
    for (const name of ['notes.md', 'photo.png', 'archive.zip', 'report.pdf', 'Makefile', '']) {
      expect(isDangerousExecutableFile(name)).toBe(false)
    }
  })

  it('detects extensionless executable files and safe-looking symlinks', async () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-link-guard-'))
    temporaryDirectories.push(directory)
    const executable = path.join(directory, 'runner')
    const alias = path.join(directory, 'notes.txt')
    fs.writeFileSync(executable, '#!/bin/sh\n')
    fs.chmodSync(executable, 0o755)
    fs.symlinkSync(executable, alias)

    await expect(requiresMacExecutableConfirmation(executable)).resolves.toBe(true)
    await expect(requiresMacExecutableConfirmation(alias)).resolves.toBe(true)
  })
})
