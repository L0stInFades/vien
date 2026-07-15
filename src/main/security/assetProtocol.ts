/**
 * vien-asset:// protocol wiring (BOUNDARY-002, PLAN.md §5.7): serve local
 * document images through a controlled custom protocol so the renderer can
 * run with webSecurity enabled instead of disabling the same-origin policy.
 */
import fs from 'node:fs'
import { pathToFileURL } from 'node:url'
import { net, protocol } from 'electron'
import log from 'electron-log'
import { ASSET_SCHEME, resolveAssetRequest } from './assetRequest'

/** Must be called BEFORE app is ready. */
export const registerAssetSchemePrivileges = (): void => {
  protocol.registerSchemesAsPrivileged([
    {
      scheme: ASSET_SCHEME,
      privileges: {
        stream: true,
        supportFetchAPI: true,
      },
    },
  ])
}

/** Must be called once the app is ready. */
export const registerAssetProtocolHandler = (): void => {
  protocol.handle(ASSET_SCHEME, (request) => {
    const filePath = resolveAssetRequest(request.url)
    if (!filePath) {
      return new Response('Forbidden', { status: 403 })
    }
    let stat: fs.Stats
    try {
      stat = fs.statSync(filePath)
    } catch (_error) {
      return new Response('Not found', { status: 404 })
    }
    if (!stat.isFile()) {
      return new Response('Not found', { status: 404 })
    }
    // net.fetch on a file URL streams the file with correct mime headers.
    return net.fetch(pathToFileURL(filePath).toString()).catch((error) => {
      log.warn(`[assetProtocol] failed to serve ${filePath}: ${error.message}`)
      return new Response('Internal error', { status: 500 })
    })
  })
}
