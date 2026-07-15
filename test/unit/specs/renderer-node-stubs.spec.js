/**
 * PLAN.md Phase 0 exit criterion: "所有 no-op stub 都有失败测试" — every
 * renderer Node stub must fail loudly with a structured
 * CapabilityUnavailableError instead of pretending success.
 *
 * If one of these tests fails, a stub regressed into a silent no-op:
 * UI would report success without any disk/process action.
 */
import { describe, it, expect } from 'vitest'
import {
  CapabilityUnavailableError,
  ERR_CAPABILITY_UNAVAILABLE,
  isCapabilityUnavailable,
} from 'common/errors/capabilityUnavailable'
import fsStub, * as fsNamed from '@/node/fs-browser-stub'
import fsExtraStub from '@/node/fs-extra-stub'
import fsPromisesStub from '@/node/fs-promises-stub'
import cpStub from '@/node/child-process-stub'
import zlibStub from '@/node/zlib-stub'

const expectSyncThrow = (fn, api) => {
  let thrown = null
  try {
    fn()
  } catch (error) {
    thrown = error
  }
  expect(thrown, `${api} must throw CapabilityUnavailableError`).toBeInstanceOf(CapabilityUnavailableError)
  expect(thrown.code).toBe(ERR_CAPABILITY_UNAVAILABLE)
  expect(isCapabilityUnavailable(thrown)).toBe(true)
}

const expectAsyncReject = async (fn, api) => {
  await expect(fn(), `${api} must reject with CapabilityUnavailableError`).rejects.toMatchObject({
    code: ERR_CAPABILITY_UNAVAILABLE,
  })
}

describe('renderer Node stubs fail loudly (no silent no-ops)', () => {
  it('fs sync APIs throw CapabilityUnavailableError', () => {
    const syncApis = [
      'statSync',
      'lstatSync',
      'readFileSync',
      'writeFileSync',
      'existsSync',
      'readlinkSync',
      'mkdirSync',
      'readdirSync',
      'unlinkSync',
      'renameSync',
      'copyFileSync',
      'accessSync',
      'chmodSync',
      'createReadStream',
      'createWriteStream',
    ]
    for (const api of syncApis) {
      expectSyncThrow(() => fsStub[api]('/tmp/x'), `fs.${api}`)
    }
  })

  it('fs async APIs reject with CapabilityUnavailableError', async () => {
    const asyncApis = ['stat', 'lstat', 'readFile', 'writeFile', 'mkdir', 'readdir', 'unlink', 'rename', 'copyFile']
    for (const api of asyncApis) {
      await expectAsyncReject(() => fsStub[api]('/tmp/x'), `fs.${api}`)
    }
  })

  it('fs async APIs also deliver the error to Node-style callbacks', async () => {
    let cbError = null
    const pending = fsStub.readFile('/tmp/x', (err) => {
      cbError = err
    })
    await pending.catch(() => {})
    expect(cbError).toBeInstanceOf(CapabilityUnavailableError)
  })

  it('fs.constants stays plain data (bootstrap-safe)', () => {
    expect(fsNamed.constants.F_OK).toBe(0)
    expect(typeof fsNamed.constants.S_IXUSR).toBe('number')
  })

  it('fs-extra APIs fail loudly', async () => {
    expectSyncThrow(() => fsExtraStub.existsSync('/tmp/x'), 'fs-extra.existsSync')
    expectSyncThrow(() => fsExtraStub.ensureDirSync('/tmp/x'), 'fs-extra.ensureDirSync')
    const asyncApis = ['ensureDir', 'outputFile', 'move', 'copy', 'readFile', 'writeFile', 'stat', 'remove']
    for (const api of asyncApis) {
      await expectAsyncReject(() => fsExtraStub[api]('/tmp/x', '/tmp/y'), `fs-extra.${api}`)
    }
  })

  it('fs/promises APIs reject', async () => {
    const asyncApis = ['access', 'stat', 'readFile', 'writeFile', 'mkdir', 'readdir', 'unlink', 'rename']
    for (const api of asyncApis) {
      await expectAsyncReject(() => fsPromisesStub[api]('/tmp/x'), `fs/promises.${api}`)
    }
  })

  it('child_process APIs fail loudly', async () => {
    expectSyncThrow(() => cpStub.spawn('rg', []), 'child_process.spawn')
    expectSyncThrow(() => cpStub.execSync('ls'), 'child_process.execSync')
    expectSyncThrow(() => cpStub.spawnSync('ls'), 'child_process.spawnSync')
    expectSyncThrow(() => cpStub.fork('mod'), 'child_process.fork')
    await expectAsyncReject(() => cpStub.exec('ls'), 'child_process.exec')
    await expectAsyncReject(() => cpStub.execFile('ls', []), 'child_process.execFile')
  })

  it('child_process.exec delivers the error to callbacks', async () => {
    let cbError = null
    const pending = cpStub.exec('picgo u "x"', (err) => {
      cbError = err
    })
    await pending.catch(() => {})
    expect(cbError).toBeInstanceOf(CapabilityUnavailableError)
  })

  it('zlib APIs fail loudly instead of returning identity data', () => {
    expectSyncThrow(() => zlibStub.deflateSync('data'), 'zlib.deflateSync')
    expectSyncThrow(() => zlibStub.gzipSync('data'), 'zlib.gzipSync')
  })

  it('error carries structured capability metadata', () => {
    try {
      fsExtraStub.existsSync('/tmp/x')
      expect.unreachable('existsSync must throw')
    } catch (error) {
      expect(error.capability).toBe('workspace.file-operations')
      expect(error.api).toBe('fs-extra.existsSync')
      expect(error.migration).toContain('WORKSPACE-001')
      expect(error.message).toContain('unavailable in the renderer')
    }
  })
})
