import { defineConfig } from 'vitest/config'
import { resolve } from 'path'

/**
 * Performance benchmark profile (PLAN.md QUALITY-001 / §8.6).
 * Run via: pnpm run perf  — writes perf-results.json for CI artifacts.
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
      common: resolve(__dirname, 'src/common'),
      muya: resolve(__dirname, 'src/muya'),
      '@': resolve(__dirname, 'src/renderer'),
    },
  },
})
