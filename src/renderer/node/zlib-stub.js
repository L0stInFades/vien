/**
 * Renderer stub for Node.js 'zlib'.
 *
 * PLAN.md Phase 0 contract: the previous identity implementation silently
 * produced corrupt PlantUML URLs (uncompressed bytes labelled as deflate).
 * Every call now fails loudly with a structured CapabilityUnavailableError.
 * PlantUML rendering must become an explicit opt-in remote capability or use
 * a browser-native compressor (PLAN.md §5.7 — remote diagram policy).
 */
import { unavailableSync, unavailableAsync } from 'common/errors/capabilityUnavailable'

const CAPABILITY = 'compression'
const MIGRATION = 'a browser-native compressor or explicit remote-diagram policy (PLAN.md §5.7)'

const sync = (api) => unavailableSync({ capability: CAPABILITY, api: `zlib.${api}`, migration: MIGRATION })
const async = (api) => unavailableAsync({ capability: CAPABILITY, api: `zlib.${api}`, migration: MIGRATION })

export const deflateSync = sync('deflateSync')
export const inflateSync = sync('inflateSync')
export const gzipSync = sync('gzipSync')
export const gunzipSync = sync('gunzipSync')
export const brotliCompressSync = sync('brotliCompressSync')
export const brotliDecompressSync = sync('brotliDecompressSync')
export const deflate = async('deflate')
export const inflate = async('inflate')
export const gzip = async('gzip')
export const gunzip = async('gunzip')
export const createDeflate = sync('createDeflate')
export const createGzip = sync('createGzip')
export const constants = { Z_DEFAULT_COMPRESSION: -1, Z_BEST_COMPRESSION: 9, Z_BEST_SPEED: 1 }

const zlibStub = {
  deflateSync,
  inflateSync,
  gzipSync,
  gunzipSync,
  brotliCompressSync,
  brotliDecompressSync,
  deflate,
  inflate,
  gzip,
  gunzip,
  createDeflate,
  createGzip,
  constants,
}
export default zlibStub
