const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { launchElectron, closeElectron } = require('../test/e2e/helpers')

const projectRoot = path.resolve(__dirname, '..')
const outputDir = path.resolve(process.argv[2] || path.join(projectRoot, 'docs', 'debug-screenshots'))
const viewport = { width: 1512, height: 982 }
const capturedShots = []

const ensureCleanDir = (dirPath) => {
  fs.rmSync(dirPath, { recursive: true, force: true })
  fs.mkdirSync(dirPath, { recursive: true })
}

const createTempDir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'vien-ui-debug-'))

const writeFile = (pathname, content) => {
  fs.mkdirSync(path.dirname(pathname), { recursive: true })
  fs.writeFileSync(pathname, content, 'utf8')
}

const registerShot = ({ filename, title, description, size }) => {
  capturedShots.push({ filename, title, description, size })
}

const saveShot = async (page, shot) => {
  await page.screenshot({ path: path.join(outputDir, shot.filename) })
  registerShot(shot)
}

const renderGallery = () => {
  const cards = capturedShots
    .map(({ filename, title, description, size }) => {
      return [
        '<article class="shot-card">',
        `  <img src="./${filename}" alt="${title}" />`,
        '  <div class="shot-copy">',
        `    <h2>${title}</h2>`,
        `    <p>${description}</p>`,
        `    <span>${size.width} × ${size.height}</span>`,
        '  </div>',
        '</article>',
      ].join('\n')
    })
    .join('\n')

  return [
    '<!doctype html>',
    '<html lang="en">',
    '  <head>',
    '    <meta charset="utf-8" />',
    '    <meta name="viewport" content="width=device-width, initial-scale=1" />',
    '    <title>Vien UI Debug Gallery</title>',
    '    <style>',
    '      :root { color-scheme: light; }',
    '      * { box-sizing: border-box; }',
    '      body { margin: 0; padding: 40px; font-family: "SF Pro Text", "Helvetica Neue", sans-serif; background: linear-gradient(180deg, #f6f4ef, #edf2f8); color: #1d1d1f; }',
    '      main { max-width: 1480px; margin: 0 auto; }',
    '      h1 { margin: 0; font-size: 42px; letter-spacing: -0.04em; }',
    '      .intro { max-width: 720px; margin: 14px 0 28px; color: #5f6470; line-height: 1.7; }',
    '      .shot-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 24px; }',
    '      .shot-card { overflow: hidden; border-radius: 28px; border: 1px solid rgba(29, 29, 31, 0.08); background: rgba(255, 255, 255, 0.72); box-shadow: 0 24px 60px rgba(24, 39, 75, 0.08); backdrop-filter: blur(18px); }',
    '      .shot-card img { display: block; width: 100%; background: white; }',
    '      .shot-copy { padding: 18px 20px 22px; }',
    '      .shot-copy h2 { margin: 0; font-size: 19px; }',
    '      .shot-copy p { margin: 10px 0 12px; color: #5f6470; line-height: 1.6; }',
    '      .shot-copy span { font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: #6a9f7b; }',
    '    </style>',
    '  </head>',
    '  <body>',
    '    <main>',
    '      <h1>Vien UI Debug Gallery</h1>',
    '      <p class="intro">Fresh screenshots captured from the packaged interaction paths. Use this page to spot spacing regressions, hierarchy drift, and visual collisions before shipping.</p>',
    `      <section class="shot-grid">${cards}</section>`,
    '    </main>',
    '  </body>',
    '</html>',
  ].join('\n')
}

const setWindowSize = async (app, { width, height }) => {
  await app.evaluate(({ BrowserWindow }, size) => {
    const [window] = BrowserWindow.getAllWindows()
    if (!window) {
      return
    }
    window.setSize(size.width, size.height)
    window.center()
  }, { width, height })
}

const scrollToTop = async (page) => {
  await page.evaluate(() => {
    window.scrollTo(0, 0)
    const editor = document.querySelector('.editor-component')
    if (editor) {
      editor.scrollTop = 0
    }
  })
}

