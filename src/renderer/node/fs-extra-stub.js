/**
 * Renderer stub for 'fs-extra'.
 *
 * PLAN.md Phase 0 contract: every call fails loudly with a structured
 * CapabilityUnavailableError. File create/copy/move/delete belongs to the
 * main-process WorkspaceService/AssetService (PLAN.md WORKSPACE-001 /
 * ASSET-001), not to the renderer.
 */
import { unavailableSync, unavailableAsync } from 'common/errors/capabilityUnavailable'

const CAPABILITY = 'workspace.file-operations'
const MIGRATION = 'WorkspaceService/AssetService over IPC (PLAN.md WORKSPACE-001/ASSET-001)'

const sync = (api) => unavailableSync({ capability: CAPABILITY, api: `fs-extra.${api}`, migration: MIGRATION })
const async = (api) => unavailableAsync({ capability: CAPABILITY, api: `fs-extra.${api}`, migration: MIGRATION })

export const ensureDir = async('ensureDir')
export const ensureDirSync = sync('ensureDirSync')
export const outputFile = async('outputFile')
export const move = async('move')
export const copy = async('copy')
export const writeFile = async('writeFile')
export const readFile = async('readFile')
export const unlink = async('unlink')
export const stat = async('stat')
export const lstat = async('lstat')
export const existsSync = sync('existsSync')
export const lstatSync = sync('lstatSync')
export const readlinkSync = sync('readlinkSync')
export const outputJson = async('outputJson')
export const readJson = async('readJson')
export const writeJson = async('writeJson')
export const remove = async('remove')
export const emptyDir = async('emptyDir')
export const mkdirs = async('mkdirs')
export const mkdirsSync = sync('mkdirsSync')

const fsExtra = {
  ensureDir,
  ensureDirSync,
  outputFile,
  move,
  copy,
  writeFile,
  readFile,
  unlink,
  stat,
  lstat,
  existsSync,
  lstatSync,
  readlinkSync,
  outputJson,
  readJson,
  writeJson,
  remove,
  emptyDir,
  mkdirs,
  mkdirsSync,
}
export default fsExtra
