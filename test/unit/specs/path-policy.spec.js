/**
 * Path policy: workspace scoping and symlink-escape defense
 * (ADR-003 / PLAN.md Phase 1 exit criteria: malicious path and symlink
 * escape attempts must be rejected).
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import {
  normalizeRequestPath,
  isPathInside,
  assertPathInScope,
} from '../../../src/main/security/pathPolicy'
import { ServiceError, ErrorCodes } from '../../../src/common/contracts/errors'

let sandbox

beforeAll(() => {
  sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'vien-path-policy-'))
  fs.mkdirSync(path.join(sandbox, 'workspace/nested'), { recursive: true })
  fs.mkdirSync(path.join(sandbox, 'outside'), { recursive: true })
  fs.writeFileSync(path.join(sandbox, 'workspace/doc.md'), '# doc\n')
  fs.writeFileSync(path.join(sandbox, 'outside/secret.txt'), 'secret\n')
})

afterAll(() => {
  fs.rmSync(sandbox, { recursive: true, force: true })
})

const expectPathDenied = (fn) => {
  let thrown = null
  try {
    fn()
  } catch (error) {
    thrown = error
  }
  expect(thrown).toBeInstanceOf(ServiceError)
  expect(thrown.code).toBe(ErrorCodes.PATH_DENIED)
}

describe('normalizeRequestPath', () => {
  it('accepts absolute paths and normalizes traversal', () => {
    expect(normalizeRequestPath('/a/b/../c')).toBe(path.normalize('/a/c'))
  })

  it('rejects relative paths, empty strings and null bytes', () => {
    expectPathDenied(() => normalizeRequestPath('relative/x'))
    expectPathDenied(() => normalizeRequestPath(''))
    expectPathDenied(() => normalizeRequestPath('/a/\0b'))
    expectPathDenied(() => normalizeRequestPath(42))
  })
})

describe('isPathInside', () => {
  it('containment basics', () => {
    expect(isPathInside('/root/dir/file', '/root')).toBe(true)
    expect(isPathInside('/root', '/root')).toBe(true)
    expect(isPathInside('/rootother/file', '/root')).toBe(false)
    expect(isPathInside('/etc/passwd', '/root')).toBe(false)
  })
})

describe('assertPathInScope', () => {
  it('allows paths inside the opened root directory', () => {
    const root = path.join(sandbox, 'workspace')
    const target = path.join(root, 'nested/new-file.md')
    const resolved = assertPathInScope(target, { rootDirectory: root }, 'test')
    expect(isPathInside(resolved, fs.realpathSync(root))).toBe(true)
  })

  it('allows paths next to an opened file when no root is open', () => {
    const docPath = path.join(sandbox, 'workspace/doc.md')
    const sibling = path.join(sandbox, 'workspace/assets/img.png')
    const resolved = assertPathInScope(sibling, { openedFiles: [docPath] }, 'test')
    expect(resolved.endsWith(path.join('assets', 'img.png'))).toBe(true)
  })

  it('rejects paths outside every root', () => {
    const root = path.join(sandbox, 'workspace')
    expectPathDenied(() => assertPathInScope(path.join(sandbox, 'outside/secret.txt'), { rootDirectory: root }, 'test'))
  })

  it('rejects .. traversal that escapes the root', () => {
    const root = path.join(sandbox, 'workspace')
    expectPathDenied(() =>
      assertPathInScope(path.join(root, '../outside/secret.txt'), { rootDirectory: root }, 'test'),
    )
  })

  it('rejects when no scope is available at all', () => {
    expectPathDenied(() => assertPathInScope('/anywhere/file.md', {}, 'test'))
  })

  it('defeats symlink escapes out of the workspace', function () {
    const root = path.join(sandbox, 'workspace')
    const linkPath = path.join(root, 'sneaky-link')
    try {
      fs.symlinkSync(path.join(sandbox, 'outside'), linkPath, 'dir')
    } catch (_err) {
      return // symlink creation not permitted on this platform/runner — skip
    }
    // The naive normalized path LOOKS inside the root, but realpath reveals
    // it points outside — must be denied.
    expectPathDenied(() => assertPathInScope(path.join(linkPath, 'secret.txt'), { rootDirectory: root }, 'test'))
  })

  it('honors explicitly granted extra roots', () => {
    const extra = path.join(sandbox, 'outside')
    const resolved = assertPathInScope(path.join(extra, 'secret.txt'), { extraRoots: [extra] }, 'test')
    expect(resolved.endsWith('secret.txt')).toBe(true)
  })
})
