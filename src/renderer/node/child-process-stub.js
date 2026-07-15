/**
 * Renderer stub for Node.js 'child_process'.
 *
 * PLAN.md Phase 0 contract: spawning processes from the renderer is a
 * privilege violation — every call fails loudly with a structured
 * CapabilityUnavailableError. Search (ripgrep) and external tools belong to
 * main-process services (PLAN.md SEARCH-001 / ShellService).
 */
import { unavailableSync, unavailableAsync } from 'common/errors/capabilityUnavailable'

const CAPABILITY = 'process.spawn'
const MIGRATION = 'SearchService/ShellService over IPC (PLAN.md SEARCH-001)'

const sync = (api) => unavailableSync({ capability: CAPABILITY, api: `child_process.${api}`, migration: MIGRATION })
const async = (api) => unavailableAsync({ capability: CAPABILITY, api: `child_process.${api}`, migration: MIGRATION })

export const spawn = sync('spawn')
export const exec = async('exec')
export const execFile = async('execFile')
export const fork = sync('fork')
export const execSync = sync('execSync')
export const spawnSync = sync('spawnSync')

const cp = { spawn, exec, execFile, fork, execSync, spawnSync }
export default cp
