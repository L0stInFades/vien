/**
 * WorkspaceService contract (PLAN.md WORKSPACE-001): file tree operations.
 * All paths are validated against the sender window's workspace scope by
 * main/security/pathPolicy — the schema only guarantees shape.
 */
import { s, type Infer } from './schema'

export const WorkspaceChannels = {
  create: 'mt::fs-create',
  paste: 'mt::fs-paste',
  rename: 'mt::fs-rename',
  isExecutable: 'mt::fs-is-executable',
} as const

export const FsCreateRequestSchema = s.object({
  pathname: s.absolutePath(),
  kind: s.literal('file', 'directory'),
})
export type FsCreateRequest = Infer<typeof FsCreateRequestSchema>

export const FsPasteRequestSchema = s.object({
  src: s.absolutePath(),
  dest: s.absolutePath(),
  kind: s.literal('copy', 'cut'),
})
export type FsPasteRequest = Infer<typeof FsPasteRequestSchema>

export const FsRenameRequestSchema = s.object({
  src: s.absolutePath(),
  dest: s.absolutePath(),
})
export type FsRenameRequest = Infer<typeof FsRenameRequestSchema>

export const FsIsExecutableRequestSchema = s.object({
  pathname: s.absolutePath(),
})
export type FsIsExecutableRequest = Infer<typeof FsIsExecutableRequestSchema>
