'use strict'

const fs = require('fs')
const path = require('path')
const thirdPartyChecker = require('../.electron-vue/thirdPartyChecker.js')
const rootDir = path.resolve(__dirname, '..')

thirdPartyChecker.getLicenses(rootDir, (err, packages) => {
  if (err) {
    console.error(`[ERROR] ${err}`)
    process.exitCode = 1
    return
  }

  let summary = ''
  let licenseList = ''
  let index = 1
  const addedKeys = {}
  Object.keys(packages).forEach(key => {
    if (/^babel-helper-vue-jsx-merge-props/.test(key) ||
      /^marktext/.test(key)) {
      // babel-helper-vue-jsx-merge-props: MIT licensed used by element-ui
      return
    }

    let packageName = key
    const nameRegex = /(^.+)(?:@)/.exec(key)
    if (nameRegex && nameRegex[1]) {
      packageName = nameRegex[1]
    }

    // Check if we already added this package
    if (addedKeys.hasOwnProperty(packageName)) {
      return
    }
    addedKeys[packageName] = 1

    const { licenses, licenseText } = packages[key]
    summary += `${index++}. ${packageName} (${licenses})\n`
    licenseList += `# ${packageName} (${licenses})
-------------------------------------------------\

${licenseText}
\n\n
`
  })


  const output = `# Third Party Notices
-------------------------------------------------

This file contains all third-party packages that are bundled and shipped with Vien.

-------------------------------------------------
# Summary
-------------------------------------------------

${summary}

-------------------------------------------------
# Licenses
-------------------------------------------------

${licenseList}
`
  // Third-party license bodies occasionally contain accidental line-ending
  // spaces. They are not part of the license text and make repository-wide
  // whitespace checks noisy, so normalize them in the generated artifact.
  const normalizedOutput = output.replace(/[ \t]+$/gm, '')
  fs.writeFileSync(path.resolve(rootDir, 'resources', 'THIRD-PARTY-LICENSES.txt'), normalizedOutput)
})
