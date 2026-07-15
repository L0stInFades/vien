/**
 * Atomic save + DiskVersion CAS (PLAN.md SAFE-002 / SAFE-003).
 * Real filesystem; electron-log and the native ced module are mocked.
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, it, expect, vi, beforeAll, afterAll } from 'vitest'

vi.mock('electron-log', () => ({ default: { warn: vi.fn(), error: vi.fn(), info: vi.fn() } }))
vi.mock('ced', () => ({ default: () => 'utf8' }))

const { atomicWriteFile, getDiskVersion, isSameDiskVersion } = await import(
  '../../../src/main/filesystem/atomicWrite'
)
const { writeMarkdownFile, DiskVersionConflictError, loadMarkdownFile } = await import(
  '../../../src/main/filesystem/markdown'
)

let sandbox

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-atomic-save-'))
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

const listTempFiles = (dir) => fs.readdirSync(dir).filter((name) => name.includes('.vien-tmp'))

describe('atomicWriteFile (SAFE-002)', () => {
  it('replaces content and returns the new disk version', async () => {
    const target = path.join(sandbox, 'doc.md')
    fs.writeFileSync(target, 'old content')
    const version = await atomicWriteFile(target, Buffer.from('new content'))
    expect(fs.readFileSync(target, 'utf8')).toBe('new content')
    expect(version.size).toBe(Buffer.byteLength('new content'))
    expect(isSameDiskVersion(version, await getDiskVersion(target))).toBe(true)
  })

  it('creates missing parent directories', async () => {
    const target = path.join(sandbox, 'nested/deeper/doc.md')
    await atomicWriteFile(target, Buffer.from('content'))
    expect(fs.readFileSync(target, 'utf8')).toBe('content')
  })

  it('preserves the file mode of the replaced file', async () => {
    const target = path.join(sandbox, 'exec.md')
    fs.writeFileSync(target, 'x')
    fs.chmodSync(target, 0o600)
    await atomicWriteFile(target, Buffer.from('y'))
    expect(fs.statSync(target).mode & 0o777).toBe(0o600)
  })

  it('leaves the original untouched and cleans temp files on failure', async () => {
    const target = path.join(sandbox, 'protected/doc.md')
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.writeFileSync(target, 'precious')

    // Make the rename step fail: temp file is created in the directory,
    // but the target name is occupied by a DIRECTORY, so rename fails.
    const dirTarget = path.join(sandbox, 'protected/collision.md')
    fs.mkdirSync(dirTarget)
    await expect(atomicWriteFile(dirTarget, Buffer.from('data'))).rejects.toThrow()
    expect(listTempFiles(path.dirname(dirTarget))).toEqual([])
    expect(fs.readFileSync(target, 'utf8')).toBe('precious')
  })

  it('never leaves temp files behind on success', async () => {
    const target = path.join(sandbox, 'clean.md')
    await atomicWriteFile(target, Buffer.from('a'))
    await atomicWriteFile(target, Buffer.from('b'))
    expect(listTempFiles(sandbox)).toEqual([])
  })
})

const utf8Options = () => ({
  adjustLineEndingOnSave: false,
  lineEnding: 'lf',
  encoding: { encoding: 'utf8', isBom: false },
})

describe('writeMarkdownFile CAS (SAFE-003)', () => {
  it('writes and returns the new disk version without an expected version', async () => {
    const target = path.join(sandbox, 'cas-free.md')
    const version = await writeMarkdownFile(target, '# hello\n', utf8Options())
    expect(fs.readFileSync(target, 'utf8')).toBe('# hello\n')
    expect(version).toEqual(await getDiskVersion(target))
  })

  it('accepts a matching expected version', async () => {
    const target = path.join(sandbox, 'cas-match.md')
    const v1 = await writeMarkdownFile(target, 'rev 1\n', utf8Options())
    const v2 = await writeMarkdownFile(target, 'rev 2\n', utf8Options(), v1)
    expect(fs.readFileSync(target, 'utf8')).toBe('rev 2\n')
    expect(v2.size).toBe(6)
  })

  it('REFUSES to overwrite an externally modified file (the P0 guarantee)', async () => {
    const target = path.join(sandbox, 'cas-conflict.md')
    const v1 = await writeMarkdownFile(target, 'our version\n', utf8Options())

    // External editor rewrites the file (force a different mtime/size).
    fs.writeFileSync(target, 'external change with different length\n')
    const externalStat = fs.statSync(target)
    fs.utimesSync(target, externalStat.atime, new Date(externalStat.mtimeMs + 5000))

    let thrown = null
    try {
      await writeMarkdownFile(target, 'our newer content\n', utf8Options(), v1)
    } catch (error) {
      thrown = error
    }
    expect(thrown).toBeInstanceOf(DiskVersionConflictError)
    expect(thrown.code).toBe('E_CONFLICT')
    expect(thrown.actualDiskVersion).not.toBeNull()
    // The external content is untouched — no silent overwrite.
    expect(fs.readFileSync(target, 'utf8')).toBe('external change with different length\n')
  })

  it('applies CRLF conversion before writing', async () => {
    const target = path.join(sandbox, 'crlf.md')
    await writeMarkdownFile(target, 'line one\nline two\n', {
      adjustLineEndingOnSave: true,
      lineEnding: 'crlf',
      encoding: { encoding: 'utf8', isBom: false },
    })
    expect(fs.readFileSync(target, 'utf8')).toBe('line one\r\nline two\r\n')
  })

  it('writes a BOM when the document policy requires it', async () => {
    const target = path.join(sandbox, 'bom.md')
    await writeMarkdownFile(target, 'content\n', {
      adjustLineEndingOnSave: false,
      lineEnding: 'lf',
      encoding: { encoding: 'utf8', isBom: true },
    })
    const bytes = fs.readFileSync(target)
    expect(bytes[0]).toBe(0xef)
    expect(bytes[1]).toBe(0xbb)
    expect(bytes[2]).toBe(0xbf)
  })

  it('round-trips through loadMarkdownFile with a stable diskVersion', async () => {
    const target = path.join(sandbox, 'roundtrip.md')
    const savedVersion = await writeMarkdownFile(target, '# doc\n', utf8Options())
    const loaded = await loadMarkdownFile(target, 'lf', false)
    expect(loaded.markdown).toBe('# doc\n')
    expect(isSameDiskVersion(loaded.diskVersion, savedVersion)).toBe(true)
    // Saving again with the loaded version succeeds (no false conflicts).
    await writeMarkdownFile(target, '# doc v2\n', utf8Options(), loaded.diskVersion)
  })
})
