'use strict'

const fs = require('node:fs')
const path = require('node:path')

const ALLOWED_LICENSES = new Set([
  'Apache-2.0',
  'BSD-2-Clause',
  'BSD-3-Clause',
  'CC-BY-3.0',
  'CC-BY-4.0',
  'CC0-1.0',
  'EPL-2.0',
  'ISC',
  'MIT',
  'MPL-2.0',
  'Unlicense',
  'WTFPL',
])

const getLicenseExpression = (manifest) => {
  const value = manifest.license ?? manifest.licenses
  if (typeof value === 'string') return value
  if (value && !Array.isArray(value) && typeof value.type === 'string') return value.type
  if (Array.isArray(value)) {
    return value
      .map((item) => (typeof item === 'string' ? item : item?.type))
      .filter(Boolean)
      .join(' OR ')
  }
  return 'UNKNOWN'
}

const getLicenseIds = (expression) => {
  return (expression.match(/[A-Za-z0-9.+-]+/g) ?? []).filter((token) => !['AND', 'OR', 'WITH'].includes(token))
}

const findNoticeText = (packageDir) => {
  const filenames = fs.readdirSync(packageDir)
  const licenseFile = filenames.find((filename) => /^(licen[cs]e|copying|notice)(?:\.|$)/i.test(filename))
  const readmeFile = filenames.find((filename) => /^readme(?:\.|$)/i.test(filename))
  const filename = licenseFile ?? readmeFile
  return filename
    ? fs.readFileSync(path.join(packageDir, filename), 'utf8')
    : 'No license text was included in the package.'
}

const collectDirectPackages = (rootDir) => {
  const rootManifest = JSON.parse(fs.readFileSync(path.join(rootDir, 'package.json'), 'utf8'))
  const packageNames = [
    ...Object.keys(rootManifest.dependencies ?? {}),
    ...Object.keys(rootManifest.optionalDependencies ?? {}),
  ]

  return Object.fromEntries(
    packageNames.map((name) => {
      const packageDir = path.join(rootDir, 'node_modules', ...name.split('/'))
      const manifest = JSON.parse(fs.readFileSync(path.join(packageDir, 'package.json'), 'utf8'))
      return [
        `${name}@${manifest.version}`,
        {
          licenses: getLicenseExpression(manifest),
          licenseText: findNoticeText(packageDir),
        },
      ]
    }),
  )
}

const asSummary = (packages) => {
  const totals = new Map()
  for (const { licenses } of Object.values(packages)) {
    totals.set(licenses, (totals.get(licenses) ?? 0) + 1)
  }
  return [...totals.entries()].map(([license, count]) => `├─ ${license}: ${count}`).join('\n')
}

const getLicenses = (rootDir, callback) => {
  try {
    const packages = collectDirectPackages(rootDir)
    const rejected = Object.entries(packages).filter(([, { licenses }]) => {
      const ids = getLicenseIds(licenses)
      return ids.length === 0 || ids.some((id) => !ALLOWED_LICENSES.has(id))
    })
    if (rejected.length > 0) {
      const details = rejected.map(([name, value]) => `${name} (${value.licenses})`).join(', ')
      throw new Error(`Disallowed or unknown licenses: ${details}`)
    }
    callback(null, packages, { asSummary })
  } catch (error) {
    callback(error)
  }
}

// Check that all production dependencies are allowed.
const validateLicenses = (rootDir) => {
  getLicenses(rootDir, (err, packages, checker) => {
    if (err) {
      console.log(`[ERROR] ${err}`)
      process.exit(1)
    }
    console.log(checker.asSummary(packages))
  })
}

module.exports = {
  getLicenses: getLicenses,
  validateLicenses: validateLicenses,
}
