const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawn } = require('node:child_process')
const { expect, test } = require('@playwright/test')
const { closeElectron, getElectronPath, launchElectron } = require('./helpers')

const createTempDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'vien-feature-'))

const writeFile = (pathname, content) => {
  fs.mkdirSync(path.dirname(pathname), { recursive: true })
  fs.writeFileSync(pathname, content, 'utf8')
}

test.describe('Feature regressions', () => {
  test('the app opens directly into a blank page and identifies itself as Vien', async () => {
    const userDataDir = createTempDir()
    const { app, page } = await launchElectron({ userDataDir })

    try {
      await expect(page.locator('.editor-tabs li.active')).toContainText('Untitled-1')
      await expect(page.locator('#ag-editor-id')).toBeVisible()
      await expect(page.locator('.new-file')).toHaveCount(0)

      await app.evaluate(({ BrowserWindow }) => {
        BrowserWindow.getAllWindows()[0].setSize(1240, 860)
      })

      await page.waitForTimeout(200)

      const metrics = await page.evaluate(() => {
        const root = document.querySelector('.editor-with-tabs')
        const editor = document.querySelector('#ag-editor-id')
        const rootRect = root.getBoundingClientRect()
        const editorRect = editor.getBoundingClientRect()

        return {
          clientWidth: root.clientWidth,
          scrollWidth: root.scrollWidth,
          editorWithinViewport: editorRect.right <= rootRect.right + 1,
          editorHasHeight: editorRect.height > 400,
        }
      })

      expect(metrics.scrollWidth).toBeLessThanOrEqual(metrics.clientWidth + 1)
      expect(metrics.editorWithinViewport).toBe(true)
      expect(metrics.editorHasHeight).toBe(true)

      await page.locator('#ag-editor-id').click()
      await page.keyboard.type('A page begins here.')
      await expect(page.locator('.new-file')).toHaveCount(1)

      await expect
        .poll(async () => {
          return app.evaluate(({ app: electronApp }) => electronApp.getName())
        })
        .toBe('Vien')
    } finally {
      await closeElectron(app)
    }
  })

  test('recent documents, about dialog, and settings persistence stay wired together', async () => {
    const userDataDir = createTempDir()
    const workspaceDir = createTempDir()
    const recentFile = path.join(workspaceDir, 'recent-note.md')
    const recentFolder = path.join(workspaceDir, 'drafts')
    const recentsPath = path.join(userDataDir, 'recently-used-documents.json')

    writeFile(recentFile, '# Recent note\n')
    fs.mkdirSync(recentFolder, { recursive: true })
    fs.mkdirSync(userDataDir, { recursive: true })
    fs.writeFileSync(recentsPath, JSON.stringify([recentFile, recentFolder], null, 2), 'utf8')

    const { app, page } = await launchElectron({ userDataDir })

    try {
      await expect(page.locator('.editor-tabs li.active')).toContainText('Untitled-1')
      await expect
        .poll(() => page.evaluate(() => window.api.ipc.invoke('mt::get-recently-used-documents')))
        .toEqual([
          {
            kind: 'file',
            name: 'recent-note.md',
            parentPath: workspaceDir,
            pathname: recentFile,
          },
          {
            kind: 'folder',
            name: 'drafts',
            parentPath: workspaceDir,
            pathname: recentFolder,
          },
        ])

      await page.evaluate(() => {
        window.api.ipc.send('mt::clear-recently-used-documents')
      })
      await expect.poll(() => JSON.parse(fs.readFileSync(recentsPath, 'utf8'))).toEqual([])

      await app.evaluate(({ BrowserWindow }) => {
        BrowserWindow.getAllWindows()[0].webContents.send('mt::about-dialog')
      })

      await expect(page.getByTestId('about-dialog')).toBeVisible()
      await expect(page.getByTestId('about-title')).toHaveText('Vien')
      await expect(page.getByTestId('about-version')).not.toHaveText('')
      await expect(page.getByTestId('about-logo')).toBeVisible()

      const settingsWindowPromise = app.waitForEvent('window')
      await app.evaluate(({ ipcMain }) => {
        ipcMain.emit('app-create-settings-window', 'editor')
      })
      const settingsPage = await settingsWindowPromise
      await settingsPage.waitForLoadState('domcontentloaded')

      await expect(settingsPage.getByTestId('pref-category-editor')).toHaveClass(/active/)

      const autoBracketRow = settingsPage.locator('.pref-switch-item', {
        hasText: 'Automatically close brackets when writing',
      })
      await autoBracketRow.locator('.el-switch').click()

      const preferencesPath = path.join(userDataDir, 'preferences.json')
      await expect.poll(() => JSON.parse(fs.readFileSync(preferencesPath, 'utf8')).autoPairBracket).toBe(false)
    } finally {
      await closeElectron(app)
    }
  })

  test('file tree navigation keeps deterministic structure and highlighted code renders', async () => {
    const projectDir = createTempDir()
    const nestedDir = path.join(projectDir, 'chapters')
    const nestedFile = path.join(nestedDir, 'code-sample.md')
    const rootFile = path.join(projectDir, 'README.md')

    writeFile(rootFile, '# Workspace\n')
    writeFile(
      nestedFile,
      [
        '# Code sample',
        '',
        '```javascript',
        'const answer = 42',
        'function greet(name) {',
        '  return `hello ' + '$' + '{name}`',
        '}',
        '```',
        '',
      ].join('\n'),
    )

    const { app, page } = await launchElectron([projectDir])

    try {
      await expect(page.getByTestId('tree-root-name')).toHaveText(path.basename(projectDir))

      const folderNode = page.locator('[data-testid="tree-folder"]', { hasText: 'chapters' })
      await folderNode.click()

      const fileNode = page.locator('[data-testid="tree-file"]', { hasText: 'code-sample.md' })
      await fileNode.click()

      await expect(page.locator('.editor-tabs li.active')).toContainText('code-sample.md')
      await expect(page.locator('.ag-code-content.language-javascript .token').first()).toBeVisible()
      await expect(fileNode).toHaveClass(/current/)
    } finally {
      await closeElectron(app)
    }
  })

  test('markdown open, resilient Mermaid rendering, and styled HTML export complete end to end', async () => {
    const userDataDir = createTempDir()
    const workspaceDir = createTempDir()
    const importFile = path.join(workspaceDir, 'drop-import.md')
    const exportFile = path.join(workspaceDir, 'drop-import.html')

    writeFile(
      importFile,
      [
        '# Drop Imported',
        '',
        '```javascript',
        'const answer = 42',
        '```',
        '',
        '```mermaid',
        'not-a-valid-mermaid-diagram',
        '```',
        '',
        '```mermaid',
        'flowchart LR',
        '  A[Latest source] --> B[Vien]',
        '```',
        '',
      ].join('\n'),
    )

    const { app, page } = await launchElectron({ userDataDir })

    try {
      await page.evaluate((pathname) => {
        window.api.ipc.send('mt::open-file-or-folder', pathname)
      }, importFile)

      await expect(page.locator('.editor-tabs li.active')).toContainText('drop-import.md')

      const mermaidFigures = page.locator('figure[data-role="MERMAID"]')
      await expect(mermaidFigures).toHaveCount(2)
      await expect(mermaidFigures.nth(0).locator('.ag-container-preview')).toHaveClass(/ag-math-error/)

      const validPreview = mermaidFigures.nth(1).locator('.ag-container-preview')
      const validSvg = validPreview.locator('svg')
      await expect(validSvg).toBeVisible()

      const previewMetrics = await validPreview.evaluate((preview) => {
        const svg = preview.querySelector('svg')
        const editor = document.querySelector('#ag-editor-id')
        if (!svg || !editor) {
          throw new Error('Unable to resolve the Mermaid preview geometry.')
        }

        const previewRect = preview.getBoundingClientRect()
        const svgRect = svg.getBoundingClientRect()
        const editorRect = editor.getBoundingClientRect()
        return {
          centered: Math.abs(svgRect.left + svgRect.width / 2 - (previewRect.left + previewRect.width / 2)) <= 1,
          withinEditor: svgRect.left >= editorRect.left - 1 && svgRect.right <= editorRect.right + 1,
          width: svgRect.width,
        }
      })

      expect(previewMetrics.centered).toBe(true)
      expect(previewMetrics.withinEditor).toBe(true)
      expect(previewMetrics.width).toBeGreaterThan(0)

      await app.evaluate(({ dialog }, filePath) => {
        dialog.showSaveDialog = async () => ({
          canceled: false,
          filePath,
        })
      }, exportFile)

      await app.evaluate(({ BrowserWindow }) => {
        BrowserWindow.getAllWindows()[0].webContents.send('mt::show-export-dialog', 'styledHtml')
      })

      await expect(page.getByTestId('export-dialog-title')).toBeVisible()
      await page.getByTestId('export-confirm').click()

      await expect.poll(() => fs.existsSync(exportFile)).toBe(true)
      await expect.poll(() => fs.readFileSync(exportFile, 'utf8')).toContain('Drop Imported')
      await expect.poll(() => fs.readFileSync(exportFile, 'utf8')).toContain('language-javascript')
      await expect.poll(() => fs.readFileSync(exportFile, 'utf8')).toContain('invalid-diagram')
      await expect.poll(() => fs.readFileSync(exportFile, 'utf8')).toContain('<svg')
      await expect.poll(() => fs.readFileSync(exportFile, 'utf8')).toContain('Latest source')
    } finally {
      await closeElectron(app)
    }
  })

  test('macOS window document state tracks the active editor tab', async () => {
    test.skip(process.platform !== 'darwin', 'macOS-only native window state')

    const userDataDir = createTempDir()
    const workspaceDir = createTempDir()
    const savePath = path.join(workspaceDir, 'native-window-state.md')

    const { app, page } = await launchElectron({ userDataDir })

    try {
      await expect(page.locator('.editor-tabs li.active')).toContainText('Untitled-1')

      await page.locator('#ag-editor-id').click()
      await page.keyboard.type('Native window state')

      await expect
        .poll(async () => {
          return app.evaluate(({ BrowserWindow }) => {
            return BrowserWindow.getAllWindows()[0].isDocumentEdited()
          })
        })
        .toBe(true)

      await app.evaluate(({ dialog }, filePath) => {
        dialog.showSaveDialog = async () => ({
          canceled: false,
          filePath,
        })
      }, savePath)

      await page.evaluate((defaultPath) => {
        const activeTab = document.querySelector('.editor-tabs li.active')
        const filename = activeTab?.querySelector('span')?.textContent?.trim() || 'Untitled-1'
        const id = activeTab?.getAttribute('data-id')

        if (!id) {
          throw new Error('Unable to resolve the active tab id before saving.')
        }

        window.api.ipc.send('mt::response-file-save', {
          id,
          filename,
          pathname: '',
          markdown: 'Native window state',
          options: {
            encoding: {
              encoding: 'utf8',
              isBom: false,
            },
            lineEnding: 'lf',
            adjustLineEndingOnSave: false,
            trimTrailingNewline: 3,
          },
          defaultPath,
        })
      }, workspaceDir)

      await expect.poll(() => fs.existsSync(savePath)).toBe(true)
      await expect
        .poll(async () => {
          return app.evaluate(({ BrowserWindow }) => {
            const window = BrowserWindow.getAllWindows()[0]
            return {
              documentEdited: window.isDocumentEdited(),
              representedFilename: window.getRepresentedFilename(),
            }
          })
        })
        .toEqual({
          documentEdited: false,
          representedFilename: savePath,
        })

      await page.evaluate(() => {
        window.api.localEmit('mt::editor-close-tab')
      })

      await expect(page.locator('.editor-tabs li.active')).toContainText('Untitled-1')
      await expect
        .poll(async () => {
          return app.evaluate(({ BrowserWindow }) => {
            const window = BrowserWindow.getAllWindows()[0]
            return {
              documentEdited: window.isDocumentEdited(),
              representedFilename: window.getRepresentedFilename(),
            }
          })
        })
        .toEqual({
          documentEdited: false,
          representedFilename: '',
        })
    } finally {
      await closeElectron(app)
    }
  })

  test('reopens a window when a second launch targets a running instance without windows', async () => {
    const userDataDir = createTempDir()
    const { app, page } = await launchElectron({ userDataDir })
    let secondProcess = null

    try {
      await page.waitForLoadState('domcontentloaded')

      await app.evaluate(({ BrowserWindow }) => {
        const [window] = BrowserWindow.getAllWindows()
        window.destroy()
      })

      await expect
        .poll(async () => {
          return app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length)
        })
        .toBe(0)

      secondProcess = spawn(getElectronPath(), ['dist/electron/main.js', '--user-data-dir', userDataDir], {
        cwd: process.cwd(),
        stdio: 'ignore',
      })

      await expect
        .poll(async () => {
          return app.evaluate(({ BrowserWindow }) => BrowserWindow.getAllWindows().length)
        })
        .toBe(1)
    } finally {
      if (secondProcess && !secondProcess.killed) {
        secondProcess.kill('SIGKILL')
      }
      await closeElectron(app)
    }
  })
})
