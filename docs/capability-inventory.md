# Renderer Node Capability Inventory (PLAN.md BASE-002)

> Status: living document — update whenever a capability migrates.
> Established: 2026-07-16 (Phase 0). Owner: desktop platform workstream.

The renderer runs with `contextIsolation: true` / `nodeIntegration: false`.
[`electron.vite.config.ts`](../electron.vite.config.ts) aliases Node built-ins
to stubs under [`src/renderer/node/`](../src/renderer/node/). Since Phase 0,
**every stub call raises a structured `CapabilityUnavailableError`**
([`src/common/errors/capabilityUnavailable.ts`](../src/common/errors/capabilityUnavailable.ts))
instead of faking success. This table maps each consumer to the main-process
service that must own the capability.

## Stub modules

| Stub | Replaces | Behavior since Phase 0 |
| --- | --- | --- |
| `fs-browser-stub.js` | `fs`, `node:fs` | throws `CapabilityUnavailableError` (constants stay as data) |
| `fs-promises-stub.js` | `fs/promises` | rejects with `CapabilityUnavailableError` |
| `fs-extra-stub.js` | `fs-extra` | throws/rejects with `CapabilityUnavailableError` |
| `child-process-stub.js` | `child_process` | throws/rejects with `CapabilityUnavailableError` |
| `zlib-stub.js` | `zlib` | throws (previous identity impl silently corrupted PlantUML URLs) |
| `vscode-ripgrep-stub.js` | `vscode-ripgrep` | `rgPath = ''` stays a string (bootstrap dereferences it at module load); spawn attempts fail via `child_process` stub |
| `electron-log-renderer.js` | `electron-log` | real console adapter, not a fake — keep |

## Consumers and owning services

| Renderer call site | Stubbed APIs | Capability | Owning service (PLAN.md) | Status |
| --- | --- | --- | --- | --- |
| `src/renderer/util/fileSystem.ts` `create/paste/rename` | `fs-extra.ensureDir/outputFile/move/copy` | workspace file operations | `WorkspaceService` (WORKSPACE-001) | ✅ migrated — `window.api.workspace.*` (`mt::fs-create/paste/rename`), guarded + path-scoped |
| `src/renderer/util/fileSystem.ts` `moveToRelativeFolder/moveImageToFolder` | `fs-extra.ensureDir/move/copy/readFile/writeFile` | image relocation | `AssetService` (ASSET-001) | ✅ migrated — `window.api.assets.*` (`mt::asset-*`), destination-scoped |
| `src/renderer/util/fileSystem.ts` `uploadImage` (picgo/cli path) | `child_process.exec/execFile`, `fs-extra.writeFile/unlink/stat` | external uploader tools | `AssetService` upload adapters (ASSET-001) | ✅ migrated — main-side execFile (no shell), github uploader stays fetch-based via `readImageForUpload` |
| `src/renderer/util/fileSystem.ts` `isFileExecutableSync` | `fs.statSync` | executable validation for custom tools | `ShellService` policy check | ✅ migrated — async `mt::fs-is-executable` |
| `src/renderer/util/pdf.ts` custom export theme | `fs.readFileSync`, `common/filesystem.isFile` | export theme read | `ExportService` (EXPORT-001) | ✅ migrated — `mt::fs-read-export-theme` (getCssForOptions is async now) |
| `src/renderer/components/exportSettings/index.vue` theme enumeration | `fs/promises.readdir`, `fs.existsSync` | export theme listing | `ExportService` (EXPORT-001) | ✅ migrated — `mt::fs-list-export-themes` |
| `src/renderer/components/sideBar/search.vue` → `node/ripgrepSearcher.js` | `child_process.spawn` + `vscode-ripgrep.rgPath` | workspace content search | `SearchService` (SEARCH-001) | ⛔ spawn throws → structured search failure |
| `src/renderer/commands/quickOpen.js` → `node/fileSearcher.js` | `child_process.spawn` + `vscode-ripgrep.rgPath` | file listing for quick open | `SearchService` (SEARCH-001) | ⛔ spawn throws → structured search failure |
| `src/muya/lib/parser/render/plantuml.ts` | `zlib.deflateSync` | PlantUML encoding for remote render | browser-native `CompressionStream` + explicit remote opt-in (§5.7) | ⛔ throws (previously produced silently corrupt URLs) |
| `src/common/filesystem/index.ts` + `paths.ts` (shared with main) | `fs.existsSync/lstatSync/...` | path validation helpers | renderer callers must switch to service answers; main keeps real fs | ⚠️ renderer calls return `false` via try/catch — audit call sites during WORKSPACE-001 |

## Rules

1. New renderer code must not import `fs`, `fs/promises`, `fs-extra`,
   `child_process`, `zlib`, `electron`, or `vscode-ripgrep`. Reach the
   capability through `window.api` instead.
2. A stub may only be deleted when its Vite alias is deleted too — at that
   point any remaining import becomes a build failure, which is the desired
   end state (PLAN.md Phase 1 exit criteria).
3. Every migration must land with a real-filesystem Electron E2E test.
