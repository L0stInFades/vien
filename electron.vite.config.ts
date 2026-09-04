import { defineConfig, externalizeDepsPlugin } from 'electron-vite'
import { resolve, basename } from 'path'
import { readFileSync, cpSync } from 'fs'
import { execSync } from 'child_process'
import { createRequire } from 'node:module'
import vue from '@vitejs/plugin-vue'
import type { Plugin } from 'vite'

const require = createRequire(import.meta.url)

// Version information
const packageJson = JSON.parse(readFileSync(new URL('package.json', import.meta.url), 'utf-8')) as {
  version: string
  dependencies?: Record<string, string>
}
const { version } = packageJson
const bundledMainDependencies = new Set(['chokidar', 'electron-store', 'plist'])
const externalMainDependencies = [
  'electron',
  ...Object.keys(packageJson.dependencies ?? {}).filter((name) => !bundledMainDependencies.has(name)),
]
let shortHash = 'N/A'
let fullHash = 'N/A'
try {
  shortHash = execSync('git rev-parse --short HEAD', { cwd: new URL('.', import.meta.url).pathname }).toString().trim()
  fullHash = execSync('git rev-parse HEAD', { cwd: new URL('.', import.meta.url).pathname }).toString().trim()
} catch (_) {}
const isStable = !!process.env.MARKTEXT_IS_STABLE
const versionString = isStable ? `v${version}` : `v${version} (${shortHash})`

// ---------------------------------------------------------------------------
// Custom plugins
// ---------------------------------------------------------------------------

/**
 * Treat .md imports as raw strings (replicates webpack's vue-html-loader / raw-loader for .md).
 * Note: .html template imports should use Vite's native `?raw` suffix instead.
 */
function mdRawPlugin(): Plugin {
  return {
    name: 'md-raw',
    load(id: string) {
      if (!id.endsWith('.md')) return null
      const content = readFileSync(id, 'utf-8')
      return `export default ${JSON.stringify(content)}`
    },
  }
}

/**
 * Snap.svg workaround — replicates `imports-loader?this=>window,fix=>module.exports=0`.
 * snap.svg uses a UMD pattern that references `this` and `module.exports`.
 * In Vite's ESM context the top-level `this` is undefined, so we wrap the
 * file in an IIFE that provides both globals.
 */
