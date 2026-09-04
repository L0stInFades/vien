import { resolve } from 'node:path'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['test/unit/specs/**/*.spec.js'],
    setupFiles: ['test/unit/setup.js'],
  },
  resolve: {
    alias: {
      common: resolve(import.meta.dirname, 'src/common'),
      muya: resolve(import.meta.dirname, 'src/muya'),
      '@': resolve(import.meta.dirname, 'src/renderer'),
    },
  },
})
