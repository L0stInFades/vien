/**
 * Renderer stub for Node.js 'fs'.
 *
 * PLAN.md Phase 0 contract: every call fails loudly with a structured
 * CapabilityUnavailableError — a stub must never fake success (empty reads,
 * no-op writes, "file does not exist" answers). Real filesystem access
 * belongs to main-process services (WorkspaceService / AssetService /
 * ExportService) reached over the preload capability API.
 *
 * `constants` stays as plain data: it is destructured at module load time
 * and carries no behavior.
 */
import { unavailableSync, unavailableAsync } from 'common/errors/capabilityUnavailable'

const CAPABILITY = 'filesystem'
const MIGRATION = 'a main-process service over IPC (PLAN.md WORKSPACE-001/ASSET-001/EXPORT-001)'

const sync = (api) => unavailableSync({ capability: CAPABILITY, api: `fs.${api}`, migration: MIGRATION })
const async = (api) => unavailableAsync({ capability: CAPABILITY, api: `fs.${api}`, migration: MIGRATION })

export const constants = {
  S_IXUSR: 0o100,
  S_IXGRP: 0o010,
  S_IXOTH: 0o001,
  O_RDONLY: 0,
  O_WRONLY: 1,
  O_RDWR: 2,
  O_CREAT: 512,
  O_EXCL: 2048,
  O_TRUNC: 1024,
  O_APPEND: 8,
  F_OK: 0,
  R_OK: 4,
  W_OK: 2,
  X_OK: 1,
}

export const statSync = sync('statSync')
export const lstatSync = sync('lstatSync')
export const readFileSync = sync('readFileSync')
export const writeFileSync = sync('writeFileSync')
export const existsSync = sync('existsSync')
export const readlinkSync = sync('readlinkSync')
export const mkdirSync = sync('mkdirSync')
export const readdirSync = sync('readdirSync')
export const unlinkSync = sync('unlinkSync')
export const renameSync = sync('renameSync')
export const copyFileSync = sync('copyFileSync')
export const accessSync = sync('accessSync')
export const chmodSync = sync('chmodSync')
export const createReadStream = sync('createReadStream')
export const createWriteStream = sync('createWriteStream')
export const stat = async('stat')
export const lstat = async('lstat')
export const readFile = async('readFile')
export const writeFile = async('writeFile')
export const mkdir = async('mkdir')
export const readdir = async('readdir')
export const unlink = async('unlink')
export const rename = async('rename')
export const copyFile = async('copyFile')
export const access = async('access')
export const chmod = async('chmod')
export const readlink = async('readlink')

const fsStub = {
  constants,
  statSync,
  lstatSync,
  readFileSync,
  writeFileSync,
  existsSync,
  readlinkSync,
  mkdirSync,
  readdirSync,
  unlinkSync,
  renameSync,
  copyFileSync,
  accessSync,
  chmodSync,
  createReadStream,
  createWriteStream,
  stat,
  lstat,
  readFile,
  writeFile,
  mkdir,
  readdir,
  unlink,
  rename,
  copyFile,
  access,
  chmod,
  readlink,
}
export default fsStub