function snapSvgPlugin(): Plugin {
  return {
    name: 'snap-svg-workaround',
    transform(code: string, id: string) {
      if (!id.includes('snap.svg-min.js')) return null
      const browserCode = code.replace(/require\((['"])eve\1\)/g, 'window.eve')
      // Without `module` defined, snap.svg's UMD fallback assigns Snap to
      // `window.Snap`. Re-export it as the ESM default after the IIFE runs.
      return {
        code: `;(function(window) {\nvar fix = 0;\nvar module;\nvar exports;\n${browserCode}\n})(typeof window !== 'undefined' ? window : globalThis);\nexport default (typeof window !== 'undefined' ? window.Snap : globalThis.Snap);`,
        map: null,
      }
    },
  }
}

/**
 * SVG sprite plugin — replicates `svg-sprite-loader`.
 * Each imported .svg file returns `{ id, url, viewBox }` and injects its
 * `<symbol>` into a shared hidden SVG sprite on `document.body`.
 */
function svgSpritePlugin(): Plugin {
  return {
    name: 'svg-sprite',
    transform(_code: string, id: string) {
      if (!id.endsWith('.svg')) return null

      const svgContent = readFileSync(id, 'utf-8')
      const viewBoxMatch = svgContent.match(/viewBox="([^"]+)"/)
      const viewBox = viewBoxMatch ? viewBoxMatch[1] : '0 0 24 24'
      const iconId = `sprite-${basename(id, '.svg')}`

      const innerMatch = svgContent.match(/<svg[^>]*>([\s\S]*?)<\/svg>/i)
      const innerContent = (innerMatch ? innerMatch[1].trim() : '')
        .replace(/\\/g, '\\\\')
        .replace(/`/g, '\\`')
        .replace(/\$\{/g, '\\${')

      return {
        code: `
function _ensureSprite() {
  if (typeof document === 'undefined') return;
  var svg = document.getElementById('__vite_svg_sprite');
  if (!svg) {
    svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.id = '__vite_svg_sprite';
    svg.setAttribute('style', 'display:none;');
    svg.setAttribute('aria-hidden', 'true');
    if (document.body) {
      document.body.insertBefore(svg, document.body.firstChild);
    } else {
      document.addEventListener('DOMContentLoaded', function() {
        document.body.insertBefore(svg, document.body.firstChild);
      });
    }
  }
  if (!document.getElementById('${iconId}')) {
    var sym = document.createElementNS('http://www.w3.org/2000/svg', 'symbol');
    sym.id = '${iconId}';
    sym.setAttribute('viewBox', '${viewBox}');
    sym.innerHTML = \`${innerContent}\`;
    svg.appendChild(sym);
  }
}
_ensureSprite();
export default { id: '${iconId}', url: '#${iconId}', viewBox: '${viewBox}' };
`,
        map: null,
      }
    },
  }
}

// ---------------------------------------------------------------------------
// electron-vite config
// ---------------------------------------------------------------------------

export default defineConfig(({ mode }) => {
  const isDev = mode === 'development'

  return {
    // ---- Main Process -------------------------------------------------------
    main: {
      plugins: [
        externalizeDepsPlugin(),
        // Copy static/ → dist/electron/static/ after main build.
        // (viteStaticCopy doesn't run in SSR/node mode, so we use closeBundle.)
        {
          name: 'copy-static-dir',
          closeBundle() {
            cpSync(resolve('static'), resolve('dist/electron/static'), { recursive: true })
          },
        } satisfies Plugin,
      ],
      resolve: {
        alias: {
          common: resolve('src/common'),
        },
      },
      define: {
        // In dev, DefinePlugin-inject __static so globalSetting.js
        // (which only runs in non-dev) isn't needed during development.
        ...(isDev
          ? { __static: JSON.stringify(resolve('static')) }
          : {}),
        'global.MARKTEXT_VERSION': JSON.stringify(version),
        'global.MARKTEXT_VERSION_STRING': JSON.stringify(versionString),
        'global.MARKTEXT_IS_STABLE': JSON.stringify(isStable),
        'global.MARKTEXT_GIT_SHORT_HASH': JSON.stringify(shortHash),
        'global.MARKTEXT_GIT_HASH': JSON.stringify(fullHash),
      },
      build: {
        outDir: 'dist/electron',
        // Main runs first — it cleans the shared dir; preload + renderer skip clean.
        emptyOutDir: true,
        rollupOptions: {
          external: externalMainDependencies,
          output: { entryFileNames: 'main.js' },
        },
      },
    },

    // ---- Preload -----------------------------------------------------------
    preload: {
      plugins: [externalizeDepsPlugin()],
      build: {
        outDir: 'dist/electron',
        emptyOutDir: false,
        rollupOptions: {
          input: resolve('src/main/preload.ts'),
          external: ['electron'],
          output: { entryFileNames: 'preload.js', format: 'cjs' },
        },
      },
    },

    // ---- Renderer ----------------------------------------------------------
    renderer: {
      root: resolve('src/renderer'),
      plugins: [
        mdRawPlugin(),
        vue(),
        snapSvgPlugin(),
        svgSpritePlugin(),
      ],
      resolve: {
        extensions: ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json', '.vue'],
        alias: [
          // Node.js stubs — use regex for EXACT matching so 'fs' doesn't
          // accidentally swallow 'fs/promises' or 'fs-extra'.
          { find: /^node:fs\/promises$/, replacement: resolve('src/renderer/node/fs-promises-stub.js') },
          { find: /^fs\/promises$/, replacement: resolve('src/renderer/node/fs-promises-stub.js') },
          { find: /^node:fs$/, replacement: resolve('src/renderer/node/fs-browser-stub.js') },
          { find: /^fs$/, replacement: resolve('src/renderer/node/fs-browser-stub.js') },
          { find: /^fs-extra$/, replacement: resolve('src/renderer/node/fs-extra-stub.js') },
          { find: /^node:child_process$/, replacement: resolve('src/renderer/node/child-process-stub.js') },
          { find: /^child_process$/, replacement: resolve('src/renderer/node/child-process-stub.js') },
          { find: /^node:zlib$/, replacement: resolve('src/renderer/node/zlib-stub.js') },
          { find: /^zlib$/, replacement: resolve('src/renderer/node/zlib-stub.js') },
          // The sandboxed renderer only imports the path API from Node's
          // standard library. Keep this one targeted browser implementation
          // instead of pulling in the entire Node polyfill graph.
          { find: /^node:path$/, replacement: require.resolve('path-browserify') },
          { find: /^path$/, replacement: require.resolve('path-browserify') },
          // Regular path aliases
          { find: '@', replacement: resolve('src/renderer') },
          { find: 'common', replacement: resolve('src/common') },
          { find: 'muya', replacement: resolve('src/muya') },
          { find: 'main', replacement: resolve('src/main') },
          { find: 'snapsvg', replacement: resolve('src/muya/lib/assets/libs/snap.svg-min.js') },
          // Renderer-safe stubs for Node.js-only packages
          { find: /^electron-log$/, replacement: resolve('src/renderer/node/electron-log-renderer.js') },
          // vscode-ripgrep has NO renderer alias on purpose: search runs in
          // the main-process SearchService (SEARCH-001); any renderer import
          // of it must fail the build.
        ],
      },
      define: {
        'process.versions.MARKTEXT_VERSION': JSON.stringify(version),
        'process.versions.MARKTEXT_VERSION_STRING': JSON.stringify(versionString),
      },
      optimizeDeps: {
        // electron is not available in renderer; keep it external so Vite
        // doesn't try to bundle it.
        exclude: ['electron', 'fontmanager-redux', 'eve'],
      },
      build: {
        outDir: 'dist/electron',
        // Don't clean — main.js and preload.js are built first and must survive.
        emptyOutDir: false,
        sourcemap: isDev ? 'inline' : false,
        rollupOptions: {
          input: resolve('src/renderer/index.html'),
          external: ['electron'],
        },
      },
    },
  }
})