const captureBlankEditorShot = async () => {
  const userDataDir = createTempDir()
  const { app, page } = await launchElectron({ userDataDir })

  try {
    await page.setViewportSize(viewport)
    await setWindowSize(app, viewport)
    await page.locator('#ag-editor-id').waitFor({ state: 'visible' })
    await page.waitForTimeout(400)
    await scrollToTop(page)
    await saveShot(page, {
      filename: 'editor-blank.png',
      title: 'Editor / Blank Page',
      description: 'Warm paper baseline for the empty writing state, without the old dashboard layer.',
      size: viewport,
    })

    await app.evaluate(({ BrowserWindow }) => {
      BrowserWindow.getAllWindows()[0].webContents.send('mt::show-command-palette')
    })
    await page.locator('.commands li').first().waitFor({ state: 'visible', timeout: 8000 })
    await page.waitForTimeout(200)
    await saveShot(page, {
      filename: 'command-palette.png',
      title: 'Command Palette',
      description: 'Overlay command surface: input hairline, quiet rows, muted shortcut chips.',
      size: viewport,
    })
    await page.keyboard.press('Escape')
  } finally {
    await closeElectron(app)
  }
}

const captureChromeShots = async () => {
  const workspaceDir = createTempDir()
  writeFile(
    path.join(workspaceDir, 'notes.md'),
    ['# 晨间笔记', '', '今天想把界面收拾得更安静一点，像一张可以久坐的书桌。', '', '## 待办', '', '- 收敛标题栏', '- 整理侧栏层级', '- 统一浮层语言', ''].join('\n'),
  )
  writeFile(
    path.join(workspaceDir, 'journal.md'),
    ['# Journal', '', 'A quiet page kept for long-form writing.', '', '## Morning', '', 'Coffee, sunlight, and a clean sheet of paper.', ''].join('\n'),
  )
  writeFile(
    path.join(workspaceDir, 'ideas', 'draft.md'),
    ['# Draft', '', 'Work in progress.', ''].join('\n'),
  )

  const { app, page } = await launchElectron([workspaceDir])

  try {
    await page.setViewportSize(viewport)
    await setWindowSize(app, viewport)
    await page.locator('#ag-editor-id').waitFor({ state: 'visible' })
    await app.evaluate(({ BrowserWindow }) => {
      BrowserWindow.getAllWindows()[0].webContents.send('mt::set-view-layout', {
        showSideBar: true,
        showTabBar: true,
      })
    })
    await page.locator('.project-tree').waitFor({ state: 'visible', timeout: 8000 })
    await page.locator('.project-tree >> text=notes.md').first().click()
    await page.locator('.project-tree >> text=journal.md').first().click()
    await page.waitForTimeout(500)
    await saveShot(page, {
      filename: 'chrome-sidebar.png',
      title: 'Chrome / Sidebar + Tabs',
      description: 'Working-window baseline: icon rail, file tree, tab strip, and title bar together.',
      size: viewport,
    })

    await app.evaluate(({ BrowserWindow }) => {
      BrowserWindow.getAllWindows()[0].webContents.send('mt::execute-command-by-id', 'edit.find')
    })
    await page.locator('.search-bar').waitFor({ state: 'visible' })
    await page.waitForTimeout(200)
    await saveShot(page, {
      filename: 'search-bar.png',
      title: 'Find / Replace Bar',
      description: 'Floating search surface over the paper: quiet toggles and hairline input.',
      size: viewport,
    })
    await page.keyboard.press('Escape')
  } finally {
    await closeElectron(app)
  }
}

const captureAboutShot = async () => {
  const userDataDir = createTempDir()
  const { app, page } = await launchElectron({ userDataDir })

  try {
    await page.setViewportSize(viewport)
    await setWindowSize(app, viewport)
    await app.evaluate(({ BrowserWindow }) => {
      BrowserWindow.getAllWindows()[0].webContents.send('mt::about-dialog')
    })
    await page.getByTestId('about-dialog').waitFor({ state: 'visible' })
    await page.waitForTimeout(500)
    await saveShot(page, {
      filename: 'about.png',
      title: 'About Dialog',
      description: 'Brand panel and release copy, useful for checking visual tone and spacing in overlays.',
      size: viewport,
    })
  } finally {
    await closeElectron(app)
  }
}

