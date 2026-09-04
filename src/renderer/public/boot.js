/**
 * Pre-module bootstrap (classic script, runs before the Vite module graph).
 * Lives in public/ so neither dev nor build transforms it — required for the
 * strict CSP in index.html (script-src 'self', no inline scripts).
 */

// Provide the small set of Node-style globals used by browser-ready modules.
// Electron's preload cannot expose `process` because contextIsolation is
// enabled and nodeIntegration is off.
// A few browser-ready dependencies still use the conventional Node `global`
// alias even though they do not need any other Node APIs.
window.global = globalThis

if (typeof process === 'undefined') {
  window.process = {
    env: {},
    browser: true,
    version: 'v22.0.0',
    versions: {},
    platform: 'browser',
    nextTick: (fn) => {
      Promise.resolve().then(fn)
    },
  }
} else if (!process.env) {
  process.env = {}
}
// Paint the loading surface in the requested theme before any content shows.
;(() => {
  const params = new URLSearchParams(window.location.search)
  const THEME_SURFACES = {
    'one-dark': 'rgb(27, 29, 33)',
    dark: 'rgb(24, 25, 29)',
    graphite: 'rgb(34, 38, 42)',
    'material-dark': 'rgb(32, 29, 27)',
    light: 'rgb(248, 244, 238)',
    ulysses: 'rgb(244, 241, 235)',
  }
  const THEME_MARKS = {
    'one-dark': 'rgba(240, 234, 224, 0.72)',
    dark: 'rgba(240, 234, 224, 0.72)',
    graphite: 'rgba(240, 234, 224, 0.68)',
    'material-dark': 'rgba(244, 236, 225, 0.72)',
    light: 'rgba(56, 48, 39, 0.62)',
    ulysses: 'rgba(64, 54, 41, 0.62)',
  }

  const theme = params.get('theme')
  document.documentElement.style.setProperty('--loading-bg', THEME_SURFACES[theme] || 'rgb(248, 244, 238)')
  document.documentElement.style.setProperty('--loading-mark', THEME_MARKS[theme] || 'rgba(56, 48, 39, 0.62)')
})()
