import { resolve } from 'node:path'
import { defineConfig } from 'vitest/config'

/**
 * Performance benchmark profile (PLAN.md QUALITY-001 / §8.6).
 * Run via: pnpm run perf — writes perf-results.json for CI artifacts.
 * Kept out of the unit profile so PR runs stay fast.
 */
export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['test/perf/**/*.spec.js'],
    setupFiles: ['test/unit/setup.js'],
    testTimeout: 120000,
    hookTimeout: 120000,
  },
  resolve: {
    alias: {
      common: resolve(import.meta.dirname, 'src/common'),
      muya: resolve(import.meta.dirname, 'src/muya'),
      '@': resolve(import.meta.dirname, 'src/renderer'),
    },
  },
})
