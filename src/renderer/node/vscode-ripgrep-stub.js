/**
 * Renderer stub for 'vscode-ripgrep'.
 *
 * `rgPath` must stay a plain string: RendererPaths dereferences it with
 * `.replace()` at module load time during bootstrap, so a throwing export
 * would crash startup. The empty path means any attempted spawn goes through
 * the child_process stub, which raises a structured
 * CapabilityUnavailableError (PLAN.md SEARCH-001 migrates search to a
 * main-process SearchService).
 */
export const rgPath = ''
export default { rgPath }