const captureSettingsShot = async () => {
  const userDataDir = createTempDir()
  const { app } = await launchElectron({ userDataDir })

  try {
    const settingsWindowPromise = app.waitForEvent('window')
    await app.evaluate(({ ipcMain }) => {
      ipcMain.emit('app-create-settings-window', 'editor')
    })

    const settingsPage = await settingsWindowPromise
    await settingsPage.waitForLoadState('domcontentloaded')
    await settingsPage.setViewportSize(viewport)
    await settingsPage.getByTestId('pref-category-editor').waitFor({ state: 'visible' })
    await saveShot(settingsPage, {
      filename: 'settings-editor.png',
      title: 'Preferences / Editor',
      description: 'Settings window baseline for density, control alignment, and navigation hierarchy.',
      size: viewport,
    })
  } finally {
    await closeElectron(app)
  }
}

const captureEditorShot = async () => {
  const workspaceDir = createTempDir()
  const docPath = path.join(workspaceDir, 'design-review.md')
  writeFile(
    docPath,
    [
      '# 夜里把页面留给文字',
      '',
      'Vien 现在应该更像一张纸，而不是一块面板。正文宽度要克制，层级要安静，`inline code` 也要像被认真排进版心里。',
      '',
      '## 标题层级要有呼吸',
      '',
      '同一份文稿里，一级标题、二级标题、三级标题应该一眼分出轻重，而不是只靠字号机械缩放。',
      '',
      '### 代码块要像一张插页',
      '',
      '```javascript',
      'const answer = 42',
      'function greet(name) {',
      "  return `hello ${name}`",
      '}',
      '```',
      '',
      '> 引文不该只是左边一条线。它也应该有自己的空气感和停顿。',
      '',
      '最后这一段用来观察正文颜色、段落宽度、选区颜色和整页的纸面感。',
      '',
    ].join('\n'),
  )

  const { app, page } = await launchElectron([docPath])

  try {
    await page.setViewportSize(viewport)
    await setWindowSize(app, viewport)
    await page.locator('.ag-code-content.language-javascript .token').first().waitFor({ state: 'visible' })
    await saveShot(page, {
      filename: 'editor-document.png',
      title: 'Editor / Sample Document',
      description: 'Document rendering baseline for headings, code blocks, spacing, and line length.',
      size: viewport,
    })

    await page.evaluate(() => {
      const paragraphs = Array.from(document.querySelectorAll('#ag-editor-id p'))
      const target = paragraphs.find((paragraph) => paragraph.textContent?.includes('最后这一段'))
      const walker = target ? document.createTreeWalker(target, NodeFilter.SHOW_TEXT) : null
      let textNode = walker?.nextNode() || null
      while (textNode && !textNode.textContent?.includes('最后这一段')) {
        textNode = walker.nextNode()
      }
      const content = textNode?.textContent || ''

      if (!target || !textNode || textNode.nodeType !== Node.TEXT_NODE || !content) {
        throw new Error('Unable to resolve selection screenshot text.')
      }
      const highlightLength = Math.min(18, content.length)
      const highlight = document.createElement('span')
      highlight.className = 'ag-selection'
      highlight.textContent = content.slice(0, highlightLength)
      textNode.replaceWith(highlight, document.createTextNode(content.slice(highlightLength)))
    })
    await page.waitForTimeout(180)
    await saveShot(page, {
      filename: 'editor-selection.png',
      title: 'Editor / Selection',
      description: 'Selection-state proof for the softer sage highlight used on the writing surface.',
      size: viewport,
    })

    await page.evaluate(() => {
      const highlight = document.querySelector('#ag-editor-id .ag-selection')
      if (highlight) highlight.replaceWith(document.createTextNode(highlight.textContent || ''))
    })

    // Triple-click a paragraph to select it and raise the inline format picker.
    await page.locator('#ag-editor-id p', { hasText: '最后这一段' }).first().click({ clickCount: 3 })
    await page.waitForTimeout(700)
    await saveShot(page, {
      filename: 'format-picker.png',
      title: 'Editor / Format Picker',
      description: 'Inline formatting float on a text selection: unified radius, border, and shadow.',
      size: viewport,
    })
  } finally {
    await closeElectron(app)
  }
}

const main = async () => {
  ensureCleanDir(outputDir)
  await captureBlankEditorShot()
  await captureChromeShots()
  await captureAboutShot()
  await captureSettingsShot()
  await captureEditorShot()
  writeFile(path.join(outputDir, 'manifest.json'), JSON.stringify(capturedShots, null, 2))
  writeFile(path.join(outputDir, 'index.html'), renderGallery())
  console.log(`Captured UI debug screenshots in ${outputDir}`)
}

main().catch((error) => {
  console.error(error.stack || error.message || error)
  process.exit(1)
})
