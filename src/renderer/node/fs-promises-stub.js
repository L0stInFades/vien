/**
 * Renderer stub for Node.js 'fs/promises'.
 *
 * PLAN.md Phase 0 contract: every call fails loudly with a structured
 * CapabilityUnavailableError instead of resolving with fake data.
 */
import { unavailableAsync } from 'common/errors/capabilityUnavailable'

const CAPABILITY = 'filesystem'
const MIGRATION = 'a main-process service over IPC (PLAN.md WORKSPACE-001/ASSET-001/EXPORT-001)'

const async = (api) => unavailableAsync({ capability: CAPABILITY, api: `fs/promises.${api}`, migration: MIGRATION })

export const access = async('access')
export const stat = async('stat')
export const lstat = async('lstat')
export const readFile = async('readFile')
export const writeFile = async('writeFile')
export const mkdir = async('mkdir')
export const readdir = async('readdir')
export const unlink = async('unlink')
export const rename = async('rename')
export const copyFile = async('copyFile')
export const chmod = async('chmod')
export const readlink = async('readlink')
export const rm = async('rm')
export const rmdir = async('rmdir')

const fsPromisesStub = {
  access,
  stat,
  lstat,
  readFile,
  writeFile,
  mkdir,
  readdir,
  unlink,
  rename,
  copyFile,
  chmod,
  readlink,
  rm,
  rmdir,
}
export default fsPromisesStub
