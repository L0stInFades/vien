/**
 * Guarded IPC handler registration for capability services (ADR-003).
 *
 * Every capability channel registered through here gets, in order:
 *   1. sender frame check — only top-level frames may call capabilities;
 *   2. sender window check — the WebContents must belong to a window the
 *      application actually tracks (no devtools/webview/ghost senders);
 *   3. runtime payload validation against the contract schema;
 *   4. structured ServiceResult envelope — handlers can throw ServiceError
 *      (or anything; it is normalized), the renderer never sees a bare
 *      exception or a success-shaped failure.
 */
import { BrowserWindow, ipcMain } from 'electron'
import type { IpcMainInvokeEvent, WebContents } from 'electron'
import log from 'electron-log'
import {
  ErrorCodes,
  ServiceError,
  formatIssues,
  serviceErr,
  serviceOk,
  type Schema,
  type ServiceResult,
} from 'common/contracts'

export interface WindowRegistry {
  /** Returns a truthy window record when the BrowserWindow id is tracked. */
  get(windowId: number): unknown
}

export interface GuardedContext {
  event: IpcMainInvokeEvent
  browserWindow: BrowserWindow
  windowId: number
}

let windowRegistry: WindowRegistry | null = null

/** Wire the app's WindowManager once during bootstrap. */
export const setWindowRegistry = (registry: WindowRegistry): void => {
  windowRegistry = registry
}

export const assertTrustedSender = (event: IpcMainInvokeEvent): BrowserWindow => {
  const senderFrame = event.senderFrame
  if (senderFrame && senderFrame.parent !== null) {
    throw new ServiceError(ErrorCodes.SENDER_REJECTED, 'Capability calls are only allowed from top-level frames.')
  }
  const browserWindow = BrowserWindow.fromWebContents(event.sender as WebContents)
  if (!browserWindow) {
    throw new ServiceError(ErrorCodes.SENDER_REJECTED, 'Sender does not belong to a browser window.')
  }
  if (windowRegistry && !windowRegistry.get(browserWindow.id)) {
    throw new ServiceError(ErrorCodes.SENDER_REJECTED, 'Sender window is not tracked by the application.')
  }
  return browserWindow
}

/**
 * Register a validated capability handler. The wire response is always a
 * ServiceResult envelope.
 */
export const handleCapability = <TReq, TRes>(
  channel: string,
  schema: Schema<TReq>,
  handler: (request: TReq, context: GuardedContext) => Promise<TRes> | TRes,
): void => {
  ipcMain.handle(channel, async (event, rawPayload): Promise<ServiceResult<TRes>> => {
    try {
      const browserWindow = assertTrustedSender(event)
      const validation = schema.validate(rawPayload)
      if (!validation.ok) {
        throw new ServiceError(ErrorCodes.VALIDATION_FAILED, `Invalid payload: ${formatIssues(validation.issues)}`, {
          channel,
        })
      }
      const value = await handler(validation.value, { event, browserWindow, windowId: browserWindow.id })
      return serviceOk(value)
    } catch (error) {
      const serviceError = ServiceError.from(error)
      if (serviceError.code === ErrorCodes.SENDER_REJECTED) {
        log.warn(`[ipcGuard] ${channel}: rejected sender (${serviceError.message})`)
      } else if (serviceError.code === ErrorCodes.INTERNAL) {
        log.error(`[ipcGuard] ${channel}: ${serviceError.message}`)
      }
      return serviceErr(serviceError.serialize())
    }
  })
}

export const removeCapability = (channel: string): void => {
  ipcMain.removeHandler(channel)
}
