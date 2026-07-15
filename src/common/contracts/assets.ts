/**
 * AssetService contract (PLAN.md ASSET-001): image relocation and external
 * uploader tools. Binary payloads travel as Uint8Array (structured clone).
 */
import { s, type Infer } from './schema'

export const AssetChannels = {
  copyImageToFolder: 'mt::asset-copy-image-to-folder',
  moveToRelativeFolder: 'mt::asset-move-to-relative-folder',
  uploadByCommand: 'mt::asset-upload-by-command',
  uploaderAvailable: 'mt::asset-uploader-available',
  readImageForUpload: 'mt::asset-read-image-for-upload',
} as const

/** Check whether an uploader command is available on this machine. */
export const AssetUploaderAvailableRequestSchema = s.object({
  uploader: s.literal('picgo'),
})
export type AssetUploaderAvailableRequest = Infer<typeof AssetUploaderAvailableRequestSchema>

/**
 * Read image bytes for an upload flow (github uploader with a path
 * reference). Restricted to image extensions and size-capped main-side.
 */
export const AssetReadImageRequestSchema = s.object({
  docPathname: s.absolutePath(),
  imagePath: s.string({ minLength: 1, maxLength: 4096 }),
  maxBytes: s.optional(s.number({ integer: true, min: 1, max: 256 * 1024 * 1024 })),
})
export type AssetReadImageRequest = Infer<typeof AssetReadImageRequestSchema>

/**
 * Copy an image (referenced by path, or pasted bytes) into `outputDir`,
 * returning the resulting absolute path. Mirrors the legacy
 * renderer `moveImageToFolder`.
 */
export const AssetCopyImageRequestSchema = s.object({
  docPathname: s.absolutePath(),
  outputDir: s.absolutePath(),
  // Path variant: image reference relative to the document (or absolute).
  imagePath: s.optional(s.string({ minLength: 1, maxLength: 4096 })),
  // Bytes variant: pasted/dropped file content.
  imageBytes: s.optional(s.bytes({ maxBytes: 256 * 1024 * 1024 })),
  imageName: s.optional(s.string({ minLength: 1, maxLength: 512 })),
})
export type AssetCopyImageRequest = Infer<typeof AssetCopyImageRequestSchema>

/** Move an already-materialized image under the workspace-relative assets dir. */
export const AssetMoveRelativeRequestSchema = s.object({
  cwd: s.absolutePath(),
  relativeName: s.string({ minLength: 0, maxLength: 512 }),
  docPathname: s.absolutePath(),
  imagePath: s.absolutePath(),
})
export type AssetMoveRelativeRequest = Infer<typeof AssetMoveRelativeRequestSchema>

/** Run a configured external uploader (picgo or a user-selected script). */
export const AssetUploadByCommandRequestSchema = s.object({
  uploader: s.literal('picgo', 'cliScript'),
  cliScript: s.optional(s.absolutePath()),
  imagePath: s.optional(s.absolutePath()),
  imageBytes: s.optional(s.bytes({ maxBytes: 256 * 1024 * 1024 })),
})
export type AssetUploadByCommandRequest = Infer<typeof AssetUploadByCommandRequestSchema>
